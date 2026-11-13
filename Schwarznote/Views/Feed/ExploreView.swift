//
//  ExploreView.swift
//  Schwarznote
//

import SwiftUI

/// The 发现 page: channel bar on top, waterfall feed below.
struct ExploreView: View {
    @Environment(AuthModel.self) private var auth
    @State private var feed = Pager<Note>()
    @State private var channel = Channel.recommend
    @State private var selectedNote: Note?
    @FocusState private var focusedChannel: Channel?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 5)

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    ChipBar(items: Channel.allCases, title: \.rawValue, selection: $channel, focus: $focusedChannel, wraps: true)
                        .id(ScrollTop.id)

                    if feed.items.isEmpty, let error = feed.error {
                        ErrorView(message: error) { await feed.retry() }
                    }

                    LazyVGrid(columns: columns, spacing: 50) {
                        ForEach(feed.items) { note in
                            Button {
                                selectedNote = note
                            } label: {
                                NoteCard(note: note)
                            }
                            .buttonStyle(.card)
                            .task { await feed.loadMoreIfNeeded(current: note) }
                        }
                    }

                    if feed.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 40)
            }
            .backButtonReturnsToTop(isAtTop: focusedChannel != nil) {
                withAnimation { scroll.scrollTo(ScrollTop.id, anchor: .top) }
                focusedChannel = channel
            }
        }
        .task(id: "\(auth.contentKey ?? "")-\(channel.category)") {
            guard auth.contentKey != nil else { return }
            let client = auth.client
            let category = channel.category
            await feed.reset { cursor, count in
                try await client.homefeed(category: category, cursor: cursor, noteIndex: count)
            }
            #if DEBUG
            // Launch argument for testing without a remote, e.g. `-openNote 3`.
            let index = UserDefaults.standard.integer(forKey: "openNote")
            if index > 0, index <= feed.items.count { selectedNote = feed.items[index - 1] }
            #endif
        }
        .fullScreenCover(item: $selectedNote) { note in
            NoteDetailView(note: note)
        }
    }
}

/// Scroll anchor for the top of a page.
enum ScrollTop {
    static let id = "top"
}

/// Error message with a focusable retry button.
struct ErrorView: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 30) {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            Button("重试") { Task { await retry() } }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}

/// Horizontal row of pill chips (推荐, 穿搭, 美食 … or the notification lists).
struct ChipBar<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    @Binding var selection: Item
    /// Which chip has focus; the page uses it to tell whether focus is in its top row.
    var focus: FocusState<Item?>.Binding
    /// Moving right from the last chip goes to the first, and left from the first to the last.
    var wraps = false

    /// Invisible stops just past each end. The focus engine moves onto them like onto any
    /// chip (so swipes work, not just clicks), and they hand focus straight to the other end.
    @FocusState private var edgeStop: HorizontalEdge?

    /// While focus is elsewhere only the selected chip can take it, so arriving from the tab
    /// bar or the feed always lands there directly, without first touching the nearest chip.
    private var hasFocus: Bool { focus.wrappedValue != nil || edgeStop != nil }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 20) {
                if wraps { stop(.leading) }
                ForEach(items, id: \.self) { item in
                    Button {
                        selection = item
                    } label: {
                        Text(title(item))
                            .font(.headline)
                            .fontWeight(item == selection ? .bold : .regular)
                            .padding(.horizontal, 12)
                    }
                    .buttonStyle(ChipStyle(isSelected: item == selection))
                    .focused(focus, equals: item)
                    .disabled(!hasFocus && item != selection)
                }
                if wraps { stop(.trailing) }
            }
            .padding(.vertical, 20)
        }
        .scrollClipDisabled()
        // Lets the selected chip be reached from anywhere above or below the row.
        .focusSection()
        // Resting on a chip switches to it; passing over chips on the way doesn't.
        .task(id: focus.wrappedValue) {
            guard let item = focus.wrappedValue, item != selection else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            selection = item
        }
        .onChange(of: edgeStop) { _, edge in
            if let edge { wrap(from: edge) }
        }
    }

    private func stop(_ edge: HorizontalEdge) -> some View {
        Color.white.opacity(0.001)
            .frame(width: 2, height: 60)
            .focusable(hasFocus)
            .focused($edgeStop, equals: edge)
    }

    /// Stops are only reachable from inside the row, so landing on one means a move off that end.
    private func wrap(from edge: HorizontalEdge) {
        guard let first = items.first, let last = items.last else { return }
        focus.wrappedValue = edge == .leading ? last : first
    }
}

/// Pill-shaped chip: filled when selected, scaled up when focused.
struct ChipStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .foregroundStyle(isFocused ? Color.black : (isSelected ? Color.primary : Color.secondary))
            .background {
                Capsule().fill(isFocused ? Color.white : (isSelected ? Color.primary.opacity(0.12) : .clear))
            }
            .scaleEffect(isFocused ? 1.1 : (configuration.isPressed ? 0.95 : 1))
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
