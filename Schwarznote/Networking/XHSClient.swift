//
//  XHSClient.swift
//  Schwarznote
//

import Foundation
import OSLog

enum XHSError: LocalizedError, Equatable {
    /// HTTP 406: the request was missing a valid signature.
    case signatureRequired
    case http(Int)
    case api(code: Int, message: String?)
    case emptyData
    case notLoggedIn
    /// Code 300012: the server's risk control rejected the client's network.
    case networkRejected
    /// HTTP 461: the server wants a human verification step the app can't do.
    case verificationRequired

    var errorDescription: String? {
        switch self {
        case .signatureRequired:
            "服务器拒绝了请求（HTTP 406）：请求签名无效，请重试。"
        case .http(let status):
            "网络请求失败（HTTP \(status)）"
        case .api(let code, let message):
            "接口返回错误 \(code)：\(message ?? "未知错误")"
        case .emptyData:
            "接口没有返回数据"
        case .notLoggedIn:
            "登录已失效，请重新扫码"
        case .networkRejected:
            "小红书拒绝了当前网络（错误 300012）。国内站只接受来自中国大陆网络的登录；身在海外时请切换到“rednote（海外）”。"
        case .verificationRequired:
            "小红书要求先完成安全验证（HTTP 461），应用无法代为完成。请稍后再试。"
        }
    }
}

/// Decodes any JSON value and discards it.
nonisolated struct IgnoredPayload: Decodable, Sendable {
    init(from decoder: Decoder) throws {}
}

/// Thin client for the Xiaohongshu / rednote web API.
final class XHSClient {
    let region: XHSRegion
    private let signer: RequestSigner
    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage

    private static let log = Logger(subsystem: "com.seal-yue.Schwarznote", category: "api")

    init(region: XHSRegion, signer: RequestSigner, cookieStorage: HTTPCookieStorage = .shared) {
        self.region = region
        self.signer = signer
        self.cookieStorage = cookieStorage
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = cookieStorage
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        self.session = URLSession(configuration: config)
    }

    var cookies: [HTTPCookie] {
        cookieStorage.cookies(for: region.apiBaseURL) ?? []
    }

    // MARK: - Login

    // The app's own QR login: these are the calls the web page makes, sent by the app itself.

    func createQRCode() async throws -> QRCodeTicket {
        try await post("/api/sns/web/v1/login/qrcode/create", body: ["qr_type": 1])
    }

    func qrCodeStatus(for ticket: QRCodeTicket) async throws -> QRCodeStatus {
        let payload: QRCodeStatusPayload = try await post(
            "/api/qrcode/userinfo",
            body: ["qrId": ticket.qrId, "code": ticket.code]
        )
        return QRCodeStatus(code: payload.codeStatus ?? 0)
    }

    /// After the phone confirms (codeStatus 2), this call is expected to issue the
    /// `web_session` cookie. Observed so far: the server can refuse with "登录异常".
    func completeQRLogin(for ticket: QRCodeTicket) async throws {
        let path = "/api/sns/web/v1/login/qrcode/status?qr_id=\(ticket.qrId)&code=\(ticket.code)"
        do {
            let _: IgnoredPayload = try await get(path)
        } catch XHSError.emptyData {
            // Success without a body is fine; the cookie is what matters.
        }
    }

    func currentUser() async throws -> XHSUser {
        try await get("/api/sns/web/v2/user/me")
    }

    // MARK: - Content

    /// One page of the explore feed. `noteIndex` is how many notes are already shown.
    func homefeed(category: String, cursor: String, noteIndex: Int) async throws -> Pager<Note>.Page {
        let payload: HomefeedPayload = try await post("/api/sns/web/v1/homefeed", body: [
            "category": category,
            "cursor_score": cursor,
            "image_formats": ["jpg", "webp", "avif"],
            "need_filter_image": false,
            "need_num": 20,
            "note_index": noteIndex,
            "num": 30,
            "refresh_type": cursor.isEmpty ? 1 : 3,
            "search_key": "",
            "unread_begin_note_id": "",
            "unread_end_note_id": "",
            "unread_note_count": 0,
        ])
        return .init(items: payload.notes, cursor: payload.cursor, hasMore: true)
    }

