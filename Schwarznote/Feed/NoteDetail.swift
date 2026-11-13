//
//  NoteDetail.swift
//  Schwarznote
//

import Foundation

/// `POST /api/sns/web/v1/feed` → data.items[0]
nonisolated struct NoteDetail: Sendable, Decodable {
    let id: String
    let title: String
    let text: String
    let author: Author
    let media: [MediaItem]
    let time: Date?
    let ipLocation: String?
    var liked: Bool
    var likes: String
    var collected: Bool
    var collects: String
    var commentCount: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let card = try c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("note_card"))
        id = c.string("id") ?? card.string("note_id") ?? ""
        title = card.string("title") ?? ""
        // Topics arrive as "#洞洞板[话题]#"; show them as "#洞洞板".
        text = (card.string("desc") ?? "").replacingOccurrences(of: "[话题]#", with: " ")
        author = try card.decode(Author.self, forKey: AnyKey("user"))
        time = card.date("time")
        ipLocation = card.string("ip_location")

        let interact = card.nested("interact_info")
        liked = interact?.value(Bool.self, "liked") ?? false
        likes = interact?.string("liked_count") ?? "0"
        collected = interact?.value(Bool.self, "collected") ?? false
        collects = interact?.string("collected_count") ?? "0"
        commentCount = interact?.string("comment_count") ?? "0"

        let images = card.value([ImageEntry].self, "image_list") ?? []
        if let stream = card.nested("video")?.nested("media")?.nested("stream"),
           let video = stream.firstStream() {
            media = [MediaItem(id: 0, kind: .video, imageURL: images.first?.url, videoURL: video.url,
                               aspectRatio: video.aspectRatio ?? images.first?.aspectRatio ?? 16.0 / 9.0)]
        } else {
            media = images.enumerated().map { index, image in
                MediaItem(id: index, kind: image.liveURL == nil ? .image : .livePhoto, imageURL: image.url,
                          videoURL: image.liveURL, aspectRatio: image.aspectRatio ?? 3.0 / 4.0)
            }
        }
    }
}

/// One page of a note's media: a photo, a live photo, or the note's video.
struct MediaItem: Identifiable, Hashable, Sendable {
    enum Kind: Sendable { case image, livePhoto, video }

    let id: Int
    let kind: Kind
    /// The photo, the live photo's still frame, or the video's cover.
    let imageURL: URL?
    let videoURL: URL?
    let aspectRatio: CGFloat
}

nonisolated private struct ImageEntry: Decodable {
    let url: URL?
    let liveURL: URL?
    let aspectRatio: CGFloat?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        url = URL(webImage: c.string("url_default", "url_pre", "url"))
        liveURL = c.value(Bool.self, "live_photo") == true ? c.nested("stream")?.firstStream()?.url : nil
        aspectRatio = ratio(c.double("width"), c.double("height"))
    }
}

nonisolated private struct StreamEntry: Decodable {
    let url: URL?
    let aspectRatio: CGFloat?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        url = URL(webImage: c.string("master_url"))
        aspectRatio = ratio(c.double("width"), c.double("height"))
    }
}

nonisolated private func ratio(_ width: Double?, _ height: Double?) -> CGFloat? {
    guard let width, let height, width > 0, height > 0 else { return nil }
    return width / height
}

nonisolated private extension KeyedDecodingContainer where Key == AnyKey {
    /// First playable stream: H.264 first, then HEVC.
    func firstStream() -> StreamEntry? {
        for codec in ["h264", "h265"] {
            if let stream = value([StreamEntry].self, codec)?.first(where: { $0.url != nil }) { return stream }
        }
        return nil
    }
}

nonisolated struct NoteDetailPayload: Decodable, Sendable {
    let note: NoteDetail

    private struct NotFound: LocalizedError {
        var errorDescription: String? { "笔记不存在或已被删除" }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let note = c.value(LossyArray<NoteDetail>.self, "items")?.elements.first else { throw NotFound() }
        self.note = note
    }
}

// MARK: - Comments

nonisolated struct Comment: Identifiable, Sendable, Decodable {
    let id: String
    let content: String
    let author: Author
    let time: Date?
    let ipLocation: String?
    let isByNoteAuthor: Bool
    /// Nickname of the comment this one replies to (replies only).
    let replyTo: String?
    let replyCount: Int
    var liked: Bool
    var likes: String
    var replies: [Comment]
    var repliesCursor: String
    var hasMoreReplies: Bool

    private struct Invalid: Error {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id") else { throw Invalid() }
        self.id = id
        content = c.string("content") ?? ""
        author = try c.decode(Author.self, forKey: AnyKey("user_info"))
        time = c.date("create_time")
        ipLocation = c.string("ip_location")
        isByNoteAuthor = c.value([String].self, "show_tags")?.contains("is_author") ?? false
        replyTo = c.nested("target_comment")?.nested("user_info")?.string("nickname")
        replyCount = Int(c.string("sub_comment_count") ?? "") ?? 0
        liked = c.value(Bool.self, "liked") ?? false
        likes = c.string("like_count") ?? "0"
        replies = c.value(LossyArray<Comment>.self, "sub_comments")?.elements ?? []
        repliesCursor = c.string("sub_comment_cursor") ?? ""
        hasMoreReplies = c.value(Bool.self, "sub_comment_has_more") ?? false
    }
}

/// `GET /api/sns/web/v2/comment/page` and `/comment/sub/page` → data
nonisolated struct CommentPage: Decodable, Sendable {
    let comments: [Comment]
    let cursor: String
    let hasMore: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        comments = c.value(LossyArray<Comment>.self, "comments")?.elements ?? []
        cursor = c.string("cursor") ?? ""
        hasMore = c.value(Bool.self, "has_more") ?? false
    }
}

/// `POST /api/sns/web/v1/comment/post` → data
nonisolated struct CommentPostPayload: Decodable, Sendable {
    let comment: Comment
}

extension String {
    /// "453" → "454". Leaves rounded counts such as "1.2万" or "10+" unchanged.
    func adjustedCount(by delta: Int) -> String {
        guard let count = Int(self) else { return self }
        return String(max(0, count + delta))
    }
}
