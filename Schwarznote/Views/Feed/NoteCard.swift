//
//  NoteCard.swift
//  Schwarznote
//

import SwiftUI

/// One note in the grid: cover, title, author and like count. Every card has the same
/// shape (3:4 cover, two title lines) so rows line up.
struct NoteCard: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay { NoteCover(note: note) }
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if note.isVideo {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white, .black.opacity(0.35))
                            .padding(16)
                    }
                }

            VStack(alignment: .leading, spacing: 14) {
                Text(note.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    AvatarView(author: note.author, size: 36)
                    Text(note.author.nickname)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Image(systemName: "heart")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(note.likes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
    }
}

/// Cover image, with a tinted placeholder while it loads.
struct NoteCover: View {
    let note: Note

    var body: some View {
        if let url = note.coverURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholder
            }
            .clipped()
        } else {
            placeholder
        }
    }

    /// Stable tint per note while the cover loads.
    private var hue: Double {
        Double(note.id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % 360) / 360
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.35, brightness: 0.85),
                Color(hue: hue, saturation: 0.55, brightness: 0.6),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}

struct AvatarView: View {
    let author: Author
    let size: CGFloat

    var body: some View {
        Group {
            if let url = author.avatarURL {
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { fallback }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallback: some View {
        Circle()
            .fill(Color(hue: Double(abs(author.id.hashValue) % 360) / 360, saturation: 0.3, brightness: 0.8))
            .overlay {
                Text(String(author.nickname.prefix(1)))
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}