    func notifications(_ kind: NotificationKind, cursor: String) async throws -> Pager<NotificationMessage>.Page {
        let page: NotificationPage = try await get(
            "/api/sns/web/v1/you/\(kind.rawValue)" + Self.query(["num": "20", "cursor": cursor])
        )
        return .init(items: page.messages, cursor: page.cursor, hasMore: page.hasMore)
    }

    // MARK: - 私信

    /// Conversations, newest first. `cursor` is the page number as a string ("" = first page).
    func chats(cursor: String) async throws -> Pager<Chat>.Page {
        let page = Int(cursor) ?? 0
        let limit = 50
        let payload: ChatListPayload = try await get("/api/im/web/v3/chats" + Self.query([
            "limit": String(limit), "complete": "true", "page": String(page), "source": "pc",
        ]))
        return .init(items: payload.chats, cursor: String(page + 1), hasMore: payload.chats.count >= limit)
    }

    /// Up to `limit` messages with a store ID of at most `lastStoreID`, oldest first.
    /// Pass the conversation's `maxStoreID` for the latest messages, or the oldest loaded
    /// store ID minus one for earlier ones. Doesn't mark anything as read.
    func chatMessages(userID: String, lastStoreID: Int, limit: Int = 30) async throws -> [ChatMessage] {
        let payload: ChatHistoryPayload = try await get("/api/im/web/messages/history" + Self.query([
            "chat_user_id": userID, "last_id": String(lastStoreID), "start_id": "0", "limit": String(limit),
        ]))
        return payload.messages.sorted { $0.storeID < $1.storeID }
    }

    // MARK: - Note detail

    /// Full note: text, every image / live photo or the video, and interaction counts.
    /// `xsecToken` and `xsecSource` come from where the note was opened: a feed card
    /// ("pc_feed") or the link of a note shared in 私信.
    func noteDetail(id: String, xsecToken: String, xsecSource: String = "pc_feed") async throws -> NoteDetail {
        let payload: NoteDetailPayload = try await post("/api/sns/web/v1/feed", body: [
            "extra": ["need_body_topic": "1"],
            "image_formats": ["jpg", "webp", "avif"],
            "source_note_id": id,
            "xsec_source": xsecSource,
            "xsec_token": xsecToken,
        ])
        return payload.note
    }

    func comments(noteID: String, xsecToken: String, cursor: String) async throws -> Pager<Comment>.Page {
        let page: CommentPage = try await get("/api/sns/web/v2/comment/page" + Self.query([
            "note_id": noteID, "cursor": cursor, "top_comment_id": "",
            "image_formats": "jpg,webp,avif", "xsec_token": xsecToken,
        ]))
        return .init(items: page.comments, cursor: page.cursor, hasMore: page.hasMore)
    }

    /// More replies under one top-level comment.
    func replies(noteID: String, rootID: String, xsecToken: String, cursor: String) async throws -> CommentPage {
        try await get("/api/sns/web/v2/comment/sub/page" + Self.query([
            "note_id": noteID, "root_comment_id": rootID, "num": "10", "cursor": cursor,
            "image_formats": "jpg,webp,avif", "top_comment_id": "", "xsec_token": xsecToken,
        ]))
    }

    // MARK: - Search

    /// One page of notes matching `keyword`, in 小红书's ranking for `sort`. Pages start at 1.
    func searchNotes(keyword: String, page: Int, searchID: String, sort: SearchSort,
                     noteType: SearchNoteType) async throws -> Pager<Note>.Page {
        let payload: SearchNotesPage = try await post("/api/sns/web/v1/search/notes", body: [
            "keyword": keyword,
            "page": page,
            "page_size": 20,
            "search_id": searchID,
            "sort": sort.rawValue,
            "note_type": noteType.rawValue,
            "ext_flags": [Any](),
            "filters": [Any](),
            "geo": "",
            "image_formats": ["jpg", "webp", "avif"],
        ])
        return .init(items: payload.notes, cursor: String(page + 1), hasMore: payload.hasMore)
    }

