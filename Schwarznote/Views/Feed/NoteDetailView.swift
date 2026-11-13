//
//  NoteDetailView.swift
//  Schwarznote
//

import SwiftUI

/// Note detail like the web modal: media on the left, author, text and stats on the right.
struct NoteDetailView: View {
    let note: Note
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 0) {
            NoteCover(note: note)
                .aspectRatio(note.coverAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)

            VStack(alignment: .leading, spacing: 32) {
                HStack(spacing: 20) {
                    AvatarView(author: note.author, size: 72)
                    Text(note.author.nickname)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Button("关注") {}
                        .disabled(true)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text(note.title)
                            .font(.title2.bold())
                        Text(note.body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .focusable()

                Divider()

                HStack(spacing: 48) {
                    Label(note.likeCount.compactCount, systemImage: "heart")
                    Label((note.likeCount / 3).compactCount, systemImage: "star")
                    Label((note.likeCount / 20).compactCount, systemImage: "bubble.right")
                }
                .font(.headline)
                .foregroundStyle(.secondary)
            }
            .padding(60)
            .frame(width: 760)
            .background(.regularMaterial)
        }
        .ignoresSafeArea()
        .onExitCommand { dismiss() }
    }
}
