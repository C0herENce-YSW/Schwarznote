//
//  SharedContentViewer.swift
//  Schwarznote
//

import SwiftUI

/// Full-screen viewer for what both people shared in a 私信 conversation: images and notes,
/// oldest to newest. Swiping (or clicking) down goes to the next one, up to the previous one;
/// left and right still move through a note's pictures, and selecting a picture opens it full
/// screen. The 点赞 / 收藏 / 评论 shortcuts act on the note on screen. The back button closes it.
struct SharedContentViewer: View {
    let model: ChatModel

    @Environment(AuthModel.self) private var auth
    @Environment(ShortcutCenter.self) private var shortcuts
    @State private var currentID: String
    @State private var forward = true
    /// One per shared note, keyed by note ID, so likes survive paging back and forth.
    @State private var notes: [String: NoteDetailModel] = [:]
    @State private var toast: String?
    @State private var lastStep = Date.distantPast
    @State private var fullScreenImage: URL?
    @State private var commenting: NoteDetailModel?
    @FocusState private var pageFocused: Bool

    init(model: ChatModel, startAt messageID: String) {
        self.model = model
        _currentID = State(initialValue: messageID)
    }

    private var items: [ChatMessage] { model.messages.filter(\.content.isShared) }
    private var index: Int? { items.firstIndex { $0.id == currentID } }

    var body: some View {
        ZStack {
            if let index {
                page(items[index])
                    .id(currentID)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .bottom : .top),
                        removal: .move(edge: forward ? .top : .bottom)
                    ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Keep pages from sliding over the bars while they move; the background stays full screen.
        .clipped()
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .bottom) { toastView }
        .background(SwipeMonitor { direction in
            step(direction == .down ? 1 : -1)
        })
        .onMoveCommand { direction in
            switch direction {
            case .down: step(1)
            case .up: step(-1)
            default: break
            }
        }
        .task(id: currentID) { await loadNote() }
        .onAppear {
            pageFocused = true
            shortcuts.handler = handleShortcut
        }
        .onDisappear { shortcuts.handler = nil }
        .fullScreenCover(item: Binding(
            get: { fullScreenImage.map { PlayableVideo(url: $0) } },
            set: { fullScreenImage = $0?.url }
        )) { image in
            PhotoViewerScreen(
                media: [MediaItem(id: 0, kind: .image, imageURL: image.url, videoURL: nil, aspectRatio: 1)],
                startAt: 0
            )
        }
        .fullScreenCover(item: Binding(
            get: { commenting.map(OpenNote.init) },
            set: { commenting = $0?.model }
        ), onDismiss: {
            // The note detail clears the shortcut handler when it closes; take it back.
            shortcuts.handler = handleShortcut
        }) { open in
            NoteDetailView(model: open.model, focusComposer: true)
        }
    }

    // MARK: - Paging

    private func step(_ delta: Int) {
        // The video player owns the remote while it's open.
        guard !shortcuts.isPaused, let index else { return }
        // A swipe can also arrive as a move command; count it once.
        guard Date().timeIntervalSince(lastStep) > 0.35 else { return }
        lastStep = Date()

        let target = index + delta
        if items.indices.contains(target) {
            go(to: items[target].id, forward: delta > 0)
        } else if delta < 0, !model.reachedStart {
            Task {
                let before = items.count
                await model.loadEarlier()
                if let current = self.index, current > 0, items.count > before {
                    go(to: items[current - 1].id, forward: false)
                } else {
                    showToast("已经是第一条了")
                }
            }
        } else {
            showToast(delta < 0 ? "已经是第一条了" : "已经是最后一条了")
        }
    }

