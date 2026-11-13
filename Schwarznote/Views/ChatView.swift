//
//  ChatView.swift
//  Schwarznote
//

import SwiftUI

/// A 私信 conversation, read-only. Opens at the newest message; scrolling to the top loads
/// earlier ones. The back button closes it.
struct ChatView: View {
    let chat: Chat
    @Environment(AuthModel.self) private var auth
    @State private var model: ChatModel?
    @State private var viewing: ChatMessage?
    @FocusState private var focusedMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let model {
                content(model)
            } else {
                Spacer()
            }
        }
        // Full-screen covers are transparent by default; don't let the list show through.
        .background(Color(white: 0.08).ignoresSafeArea())
        .task {
            let model = ChatModel(chat: chat, client: auth.client)
            self.model = model
            await model.loadLatest()
            focusedMessage = model.messages.last?.id
            #if DEBUG
            // Launch argument for testing without a remote, e.g. `-openShared 1`.
            let index = UserDefaults.standard.integer(forKey: "openShared")
            let shared = model.messages.filter(\.content.isShared)
            if index > 0, index <= shared.count { viewing = shared[index - 1] }
            #endif
        }
        .fullScreenCover(item: $viewing) { message in
            if let model {
                SharedContentViewer(model: model, startAt: message.id)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 24) {
            AvatarView(author: chat.user, size: 72)
            Text(chat.user.nickname)
                .font(.title3.bold())
            Spacer()
            Text("电视上暂时只能查看私信")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 30)
    }

    @ViewBuilder
    private func content(_ model: ChatModel) -> some View {
        if model.messages.isEmpty, let error = model.error {
            ErrorView(message: error) { await model.loadLatest() }
                .frame(maxHeight: .infinity)
        } else if model.messages.isEmpty, model.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.messages.isEmpty {
            ContentUnavailableView("还没有消息", systemImage: "bubble.left.and.bubble.right")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focusable()
        } else {
            ScrollView {
                LazyVStack(spacing: 20) {
                    if model.isLoading {
                        ProgressView()
                    } else if model.reachedStart {
                        Text("没有更早的消息了")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                        if let time = message.time, showsTime(at: index, in: model.messages) {
                            Text(time, format: .dateTime.month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 12)
                        }
                        MessageBubble(message: message, isMine: model.isMine(message), author: chat.user) {
                            if message.content.isShared { viewing = message }
                        }
                            .focused($focusedMessage, equals: message.id)
                            .onAppear {
                                if index == 0 { Task { await model.loadEarlier() } }
                            }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 40)
            }
            .defaultScrollAnchor(.bottom)
        }
    }

    /// A time line above the first message and wherever five minutes pass between messages.
    private func showsTime(at index: Int, in messages: [ChatMessage]) -> Bool {
        guard index > 0, let time = messages[index].time, let previous = messages[index - 1].time else { return true }
        return time.timeIntervalSince(previous) > 5 * 60
    }
}

/// One message, on the right for messages the signed-in user sent. Focusable so the remote
/// can scroll through the conversation; selecting an image or card opens the shared-content viewer.
struct MessageBubble: View {
    let message: ChatMessage
    let isMine: Bool
    let author: Author
    let open: () -> Void

    var body: some View {
        if case .hint(let text) = message.content {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .focusable()
        } else {
            HStack(alignment: .top, spacing: 20) {
                if isMine {
                    Spacer(minLength: 300)
                } else {
                    AvatarView(author: author, size: 56)
                }
                Button(action: open) {
                    bubbleContent
                }
                .buttonStyle(BubbleStyle(isMine: isMine))
                if !isMine { Spacer(minLength: 300) }
            }
        }
    }

    @ViewBuilder
    private var bubbleContent: some View {
        switch message.content {
        case .text(let text):
            Text(text)
                .multilineTextAlignment(.leading)
        case .image(let url):
            RemoteImage(url: url, contentMode: .fit)
                .frame(maxWidth: 420, maxHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        case .card(let card):
            HStack(spacing: 20) {
                if let imageURL = card.imageURL {
                    RemoteImage(url: imageURL, contentMode: .fill)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Text(card.title.isEmpty ? "[卡片]" : card.title)
                    .lineLimit(3)
            }
            .frame(maxWidth: 600, alignment: .leading)
        case .hint(let text), .unsupported(let text):
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

/// Chat bubble: red for the signed-in user, grey for the other side, lifted when focused.
struct BubbleStyle: ButtonStyle {
    let isMine: Bool
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(isMine ? Color.white : Color.primary)
            .padding(.horizontal, 26)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(isMine ? Color.red.opacity(isFocused ? 1 : 0.8) : Color.white.opacity(isFocused ? 0.28 : 0.12))
            )
            .scaleEffect(isFocused ? 1.04 : 1)
            .shadow(radius: isFocused ? 12 : 0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
