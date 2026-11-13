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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                ChipBar(items: Channel.allCases, title: \.rawValue, selection: $channel)

                if feed.items.isEmpty, let error = feed.error {
                    ErrorView(message: error) { await feed.retry() }
                }

                WaterfallGrid(
                    items: feed.items,
                    columns: 5,
                    spacing: 40,
                    relativeHeight: NoteCard.relativeHeight(of:)
                ) { note in
                    Button {
                        selectedNote = note
                    } label: {
                        NoteCard(note: note)
                    }
                    .buttonStyle(.card)
                    .task { await feed.loadMoreIfNeeded(current: note) }
                }

                if feed.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 40)
        }
        .task(id: "\(auth.contentKey ?? "")-\(channel.category)") {
            guard auth.contentKey != nil else { return }
            let client = auth.client
            let category = channel.category
            await feed.reset { cursor, count in
                try await client.homefeed(category: category, cursor: cursor, noteIndex: count)
            }
        }
        .fullScreenCover(item: $selectedNote) { note in
            NoteDetailView(note: note)
        }
    }
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

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 20) {
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
                }
            }
            .padding(.vertical, 20)
        }
        .scrollClipDisabled()
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
