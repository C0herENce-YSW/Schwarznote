//
//  NoteDetailView.swift
//  Schwarznote
//

import SwiftUI

/// Note detail like the web modal: media on the left; author, text, actions and comments on the right.
struct NoteDetailView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(ShortcutCenter.self) private var shortcuts
    @Environment(\.dismiss) private var dismiss
    @State private var model: NoteDetailModel
    @State private var draft = ""
    @State private var replyTarget: Comment?
    @FocusState private var composerFocused: Bool
    private let focusComposerOnOpen: Bool

    init(note: Note) {
        _model = State(initialValue: NoteDetailModel(note: note))
        focusComposerOnOpen = false
    }

    /// Opens a note another screen already loaded, e.g. from the 评论 shortcut in the 私信 viewer.
    init(model: NoteDetailModel, focusComposer: Bool) {
        _model = State(initialValue: model)
        focusComposerOnOpen = focusComposer
    }

    private var note: Note { model.note }

    /// Until the detail loads, show the feed card's cover.
    private var media: [MediaItem] {
        model.detail?.media ?? [MediaItem(id: 0, kind: .image, imageURL: note.coverURL, videoURL: nil,
                                          aspectRatio: note.coverAspectRatio)]
    }

    var body: some View {
        HStack(spacing: 0) {
            MediaViewer(media: media)

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    header
                    actionBar
                    Divider()
                    composer
                    commentList
                }
                .padding(60)
            }
            .frame(width: 820)
            .background(.regularMaterial)
        }
        .ignoresSafeArea()
        .onExitCommand { dismiss() }
        .task { await model.load(client: auth.client) }
        .task {
            // Give the cover a moment to settle so the focus change sticks.
            guard focusComposerOnOpen else { return }
            try? await Task.sleep(for: .milliseconds(400))
            composerFocused = true
        }
        .onAppear { shortcuts.handler = handleShortcut }
        .onDisappear { shortcuts.handler = nil }
        .alert("操作失败", isPresented: Binding(
            get: { model.actionError != nil },
            set: { if !$0 { model.actionError = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(model.actionError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 20) {
                AvatarView(author: model.detail?.author ?? note.author, size: 72)
                Text((model.detail?.author ?? note.author).nickname)
                    .font(.title3.weight(.semibold))
            }

            Text(model.detail?.title.isEmpty == false ? model.detail!.title : note.title)
                .font(.title2.bold())

            if let detail = model.detail {
                VStack(alignment: .leading, spacing: 20) {
                    if !detail.text.isEmpty {
                        Text(detail.text)
                    }
                    Text([detail.time?.formatted(date: .abbreviated, time: .omitted), detail.ipLocation]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Focusable so long text can be scrolled to with the remote.
                .focusable()
            } else if let error = model.loadError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func handleShortcut(_ action: ShortcutAction) {
        // Keys typed into the comment box are text, not shortcuts.
        guard !composerFocused else { return }
        switch action {
        case .like: requireLogin { await model.toggleLike(client: auth.client) }
        case .collect: requireLogin { await model.toggleCollect(client: auth.client) }
        case .comment:
            replyTarget = nil
            composerFocused = true
        case .backToTop: break
        }
    }

    private var actionBar: some View {
        HStack(spacing: 20) {
            if let detail = model.detail {
                actionButton(detail.likes, systemImage: detail.liked ? "heart.fill" : "heart",
                             active: detail.liked) { await model.toggleLike(client: auth.client) }
                actionButton(detail.collects, systemImage: detail.collected ? "star.fill" : "star",
                             active: detail.collected) { await model.toggleCollect(client: auth.client) }
                Button {
                    replyTarget = nil
                    composerFocused = true
                } label: {
                    Label(detail.commentCount, systemImage: "bubble.right")
                }
                .buttonStyle(ChipStyle(isSelected: false))
            }
        }
    }

    private func actionButton(_ count: String, systemImage: String, active: Bool,
                              action: @escaping () async -> Void) -> some View {
        Button {
            requireLogin { await action() }
        } label: {
            Label(count, systemImage: systemImage)
                .foregroundStyle(active ? Color.accentColor : .primary)
        }
        .buttonStyle(ChipStyle(isSelected: active))
    }

    private func requireLogin(_ action: @escaping () async -> Void) {
        guard auth.isLoggedIn else {
            model.actionError = "请先在“我”页面扫码登录"
            return
        }
        Task { await action() }
    }

    // MARK: - Comments

    private var composer: some View {
        HStack(spacing: 20) {
            TextField(replyTarget.map { "回复 \($0.author.nickname)" } ?? "说点什么…", text: $draft)
                .focused($composerFocused)
                .onSubmit(send)
            if replyTarget != nil {
                Button("取消回复") { replyTarget = nil }
            }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let target = replyTarget
        requireLogin {
            if await model.post(text, replyingTo: target, client: auth.client) {
                draft = ""
                replyTarget = nil
            }
        }
    }

    @ViewBuilder
    private var commentList: some View {
        let comments = model.comments

        if comments.items.isEmpty, let error = comments.error {
            ErrorView(message: error) { await comments.retry() }
        } else if comments.items.isEmpty, !comments.isLoading {
            Text("还没有评论")
                .foregroundStyle(.secondary)
        }

        LazyVStack(alignment: .leading, spacing: 28) {
            ForEach(comments.items) { comment in
                VStack(alignment: .leading, spacing: 16) {
                    commentRow(comment)
                    ForEach(comment.replies) { reply in
                        commentRow(reply)
                            .padding(.leading, 76)
                    }
                    if comment.hasMoreReplies {
                        Button("展开更多回复") {
                            Task { await model.loadMoreReplies(for: comment, client: auth.client) }
                        }
                        .buttonStyle(ChipStyle(isSelected: false))
                        .padding(.leading, 76)
                    }
                }
                .task { await comments.loadMoreIfNeeded(current: comment) }
            }
        }

        if comments.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }

    private func commentRow(_ comment: Comment) -> some View {
        CommentRow(comment: comment) {
            replyTarget = comment
            composerFocused = true
        } onLike: {
            requireLogin { await model.toggleLike(of: comment, client: auth.client) }
        }
    }
}

/// One comment: selecting the text replies to it; the heart likes it.
struct CommentRow: View {
    let comment: Comment
    let onReply: () -> Void
    let onLike: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Button(action: onReply) {
                HStack(alignment: .top, spacing: 20) {
                    AvatarView(author: comment.author, size: 56)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Text(comment.author.nickname)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if comment.isByNoteAuthor {
                                Text("作者")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.25), in: Capsule())
                            }
                        }
                        if let replyTo = comment.replyTo {
                            Text("回复 ").foregroundStyle(.secondary) + Text(replyTo).bold() + Text("：" + comment.content)
                        } else {
                            Text(comment.content)
                        }
                        Text([comment.time?.formatted(.relative(presentation: .named)), comment.ipLocation]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(RowStyle())

            Button(action: onLike) {
                VStack(spacing: 4) {
                    Image(systemName: comment.liked ? "heart.fill" : "heart")
                        .foregroundStyle(comment.liked ? Color.accentColor : .secondary)
                    Text(comment.likes)
                        .font(.caption)
                }
            }
            .buttonStyle(RowStyle())
        }
    }
}

/// Subtle highlight for list rows, instead of the default button platter.
struct RowStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16).fill(.white.opacity(isFocused ? 0.15 : 0))
            )
            .scaleEffect(isFocused ? 1.02 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
