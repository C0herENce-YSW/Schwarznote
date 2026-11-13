//
//  Chat.swift
//  Schwarznote
//
//  私信, from the web client's IM endpoints (www.xiaohongshu.com/chat).
//

import Foundation

/// `GET /api/im/web/v3/chats` → data
nonisolated struct ChatListPayload: Decodable, Sendable {
    let chats: [Chat]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        chats = c.value(LossyArray<Chat>.self, "chats")?.elements ?? []
    }
}

/// One conversation with another user.
nonisolated struct Chat: Identifiable, Hashable, Sendable, Decodable {
    /// The other user's ID; also what the message history is keyed by.
    let id: String
    let user: Author
    let lastMessage: String
    let time: Date?
    let unreadCount: Int
    /// Newest message's store ID; the history is paged by store ID.
    let maxStoreID: Int
    let isOfficial: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let info = c.nested("info")
        let id = c.string("chat_user_id", "chatUserId") ?? ""
        self.id = id
        user = Author(
            id: id,
            nickname: info?.string("nickname") ?? "",
            avatarURL: URL(webImage: info?.string("avatar"))
        )
        lastMessage = MessageContent(raw: c.string("last_msg_content", "lastMsgContent")).preview
        time = c.date("last_msg_time", "lastMsgTime", "update_time", "updateTime")
        unreadCount = Int(c.double("unread_count", "unreadCount") ?? 0)
        maxStoreID = Int(c.double("max_store_id", "maxStoreId") ?? 0)
        isOfficial = info?.value(Bool.self, "is_official", "isOfficial") ?? false
    }
}

/// `GET /api/im/web/messages/history` → data
nonisolated struct ChatHistoryPayload: Decodable, Sendable {
    let messages: [ChatMessage]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        messages = c.value(LossyArray<ChatMessage>.self, "out_message_list", "outMessageList")?.elements ?? []
    }
}

nonisolated struct ChatMessage: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    let storeID: Int
    let senderID: String
    let time: Date?
    let content: MessageContent

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        storeID = Int(c.double("store_id", "storeId") ?? 0)
        id = c.string("id", "uuid") ?? String(storeID)
        senderID = c.string("sender_id", "senderId") ?? ""
        time = c.date("created_at", "createdAt")
        content = MessageContent(raw: c.string("content"))
    }
}

/// A message's `content`: a JSON string `{"contentType": 1, "content": "…"}`, where the inner
/// content is plain text for text messages and another JSON object for images, cards and so on.
nonisolated enum MessageContent: Hashable, Sendable {
    case text(String)
    case image(URL?)
    case card(ChatCard)
    /// System line such as "你撤回了一条消息".
    case hint(String)
    /// A type the TV can't show; carries a short label like "[语音]".
    case unsupported(String)

    init(raw: String?) {
        guard let raw, !raw.isEmpty else { self = .text(""); return }
        guard let outer = Self.object(raw) else { self = .text(raw); return }
        let type = (outer["contentType"] ?? outer["content_type"]).flatMap { Int("\($0)") } ?? 1
        let content = outer["content"] as? String ?? ""
        let inner = Self.object(content) ?? [:]

        switch type {
        case 1: self = .text(content)
        case 2: self = .image(Self.url(in: inner))
        case 3, 6:
            // Shared notes: {"title", "desc", "image", "link": "xhsdiscover://item/…", "type": "note", "user"}.
            var title = Self.string(in: inner, "title", "desc", "content", "name")
            if title.isEmpty, inner["type"] as? String == "note" { title = "分享了一篇笔记" }
            let link = (inner["link"] as? String).flatMap(SharedNoteLink.init)
            self = .card(ChatCard(title: title, imageURL: Self.url(in: inner), note: link))
        case 4, 5, 10: self = .hint(Self.string(in: inner, "content", "text", "desc").nonEmpty ?? content)
        case 7: self = .unsupported("[表情]")
        case 9: self = .unsupported("[语音]")
        case 11: self = .unsupported("[视频]")
        default: self = .unsupported("[暂不支持的消息]")
        }
    }

    /// One-line text for the conversation list.
    var preview: String {
        switch self {
        case .text(let text), .hint(let text), .unsupported(let text): text
        case .image: "[图片]"
        case .card(let card): card.title.isEmpty ? "[卡片]" : "[卡片] \(card.title)"
        }
    }

    /// Images and cards, which open in the shared-content viewer.
    var isShared: Bool {
        switch self {
        case .image, .card: true
        default: false
        }
    }

    private static func object(_ string: String) -> [String: Any]? {
        guard string.hasPrefix("{"), let data = string.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func string(in object: [String: Any], _ keys: String...) -> String {
        keys.lazy.compactMap { object[$0] as? String }.first { !$0.isEmpty } ?? ""
    }

    /// The first image URL in a payload, searching nested objects too. Only web URLs count:
    /// `link` is usually an app deep link such as `xhsdiscover://item/…`.
    private static func url(in object: [String: Any]) -> URL? {
        for key in ["image", "cover", "url", "thumbnail", "original", "link"] {
            if let value = object[key] as? String, let url = URL(webImage: value),
               url.scheme == "https" { return url }
        }
        for value in object.values {
            if let nested = value as? [String: Any], let url = url(in: nested) { return url }
            if let list = value as? [[String: Any]], let first = list.first, let url = url(in: first) { return url }
        }
        return nil
    }
}

/// A card message: usually a shared note, sometimes a profile or another link.
nonisolated struct ChatCard: Hashable, Sendable {
    let title: String
    let imageURL: URL?
    /// Set when the card is a note that can be loaded in full.
    let note: SharedNoteLink?
}

/// `xhsdiscover://item/<note id>?…&xsec_source=…&xsec_token=…`, the link of a shared note.
nonisolated struct SharedNoteLink: Hashable, Sendable {
    let id: String
    let xsecToken: String
    let xsecSource: String

    init?(_ link: String) {
        guard let components = URLComponents(string: link), components.host == "item" else { return nil }
        let id = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { first, _ in first }
        guard !id.isEmpty, let token = query["xsec_token"], !token.isEmpty else { return nil }
        self.id = id
        xsecToken = token
        xsecSource = query["xsec_source"].flatMap { $0.isEmpty ? nil : $0 } ?? "pc_share"
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
