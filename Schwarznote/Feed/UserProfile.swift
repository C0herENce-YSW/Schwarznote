//
//  UserProfile.swift
//  Schwarznote
//

import Foundation
import Observation

/// How the account and another user follow each other, as the API names it.
nonisolated enum FollowRelation: String, Sendable {
    case none
    /// The account follows them.
    case follows
    /// They follow the account.
    case fans
    case both

    var isFollowing: Bool { self == .follows || self == .both }

    func with(following: Bool) -> FollowRelation {
        let followsBack = self == .fans || self == .both
        switch (following, followsBack) {
        case (true, true): return .both
        case (true, false): return .follows
        case (false, true): return .fans
        case (false, false): return .none
        }
    }

    /// Button title, as on the web.
    var title: String {
        switch self {
        case .none: "关注"
        case .fans: "回关"
        case .follows: "已关注"
        case .both: "互相关注"
        }
    }
}

/// `GET /api/sns/web/v1/user/otherinfo` → data (only the fields we show).
nonisolated struct UserProfile: Sendable, Decodable {
    struct Stat: Sendable, Hashable {
        let name: String
        let count: String
    }

    let nickname: String
    let avatarURL: URL?
    let redID: String?
    let bio: String
    let ipLocation: String?
    /// 关注 / 粉丝 / 获赞与收藏, in the server's order.
    let stats: [Stat]
    let relation: FollowRelation

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let basic = c.nested("basic_info")
        nickname = basic?.string("nickname") ?? ""
        avatarURL = URL(webImage: basic?.string("imageb", "images"))
        redID = basic?.string("red_id")
        bio = basic?.string("desc") ?? ""
        ipLocation = basic?.string("ip_location")
        stats = (c.value([StatEntry].self, "interactions") ?? []).map { Stat(name: $0.name, count: $0.count) }
        relation = FollowRelation(rawValue: c.nested("extra_info")?.string("fstatus") ?? "") ?? .none
    }

    private struct StatEntry: Decodable {
        let name: String
        let count: String

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            name = c.string("name") ?? ""
            count = c.string("count") ?? "0"
        }
    }
}

/// `GET /api/sns/web/v1/user_posted` → data
nonisolated struct UserNotesPage: Decodable, Sendable {
    let notes: [Note]
    let cursor: String
    let hasMore: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        notes = c.value(LossyArray<Note>.self, "notes")?.elements ?? []
        cursor = c.string("cursor") ?? ""
        hasMore = c.value(Bool.self, "has_more") ?? false
    }
}

/// `POST /api/sns/web/v1/user/follow` and `/unfollow` → data, when the server says the new relation.
nonisolated struct FollowPayload: Decodable, Sendable {
    let relation: FollowRelation?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        relation = c.string("fstatus").flatMap(FollowRelation.init(rawValue:))
    }
}

/// One open profile: the user's info, their notes, and following them.
@Observable
final class UserProfileModel: Identifiable {
    let author: Author
    private(set) var profile: UserProfile?
    private(set) var loadError: String?
    private(set) var relation: FollowRelation
    /// Shown as an alert when following fails.
    var actionError: String?
    let notes = Pager<Note>()
    /// Tells the note the profile was opened from, so its button matches.
    var onRelationChange: ((FollowRelation) -> Void)?

    private let xsecToken: String
    private let xsecSource = "pc_note"

    var id: String { author.id }

    /// `fallbackToken` is the note's token, for authors that arrive without their own.
    init(author: Author, relation: FollowRelation, fallbackToken: String?) {
        self.author = author
        self.relation = relation
        xsecToken = author.xsecToken ?? fallbackToken ?? ""
    }

    func load(client: XHSClient) async {
        let id = author.id
        let token = xsecToken
        let source = xsecSource
        async let notesLoaded: Void = notes.reset { cursor, _ in
            try await client.userNotes(id: id, xsecToken: token, xsecSource: source, cursor: cursor)
        }
        do {
            let profile = try await client.userProfile(id: id, xsecToken: token, xsecSource: source)
            self.profile = profile
            relation = profile.relation
        } catch {
            loadError = error.localizedDescription
        }
        await notesLoaded
    }

    func setFollowing(_ following: Bool, client: XHSClient) async {
        let before = relation
        relation = before.with(following: following)
        do {
            relation = try await client.setFollowing(following, userID: author.id, current: before)
            onRelationChange?(relation)
        } catch {
            relation = before
            actionError = error.localizedDescription
        }
    }
}