    /// One page of accounts matching `keyword`. Pages start at 1.
    func searchUsers(keyword: String, page: Int, searchID: String) async throws -> Pager<UserSearchResult>.Page {
        let requestID = "\(Int.random(in: 1...0x7ffffffe))-\(Int(Date.now.timeIntervalSince1970 * 1000))"
        let payload: UserSearchPage = try await post("/api/sns/web/v1/search/usersearch", body: [
            "search_user_request": [
                "keyword": keyword,
                "search_id": searchID,
                "page": page,
                "page_size": 15,
                "biz_type": "web_search_user",
                "request_id": requestID,
            ] as [String: Any],
        ])
        return .init(items: payload.users, cursor: String(page + 1), hasMore: payload.hasMore)
    }

    /// Completions for a partly typed query.
    func searchSuggestions(for keyword: String) async throws -> [String] {
        let payload: SearchWordsPayload = try await get(
            "/api/sns/web/v1/search/recommend" + Self.query(["keyword": keyword])
        )
        return payload.words
    }

    /// 猜你想搜: what 小红书 suggests before anything is typed.
    func trendingSearches() async throws -> [String] {
        let payload: SearchWordsPayload = try await get("/api/sns/web/v1/search/querytrending" + Self.query([
            "source": "Explore", "search_type": "trend", "last_query": "", "last_query_time": "0",
            "word_request_situation": "FIRST_ENTER", "hint_word": "", "hint_word_type": "",
            "hint_word_request_id": "",
        ]))
        return payload.words
    }

    // MARK: - Users

    /// Someone else's profile. `xsecSource` is where it was opened from ("pc_note" from a note).
    func userProfile(id: String, xsecToken: String, xsecSource: String) async throws -> UserProfile {
        try await get("/api/sns/web/v1/user/otherinfo" + Self.query([
            "target_user_id": id, "xsec_token": xsecToken, "xsec_source": xsecSource,
        ]))
    }

    /// The user's posted notes, newest first.
    func userNotes(id: String, xsecToken: String, xsecSource: String, cursor: String) async throws -> Pager<Note>.Page {
        let page: UserNotesPage = try await get("/api/sns/web/v1/user_posted" + Self.query([
            "num": "30", "cursor": cursor, "user_id": id, "image_formats": "jpg,webp,avif",
            "xsec_token": xsecToken, "xsec_source": xsecSource,
        ]))
        return .init(items: page.notes, cursor: page.cursor, hasMore: page.hasMore)
    }

    /// Follows or unfollows a user and returns the new relation.
    func setFollowing(_ following: Bool, userID: String, current: FollowRelation) async throws -> FollowRelation {
        let path = following ? "/api/sns/web/v1/user/follow" : "/api/sns/web/v1/user/unfollow"
        let expected = current.with(following: following)
        do {
            let payload: FollowPayload = try await post(path, body: ["target_user_id": userID])
            return payload.relation ?? expected
        } catch XHSError.emptyData {
            return expected
        }
    }

    // MARK: - Actions

    func setLiked(_ liked: Bool, noteID: String) async throws {
        try await action(liked ? "/api/sns/web/v1/note/like" : "/api/sns/web/v1/note/dislike",
                         body: ["note_oid": noteID])
    }

    func setCollected(_ collected: Bool, noteID: String) async throws {
        if collected {
            try await action("/api/sns/web/v1/note/collect", body: ["note_id": noteID])
        } else {
            try await action("/api/sns/web/v1/note/uncollect", body: ["note_ids": noteID])
        }
    }

    func setCommentLiked(_ liked: Bool, noteID: String, commentID: String) async throws {
        try await action(liked ? "/api/sns/web/v1/comment/like" : "/api/sns/web/v1/comment/dislike",
                         body: ["note_id": noteID, "comment_id": commentID])
    }

