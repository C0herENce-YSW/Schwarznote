//
//  SharedContentViewer.swift
//  Schwarznote
//

import SwiftUI

/// Full-screen viewer for what both people shared in a 私信 conversation: images and notes,
/// oldest to newest. Swiping (or clicking) down goes to the next one, up to the previous one;
/// left and right still move through a note's pictures. The back button closes it.
struct SharedContentViewer: View {
    let model: ChatModel

    @Environment(AuthModel.self) private var auth
    @Environment(ShortcutCenter.self) private var shortcuts
    @State private var currentID: String
    @State private var forward = true
    @State private var details: [String: NoteDetail] = [:]
    @State private var failures: [String: String] = [:]
    @State private var edgeHint: String?
    @State private var lastStep = Date.distantPast
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
        .overlay(alignment: .bottom) { edgeHintView }
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
        .onAppear { pageFocused = true }
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
                    showEdgeHint("已经是第一条了")
                }
            }
        } else {
            showEdgeHint(delta < 0 ? "已经是第一条了" : "已经是最后一条了")
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

    private func showEdgeHint(_ text: String) {
        withAnimation { edgeHint = text }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if edgeHint == text { withAnimation { edgeHint = nil } }
        }
    }

    // MARK: - Pages

    @ViewBuilder
    private func page(_ message: ChatMessage) -> some View {
        switch message.content {
        case .image(let url):
            RemoteImage(url: url, contentMode: .fit)
                .padding(.horizontal, 80)
                .padding(.top, 150)
                .padding(.bottom, 60)
                .focusable()
                .focused($pageFocused)
        case .card(let card):
            if let link = card.note, let detail = details[link.id] {
                notePage(detail)
            } else {
                cardPage(card, error: card.note.flatMap { failures[$0.id] })
            }
        default:
            EmptyView()
        }
    }

    private func notePage(_ detail: NoteDetail) -> some View {
        HStack(spacing: 0) {
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
                    Label(detail.likes, systemImage: "heart")
                    Label(detail.collects, systemImage: "star")
                    Label(detail.commentCount, systemImage: "bubble.right")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(50)
            .padding(.top, 110)
            .frame(width: 760, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .top)
            .focusable()
            .focused($pageFocused)
        }
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
        guard let index, case .card(let card) = items[index].content, let link = card.note,
              details[link.id] == nil else { return }
        failures[link.id] = nil
        do {
            details[link.id] = try await auth.client.noteDetail(
                id: link.id, xsecToken: link.xsecToken, xsecSource: link.xsecSource
            )
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            failures[link.id] = error.localizedDescription
        }
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
    private var edgeHintView: some View {
        if let edgeHint {
            Text(edgeHint)
                .font(.callout)
                .padding(.horizontal, 30)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 60)
                .transition(.opacity)
        }
    }
}
