//
//  NoteDetailView.swift
//  Schwarznote
//

import SwiftUI

/// Note detail like the web modal: media on the left; author, text, actions and comments on the right.
///
/// Remote:
/// - Swipe left / right on the touch surface: previous / next picture.
/// - Swipe up / down: scroll the right-hand column a section at a time (text, actions, each comment).
/// - Click up / down / left / right: choose 作者 / 关注 / 大图 / 点赞 / 收藏 / 评论 / a comment…;
///   click the center to use it.
///
/// Swipes and clicks need different jobs, but the focus engine treats them alike. So the column
/// isn't made of focusable buttons: one invisible button behind it holds the focus and takes the
/// clicks, `selection` says which control is highlighted, and swipes come from `SwipeMonitor`.
/// With nothing else to move to, the focus engine leaves swipes alone. Only the comment field
/// takes focus itself, and only while you're writing; the back button leaves it.
struct NoteDetailView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(ShortcutCenter.self) private var shortcuts
    @Environment(\.dismiss) private var dismiss
    @State private var model: NoteDetailModel
    @State private var draft = ""
    @State private var replyTarget: Comment?
    @State private var authorProfile: UserProfileModel?
    @State private var mediaIndex = 0
    @State private var showsMediaFullScreen = false
    @State private var selection = Control.like
    @State private var isComposing = false
    @State private var confirmingUnfollow = false
    @FocusState private var focus: FocusTarget?
    private let focusComposerOnOpen: Bool

    /// One thing in the right-hand column that can be highlighted and used.
    enum Control: Hashable {
        case author, follow, media, like, collect, comments, composer, cancelReply, retryComments
        case reply(String), commentLike(String), moreReplies(String)
    }

    private enum FocusTarget: Hashable { case panel, composer }

    /// `xsecSource` says where the note was opened: "pc_feed" for the feed, "pc_user" for a profile.
    init(note: Note, xsecSource: String = "pc_feed") {
        _model = State(initialValue: NoteDetailModel(note: note, xsecSource: xsecSource))
        focusComposerOnOpen = false
    }

    /// Opens a note another screen already loaded, e.g. from the 评论 shortcut in the 私信 viewer.
    init(model: NoteDetailModel, focusComposer: Bool) {
        _model = State(initialValue: model)
        focusComposerOnOpen = focusComposer
    }

    private var note: Note { model.note }
    private var author: Author { model.detail?.author ?? note.author }
    private var showsFollow: Bool { model.detail != nil && author.id != auth.currentUser?.userId }

    /// Until the detail loads, show the feed card's cover.
    private var media: [MediaItem] {
        model.detail?.media ?? [MediaItem(id: 0, kind: .image, imageURL: note.coverURL, videoURL: nil,
                                          aspectRatio: note.coverAspectRatio)]
    }

    var body: some View {
        HStack(spacing: 0) {
            MediaViewer(media: media, index: $mediaIndex, fullScreenRequest: $showsMediaFullScreen)

            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        header
                        actionBar
                            .id(Section.actions)
                        Divider()
                        composer
                            .id(Section.composer)
                        commentList
                    }
                    .padding(60)
                }
                .scrollDisabled(true)
                .onChange(of: selection) { _, control in
                    withAnimation(.easeOut(duration: 0.2)) {
                        scroll.scrollTo(scrollID(for: control), anchor: control == .author ? .top : nil)
                    }
                }
                .background(SwipeMonitor(directions: [.left, .right, .up, .down]) { direction in
                    swiped(direction, scroll: scroll)
                })
            }
            .frame(width: 820)
            .background(.regularMaterial)
            .background(focusHolder)
        }
        .ignoresSafeArea()
        .onExitCommand {
            if isComposing { stopComposing() } else { dismiss() }
        }
        .task { await model.load(client: auth.client) }
        .task {
            // Give the cover a moment to settle so the focus change sticks.
            guard focusComposerOnOpen else { return }
            try? await Task.sleep(for: .milliseconds(400))
            startComposing()
        }
        #if DEBUG
        .task(id: model.detail == nil) {
            // Launch argument for testing without a remote: `-openProfile YES` opens the author.
            if model.detail != nil, UserDefaults.standard.bool(forKey: "openProfile"), authorProfile == nil {
                authorProfile = model.makeAuthorProfile()
            }
        }
        #endif
        .fullScreenCover(item: $authorProfile) { profile in
            UserProfileView(model: profile)
        }
        .confirmationDialog("不再关注\(author.nickname)？", isPresented: $confirmingUnfollow,
                            titleVisibility: .visible) {
            Button("不再关注", role: .destructive) {
                requireLogin { await model.setFollowing(false, client: auth.client) }
            }
            Button("取消", role: .cancel) {}
        }
        .onAppear {
            shortcuts.handler = handleShortcut
            focus = .panel
        }
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

    /// The column's only focusable view: takes the clicks and the center press.
    private var focusHolder: some View {
        Button(action: activate) {
            Color.white.opacity(0.001)
        }
        .buttonStyle(BareButtonStyle())
        .focused($focus, equals: .panel)
        .disabled(isComposing)
        .onMoveCommand(perform: move)
    }

    private func isLit(_ control: Control) -> Bool {
        focus == .panel && selection == control
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 24) {
                HStack(spacing: 20) {
                    AvatarView(author: author, size: 72)
                    Text(author.nickname)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                }
                .modifier(RowLook(isLit: isLit(.author)))

                if showsFollow, let detail = model.detail {
                    Text(detail.relation.title)
                        .modifier(FollowLook(isFollowing: detail.relation.isFollowing, isLit: isLit(.follow)))
                }
            }
            // RowLook pads the author; line it up with the text below.
            .padding(.leading, -16)
            .id(Section.header)

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

    private var actionBar: some View {
        HStack(spacing: 20) {
            if let detail = model.detail {
                if let item = currentMedia {
                    Group {
                        switch item.kind {
                        case .image: Label("大图", systemImage: "arrow.up.left.and.arrow.down.right")
                        case .livePhoto: Label("实况", systemImage: "livephoto")
                        case .video: Label("播放", systemImage: "play.fill")
                        }
                    }
                    .modifier(ChipLook(isSelected: false, isLit: isLit(.media)))
                }
                actionChip(detail.likes, systemImage: detail.liked ? "heart.fill" : "heart",
                           active: detail.liked, control: .like)
                actionChip(detail.collects, systemImage: detail.collected ? "star.fill" : "star",
                           active: detail.collected, control: .collect)
                actionChip(detail.commentCount, systemImage: "bubble.right", active: false, control: .comments)
            }
        }
    }

    private var currentMedia: MediaItem? {
        media.indices.contains(mediaIndex) ? media[mediaIndex] : media.first
    }

    private func actionChip(_ count: String, systemImage: String, active: Bool, control: Control) -> some View {
        Label(count, systemImage: systemImage)
            .foregroundStyle(active ? Color.accentColor : .primary)
            .modifier(ChipLook(isSelected: active, isLit: isLit(control)))
    }

    private func handleShortcut(_ action: ShortcutAction) {
        // Keys typed into the comment box are text, not shortcuts.
        guard !isComposing else { return }
        switch action {
        case .like: requireLogin { await model.toggleLike(client: auth.client) }
        case .collect: requireLogin { await model.toggleCollect(client: auth.client) }
        case .comment:
            replyTarget = nil
            startComposing()
        case .backToTop: break
        }
    }

    private func requireLogin(_ action: @escaping () async -> Void) {
        guard auth.isLoggedIn else {
            model.actionError = "请先在“我”页面扫码登录"
            return
        }
        Task { await action() }
    }

    // MARK: - Remote

    /// Click: move the highlight within a row (left / right) or between rows (up / down).
    private func move(_ direction: MoveCommandDirection) {
        let rows = controlRows
        guard let (row, column) = position(of: selection, in: rows) else {
            selection = rows.first(where: { $0.contains(.like) }) != nil ? .like : rows.first?.first ?? .author
            return
        }
        switch direction {
        case .left:
            selection = rows[row][max(column - 1, 0)]
        case .right:
            selection = rows[row][min(column + 1, rows[row].count - 1)]
        case .up where row > 0:
            selection = rows[row - 1][min(column, rows[row - 1].count - 1)]
        case .down where row < rows.count - 1:
            selection = rows[row + 1][min(column, rows[row + 1].count - 1)]
        default:
            break
        }
    }

    /// Swipe: left / right changes the picture; up / down jumps a section and keeps it in view.
    private func swiped(_ direction: UISwipeGestureRecognizer.Direction, scroll: ScrollViewProxy) {
        guard !isComposing, focus == .panel else { return }
        switch direction {
        case .left, .right:
            guard media.count > 1 else { return }
            let step = direction == .left ? 1 : -1
            mediaIndex = (mediaIndex + step + media.count) % media.count
        case .up, .down:
            let sections = sectionStarts
            let current = sections.lastIndex { $0.rows.contains(where: { $0.contains(selection) }) } ?? 0
            let next = direction == .up ? current + 1 : current - 1
            guard sections.indices.contains(next) else { return }
            selection = sections[next].first
        default:
            break
        }
    }

    /// Center click: use the highlighted control.
    private func activate() {
        switch selection {
        case .author:
            authorProfile = model.makeAuthorProfile()
        case .follow:
            guard let relation = model.detail?.relation else { return }
            if relation.isFollowing {
                confirmingUnfollow = true
            } else {
                requireLogin { await model.setFollowing(true, client: auth.client) }
            }
        case .media:
            showsMediaFullScreen = true
        case .like:
            requireLogin { await model.toggleLike(client: auth.client) }
        case .collect:
            requireLogin { await model.toggleCollect(client: auth.client) }
        case .comments, .composer:
            if selection == .comments { replyTarget = nil }
            startComposing()
        case .cancelReply:
            replyTarget = nil
            selection = .composer
        case .retryComments:
            Task { await model.comments.retry() }
        case .reply(let id):
            guard let comment = comment(id) else { return }
            replyTarget = comment
            startComposing()
        case .commentLike(let id):
            guard let comment = comment(id) else { return }
            requireLogin { await model.toggleLike(of: comment, client: auth.client) }
        case .moreReplies(let id):
            guard let comment = comment(id) else { return }
            Task { await model.loadMoreReplies(for: comment, client: auth.client) }
        }
    }

    /// The column's controls row by row, top to bottom.
    private var controlRows: [[Control]] {
        sectionStarts.flatMap(\.rows)
    }

    /// Rows grouped into the sections an up / down swipe jumps between.
    private var sectionStarts: [(first: Control, rows: [[Control]])] {
        var sections: [(first: Control, rows: [[Control]])] = []
        sections.append((.author, [showsFollow ? [.author, .follow] : [.author]]))
        if model.detail != nil {
            sections.append((.like, [[.media, .like, .collect, .comments]]))
        }
        sections.append((.composer, [replyTarget == nil ? [.composer] : [.composer, .cancelReply]]))
        let comments = model.comments
        if comments.items.isEmpty, comments.error != nil {
            sections.append((.retryComments, [[.retryComments]]))
        }
        for comment in comments.items {
            var rows: [[Control]] = [[.reply(comment.id), .commentLike(comment.id)]]
            rows += comment.replies.map { [.reply($0.id), .commentLike($0.id)] }
            if comment.hasMoreReplies { rows.append([.moreReplies(comment.id)]) }
            sections.append((.reply(comment.id), rows))
        }
        return sections
    }

    private func position(of control: Control, in rows: [[Control]]) -> (Int, Int)? {
        for (row, controls) in rows.enumerated() {
            if let column = controls.firstIndex(of: control) { return (row, column) }
        }
        return nil
    }

    private enum Section: Hashable { case header, actions, composer }

    private func scrollID(for control: Control) -> AnyHashable {
        switch control {
        case .author, .follow: Section.header
        case .media, .like, .collect, .comments: Section.actions
        case .composer, .cancelReply, .retryComments: Section.composer
        case .reply(let id), .commentLike(let id): id
        case .moreReplies(let id): "more-\(id)"
        }
    }

    private func comment(_ id: String) -> Comment? {
        for comment in model.comments.items {
            if comment.id == id { return comment }
            if let reply = comment.replies.first(where: { $0.id == id }) { return reply }
        }
        return nil
    }

    // MARK: - Comments

    private var composer: some View {
        HStack(spacing: 20) {
            TextField(replyTarget.map { "回复 \($0.author.nickname)" } ?? "说点什么…", text: $draft)
                .focused($focus, equals: .composer)
                .disabled(!isComposing)
                .onSubmit(send)
                .overlay {
                    // The field only takes focus while writing; otherwise show the column's highlight.
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.white, lineWidth: isLit(.composer) ? 4 : 0)
                }
            if replyTarget != nil {
                Text("取消回复")
                    .modifier(ChipLook(isSelected: false, isLit: isLit(.cancelReply)))
            }
        }
    }

    /// Moves focus into the comment field; pressing the center again opens the keyboard.
    private func startComposing() {
        selection = .composer
        isComposing = true
        Task {
            // The field becomes focusable on the next update.
            try? await Task.sleep(for: .milliseconds(50))
            focus = .composer
        }
    }

    /// Back to the column: after sending, or with the back button.
    private func stopComposing() {
        isComposing = false
        focus = .panel
    }

    private func send() {
        stopComposing()
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
            HStack(spacing: 24) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Text("重试")
                    .modifier(ChipLook(isSelected: false, isLit: isLit(.retryComments)))
            }
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
                        Text("展开更多回复")
                            .modifier(ChipLook(isSelected: false, isLit: isLit(.moreReplies(comment.id))))
                            .padding(.leading, 76)
                            .id("more-\(comment.id)")
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
        CommentRow(comment: comment, isTextLit: isLit(.reply(comment.id)),
                   isLikeLit: isLit(.commentLike(comment.id)))
            .id(comment.id)
    }
}

/// One comment: the text (selecting it replies) and the heart (selecting it likes).
struct CommentRow: View {
    let comment: Comment
    let isTextLit: Bool
    let isLikeLit: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
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
            .modifier(RowLook(isLit: isTextLit))

            VStack(spacing: 4) {
                Image(systemName: comment.liked ? "heart.fill" : "heart")
                    .foregroundStyle(comment.liked ? Color.accentColor : .secondary)
                Text(comment.likes)
                    .font(.caption)
            }
            .modifier(RowLook(isLit: isLikeLit))
        }
    }
}

/// Subtle highlight for list rows, instead of the default button platter.
struct RowStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(RowLook(isLit: isFocused))
    }
}

/// The row highlight on its own, for views that show it without taking focus.
struct RowLook: ViewModifier {
    let isLit: Bool

    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16).fill(.white.opacity(isLit ? 0.15 : 0))
            )
            .scaleEffect(isLit ? 1.02 : 1)
            .animation(.easeOut(duration: 0.15), value: isLit)
    }
}
