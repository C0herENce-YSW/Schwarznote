//
//  Note.swift
//  Schwarznote
//

import SwiftUI

nonisolated struct Author: Hashable, Sendable, Decodable {
    let id: String
    let nickname: String
    let avatarURL: URL?

    init(id: String, nickname: String, avatarURL: URL?) {
        self.id = id
        self.nickname = nickname
        self.avatarURL = avatarURL
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.string("user_id", "userid") ?? ""
        nickname = c.string("nickname", "nick_name") ?? ""
        avatarURL = URL(webImage: c.string("avatar", "image", "images"))
    }
}

/// One card of `POST /api/sns/web/v1/homefeed` → data.items.
nonisolated struct Note: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    /// Needed later to open the note's detail.
    let xsecToken: String?
    let title: String
    let author: Author
    let coverURL: URL?
    /// Cover width / height, used to size cards in the waterfall.
    let coverAspectRatio: CGFloat
    /// Already formatted by the server, e.g. "453" or "1.2万".
    let likes: String
    let isVideo: Bool

    private struct NotANote: Error {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        guard let id = c.string("id"), c.string("model_type") ?? "note" == "note",
              let card = c.nested("note_card") else { throw NotANote() }
        self.id = id
        xsecToken = c.string("xsec_token")
        title = card.string("display_title") ?? ""
        author = try card.decode(Author.self, forKey: AnyKey("user"))
        let cover = card.nested("cover")
        coverURL = URL(webImage: cover?.string("url_default", "url_pre", "url"))
        if let width = cover?.double("width"), let height = cover?.double("height"), width > 0, height > 0 {
            coverAspectRatio = width / height
        } else {
            coverAspectRatio = 3.0 / 4.0
        }
        likes = card.nested("interact_info")?.string("liked_count") ?? "0"
        isVideo = card.string("type") == "video"
    }
}

/// Feed channels, in the same order as the web explore page.
enum Channel: String, CaseIterable, Identifiable, Sendable {
    case recommend = "推荐"
    case fashion = "穿搭"
    case food = "美食"
    case makeup = "彩妆"
    case movies = "影视"
    case career = "职场"
    case emotion = "情感"
    case home = "家居"
    case games = "游戏"
    case travel = "旅行"
    case fitness = "健身"

    var id: String { rawValue }

    /// `category` for the homefeed request; the same on both sites.
    var category: String {
        switch self {
        case .recommend: "homefeed_recommend"
        case .fashion: "homefeed.fashion_v3"
        case .food: "homefeed.food_v3"
        case .makeup: "homefeed.cosmetics_v3"
        case .movies: "homefeed.movie_and_tv_v3"
        case .career: "homefeed.career_v3"
        case .emotion: "homefeed.love_v3"
        case .home: "homefeed.household_product_v3"
        case .games: "homefeed.gaming_v3"
        case .travel: "homefeed.travel_v3"
        case .fitness: "homefeed.fitness_v3"
        }
    }
}
