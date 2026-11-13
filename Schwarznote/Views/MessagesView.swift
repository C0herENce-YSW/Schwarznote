//
//  MessagesView.swift
//  Schwarznote
//

import SwiftUI

/// One chip on the 消息 page.
enum InboxTab: Hashable {
    case chats
    case notifications(NotificationKind)

    static let all: [InboxTab] = [.chats] + NotificationKind.allCases.map { .notifications($0) }

    var title: String {
        switch self {
        case .chats: "私信"
        case .notifications(let kind): kind.title
        }
    }
}

/// The 消息 page: 私信 first, then 评论和@ / 赞和收藏 / 新增关注, like the web client.
struct MessagesView: View {
    @Environment(AuthModel.self) private var auth
    @State private var tab = InboxTab.chats
    @State private var chats = Pager<Chat>()
    @State private var notifications = Pager<NotificationMessage>()
    @State private var openChat: Chat?
    @FocusState private var focusedTab: InboxTab?

    var body: some View {
        if auth.isLoggedIn {
            list
        } else {
            LoginRequiredView(feature: "消息")
                .backButtonReturnsToTop(isAtTop: true) {}
        }
    }

    private var list: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ChipBar(items: InboxTab.all, title: \.title, selection: $tab, focus: $focusedTab)
                        .id(ScrollTop.id)

                    switch tab {
                    case .chats:
                        rows(chats, empty: "暂时没有私信", systemImage: "bubble.left.and.bubble.right") { chat in
                            Button { openChat = chat } label: { ChatRow(chat: chat) }
                        }
                    case .notifications(let kind):
                        rows(notifications, empty: "暂时没有\(kind.title)", systemImage: "bell.slash") { message in
                            Button {} label: { NotificationRow(message: message) }
                        }
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 40)
            }
            .backButtonReturnsToTop(isAtTop: focusedTab != nil) {
                withAnimation { scroll.scrollTo(ScrollTop.id, anchor: .top) }
                focusedTab = tab
            }
        }
        .task(id: "\(auth.contentKey ?? "")-\(tab.title)") {
            guard auth.contentKey != nil else { return }
            let client = auth.client
            switch tab {
            case .chats:
                await chats.reset { cursor, _ in try await client.chats(cursor: cursor) }
                #if DEBUG
                // Launch argument for testing without a remote, e.g. `-openChat 1`.
                let index = UserDefaults.standard.integer(forKey: "openChat")
                if index > 0, index <= chats.items.count { openChat = chats.items[index - 1] }
                #endif
            case .notifications(let kind):
                await notifications.reset { cursor, _ in try await client.notifications(kind, cursor: cursor) }
            }
        }
        .fullScreenCover(item: $openChat) { chat in
            ChatView(chat: chat)
        }
    }

    /// Error, empty state, the rows, and a spinner while the next page loads.
    @ViewBuilder
    private func rows<Item, Row: View>(
        _ pager: Pager<Item>, empty: String, systemImage: String, @ViewBuilder row: @escaping (Item) -> Row
    ) -> some View {
        if pager.items.isEmpty, let error = pager.error {
            ErrorView(message: error) { await pager.retry() }
        } else if pager.items.isEmpty, !pager.isLoading {
            ContentUnavailableView(empty, systemImage: systemImage)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 80)
                .focusable()
        }

        ForEach(pager.items) { item in
            row(item)
                .buttonStyle(.card)
                .task { await pager.loadMoreIfNeeded(current: item) }
        }

        if pager.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }
}

struct ChatRow: View {
    let chat: Chat

    var body: some View {
        HStack(spacing: 28) {
            AvatarView(author: chat.user, size: 80)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text(chat.user.nickname)
                        .font(.headline)
                    if chat.isOfficial {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.red)
                    }
                }
                Text(chat.lastMessage)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 10) {
                if let time = chat.time {
                    Text(time, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if chat.unreadCount > 0 {
                    Text(chat.unreadCount > 99 ? "99+" : "\(chat.unreadCount)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.red))
                }
            }
        }
        .padding(28)
    }
}

struct NotificationRow: View {
    let message: NotificationMessage

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            if let user = message.user {
                AvatarView(author: user, size: 80)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    Text(message.user?.nickname ?? "")
                        .font(.headline)
                    Text(message.title)
                        .foregroundStyle(.secondary)
                }
                if let content = message.content, !content.isEmpty {
                    Text(content)
                        .lineLimit(2)
                }
                if let time = message.time {
                    Text(time, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let url = message.imageURL {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.2) }
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(28)
    }
}
