//
//  NotificationsView.swift
//  Schwarznote
//

import SwiftUI

/// The 通知 page: 评论和@ / 赞和收藏 / 新增关注, like the web client.
struct NotificationsView: View {
    @Environment(AuthModel.self) private var auth
    @State private var kind = NotificationKind.mentions
    @State private var pager = Pager<NotificationMessage>()
    @FocusState private var focusedKind: NotificationKind?

    var body: some View {
        if auth.isLoggedIn {
            list
        } else {
            LoginRequiredView(feature: "通知")
                .backButtonReturnsToTop(isAtTop: true) {}
        }
    }

    private var list: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ChipBar(items: NotificationKind.allCases, title: \.title, selection: $kind, focus: $focusedKind)
                        .id(ScrollTop.id)

                    if pager.items.isEmpty, let error = pager.error {
                        ErrorView(message: error) { await pager.retry() }
                    } else if pager.items.isEmpty, !pager.isLoading {
                        ContentUnavailableView("暂时没有\(kind.title)", systemImage: "bell.slash")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 80)
                            .focusable()
                    }

                    ForEach(pager.items) { message in
                        Button {} label: {
                            NotificationRow(message: message)
                        }
                        .buttonStyle(.card)
                        .task { await pager.loadMoreIfNeeded(current: message) }
                    }

                    if pager.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 40)
            }
            .backButtonReturnsToTop(isAtTop: focusedKind != nil) {
                withAnimation { scroll.scrollTo(ScrollTop.id, anchor: .top) }
                focusedKind = kind
            }
        }
        .task(id: "\(auth.contentKey ?? "")-\(kind.rawValue)") {
            guard auth.contentKey != nil else { return }
            let client = auth.client
            let kind = kind
            await pager.reset { cursor, _ in
                try await client.notifications(kind, cursor: cursor)
            }
        }
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
