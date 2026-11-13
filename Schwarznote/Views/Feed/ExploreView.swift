//
//  ExploreView.swift
//  Schwarznote
//

import SwiftUI

/// The 发现 page: channel bar on top, waterfall feed below.
struct ExploreView: View {
    @State private var feed = FeedModel()
    @State private var selectedNote: Note?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                ChannelBar(selection: $feed.channel)

                WaterfallGrid(
                    items: feed.notes,
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
        .task { if feed.notes.isEmpty { await feed.reload() } }
        .fullScreenCover(item: $selectedNote) { note in
            NoteDetailView(note: note)
        }
    }
}

/// Horizontal row of channel chips (推荐, 穿搭, 美食 …).
struct ChannelBar: View {
    @Binding var selection: Channel

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 20) {
                ForEach(Channel.allCases) { channel in
                    Button {
                        selection = channel
                    } label: {
                        Text(channel.rawValue)
                            .font(.headline)
                            .fontWeight(channel == selection ? .bold : .regular)
                            .padding(.horizontal, 12)
                    }
                    .buttonStyle(ChannelChipStyle(isSelected: channel == selection))
                }
            }
            .padding(.vertical, 20)
        }
        .scrollClipDisabled()
    }
}

/// Pill-shaped chip: filled when selected, scaled up when focused.
struct ChannelChipStyle: ButtonStyle {
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
