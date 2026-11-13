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

                Text(note.title)
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Something must hold focus so the Menu button reaches onExitCommand.
                    .focusable()

                Spacer()

                Divider()

                Label(note.likes, systemImage: "heart")
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