    /// Posts a comment on the note, or a reply when `replyTo` is a comment ID.
    func postComment(noteID: String, content: String, replyTo: String?) async throws -> Comment {
        var body: [String: Any] = ["note_id": noteID, "content": content, "at_users": [Any]()]
        if let replyTo { body["target_comment_id"] = replyTo }
        let payload: CommentPostPayload = try await post("/api/sns/web/v1/comment/post", body: body)
        return payload.comment
    }

    /// POST whose response body we don't need.
    private func action(_ path: String, body: [String: Any]) async throws {
        do {
            let _: IgnoredPayload = try await post(path, body: body)
        } catch XHSError.emptyData {
            // Success without data.
        }
    }

    /// Query string in a fixed order. Commas stay literal, as the web client sends them.
    private static func query(_ items: KeyValuePairs<String, String>) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.,")
        return "?" + items.map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
    }

    // MARK: - Requests

    private func get<T: Decodable & Sendable>(_ path: String) async throws -> T {
        var request = makeRequest(path: path)
        request.httpMethod = "GET"
        return try await send(request, path: path, body: nil)
    }

    private func post<T: Decodable & Sendable>(_ path: String, body: [String: Any]) async throws -> T {
        // Compact JSON with no spaces: the signature covers the exact body bytes.
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
        var request = makeRequest(path: path)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json;charset=utf-8", forHTTPHeaderField: "Content-Type")
        return try await send(request, path: path, body: data)
    }

    private func makeRequest(path: String) -> URLRequest {
        var request = URLRequest(url: URL(string: path, relativeTo: region.apiBaseURL)!)
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(region.webOrigin, forHTTPHeaderField: "Origin")
        request.setValue(region.webOrigin + "/", forHTTPHeaderField: "Referer")
        request.setValue(WebPage.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        return request
    }

    #if DEBUG
    /// Login and account responses carry session tokens; log only their code and message.
    private static func loggableBody(_ data: Data, path: String) -> String {
        // The scan status also carries the scanning account's id and country.
        let sensitive = ["/login/qrcode/status", "/login/activate", "/user/me", "/qrcode/userinfo"]
        guard sensitive.contains(where: path.contains) else {
            return String(decoding: data.prefix(500), as: UTF8.self)
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return "[redacted] code=\(json?["code"] ?? "?") msg=\(json?["msg"] ?? "?")"
    }
    #endif

    private func send<T: Decodable & Sendable>(_ request: URLRequest, path: String, body: Data?) async throws -> T {
        var request = request
        let signature = try await signer.sign(region: region, path: path, body: body)
        for (key, value) in signature.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if signature.path != path {
            request.url = URL(string: signature.path, relativeTo: region.apiBaseURL)
        }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        #if DEBUG
        let setCookies = ((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Set-Cookie") ?? "")
            .split(separator: ",").compactMap { $0.split(separator: "=").first?.trimmingCharacters(in: .whitespaces) }
        Self.log.notice("""
            \(path, privacy: .public) → \(status) set-cookie=\(setCookies.joined(separator: ","), privacy: .public) \
            body=\(Self.loggableBody(data, path: path), privacy: .public)
            """)
        #endif
        switch status {
        case 200..<300: break
        case 406: throw XHSError.signatureRequired
        case 461: throw XHSError.verificationRequired
        case 401: throw XHSError.notLoggedIn
        default: throw XHSError.http(status)
        }

        let envelope = try JSONDecoder().decode(XHSResponse<T>.self, from: data)
        guard envelope.success else {
            if envelope.code == 300012 { throw XHSError.networkRejected }
            // "登录已过期": the saved session is no longer valid (sent with HTTP 200).
            if envelope.code == -100 { throw XHSError.notLoggedIn }
            throw XHSError.api(code: envelope.code, message: envelope.msg)
        }
        guard let payload = envelope.data else { throw XHSError.emptyData }
        return payload
    }
}