    private func go(to id: String, forward: Bool) {
        // Set the direction first so the outgoing page leaves the right way, then switch.
        self.forward = forward
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.35)) { currentID = id }
            pageFocused = true
        }
    }

    private func showToast(_ text: String) {
        withAnimation { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if toast == text { withAnimation { toast = nil } }
        }
    }

    // MARK: - Shortcuts

    /// The note model for the item on screen, if it's a shared note.
    private var currentNote: NoteDetailModel? {
        guard let index, case .card(let card) = items[index].content, let link = card.note else { return nil }
        return notes[link.id]
    }

    private func handleShortcut(_ action: ShortcutAction) {
        guard action != .backToTop else { return }
        guard let note = currentNote else {
            showToast("只有分享的笔记可以\(action.title)")
            return
        }
        guard let detail = note.detail else {
            showToast("笔记还没加载好")
            return
        }
        let client = auth.client
        switch action {
        case .like:
            showToast(detail.liked ? "已取消点赞" : "已点赞")
            Task { await note.toggleLike(client: client); reportFailure(of: note) }
        case .collect:
            showToast(detail.collected ? "已取消收藏" : "已收藏")
            Task { await note.toggleCollect(client: client); reportFailure(of: note) }
        case .comment:
            commenting = note
        case .backToTop:
            break
        }
    }

    private func reportFailure(of note: NoteDetailModel) {
        if let error = note.actionError {
            note.actionError = nil
            showToast("操作失败：\(error)")
        }
    }

    // MARK: - Pages

    @ViewBuilder
    private func page(_ message: ChatMessage) -> some View {
        switch message.content {
        case .image(let url):
            Button { fullScreenImage = url } label: {
                RemoteImage(url: url, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(BareButtonStyle())
            .padding(.horizontal, 80)
            .padding(.top, 150)
            .padding(.bottom, 60)
            .focused($pageFocused)
        case .card(let card):
            if let link = card.note, let note = notes[link.id], let detail = note.detail {
                notePage(detail)
            } else {
                cardPage(card, error: card.note.flatMap { notes[$0.id]?.loadError })
            }
        default:
            EmptyView()
        }
    }

    private func notePage(_ detail: NoteDetail) -> some View {
        HStack(spacing: 0) {
            // Holds the focus: the thumbnails or the 全屏查看 / 播放 button.
            MediaViewer(media: detail.media)
                .padding(.top, 110)
                .frame(maxWidth: .infinity)
                // The thumbnail strip would otherwise run under the text column.
                .clipped()

            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 18) {
                    AvatarView(author: detail.author, size: 64)
                    Text(detail.author.nickname)
                        .font(.headline)
                }
                if !detail.title.isEmpty {
                    Text(detail.title)
                        .font(.title3.bold())
                }
                Text(detail.text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(14)
                Spacer(minLength: 0)
                HStack(spacing: 36) {
                    Label(detail.likes, systemImage: detail.liked ? "heart.fill" : "heart")
                        .foregroundStyle(detail.liked ? Color.accentColor : .secondary)
                    Label(detail.collects, systemImage: detail.collected ? "star.fill" : "star")
                        .foregroundStyle(detail.collected ? Color.accentColor : .secondary)
                    Label(detail.commentCount, systemImage: "bubble.right")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                if let keys = shortcutSummary {
                    Text(keys)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(50)
            .padding(.top, 110)
            .frame(width: 760, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// e.g. "播放/暂停 点赞 · 键盘 C 评论", from the bindings in 设置 → 快捷键.
    private var shortcutSummary: String? {
        let parts = [ShortcutAction.like, .collect, .comment].compactMap { action in
            shortcuts.bindings[action].map { "\($0.name) \(action.title)" }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// A card that isn't a note, or a note that is still loading or failed to load.
    private func cardPage(_ card: ChatCard, error: String?) -> some View {
        VStack(spacing: 36) {
            RemoteImage(url: card.imageURL, contentMode: .fit)
                .frame(maxWidth: 900, maxHeight: 640)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            Text(card.title.isEmpty ? "[卡片]" : card.title)
                .font(.title3)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            } else if card.note != nil {
                ProgressView()
            }
        }
        .padding(.top, 110)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusable()
        .focused($pageFocused)
    }

    private func loadNote() async {
        guard let index, case .card(let card) = items[index].content, let link = card.note else { return }
        let note = notes[link.id] ?? NoteDetailModel(
            note: Note(id: link.id, xsecToken: link.xsecToken, title: card.title,
                       author: Author(id: "", nickname: "", avatarURL: nil), coverURL: card.imageURL),
            xsecSource: link.xsecSource
        )
        notes[link.id] = note
        await note.loadDetail(client: auth.client)
    }

    // MARK: - Overlays

    @ViewBuilder
    private var topBar: some View {
        if let index {
            let message = items[index]
            HStack(spacing: 24) {
                Text(model.isMine(message) ? "你分享的" : "\(model.chat.user.nickname) 分享的")
                    .font(.headline)
                if let time = message.time {
                    Text(time, format: .dateTime.month().day().hour().minute())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(index + 1) / \(items.count)")
                    .monospacedDigit()
                Text("上下滑动切换")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
            .background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))
        }
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.callout)
                .padding(.horizontal, 30)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 60)
                .transition(.opacity)
        }
    }
}

/// Drives `fullScreenCover(item:)` for a note model.
private struct OpenNote: Identifiable {
    let model: NoteDetailModel
    var id: ObjectIdentifier { ObjectIdentifier(model) }
}
