//
//  NotificationMessage.swift
//  Schwarznote
//

import Foundation

/// The three lists on the web notifications page.
enum NotificationKind: String, CaseIterable, Identifiable, Sendable {
    case mentions, likes, connections

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mentions: "评论和@"
        case .likes: "赞和收藏"
        case .connections: "新增关注"
        }
    }
}

/// `GET /api/sns/web/v1/you/{mentions,likes,connections}` → data
nonisolated struct NotificationPage: Decodable, Sendable {
    let messages: [NotificationMessage]
    let cursor: String
    let hasMore: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        messages = c.value(LossyArray<NotificationMessage>.self, "message_list")?.elements ?? []
        cursor = c.string("strCursor", "str_cursor", "cursor") ?? ""
        hasMore = c.value(Bool.self, "has_more") ?? false
    }
}

nonisolated struct NotificationMessage: Identifiable, Sendable, Decodable {
    let id: String
    /// Server-written action text, e.g. "评论了你的笔记".
    let title: String
    let time: Date?
    let user: Author?
    /// The comment text, or the note's text when there is no comment.
    let content: String?
    /// Thumbnail of the note the message is about.
    let imageURL: URL?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let item = c.nested("item_info")
        let comment = c.nested("comment_info")
        id = c.string("id") ?? UUID().uuidString
        title = c.string("title") ?? ""
        time = c.date("time")
        user = c.value(Author.self, "user_info", "user")
        content = comment?.string("content") ?? item?.string("content")
        imageURL = URL(webImage: item?.string("image"))
    }
}
