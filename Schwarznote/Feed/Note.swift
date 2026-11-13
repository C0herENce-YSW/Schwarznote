//
//  Note.swift
//  Schwarznote
//

import SwiftUI

struct Author: Hashable, Sendable {
    let id: String
    let nickname: String
    let avatarURL: URL?
}

struct Note: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let body: String
    let author: Author
    let coverURL: URL?
    /// Cover width / height, used to size cards in the waterfall.
    let coverAspectRatio: CGFloat
    let likeCount: Int
    let isVideo: Bool
    /// Placeholder tint until real cover images load.
    let placeholderHue: Double
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
}

extension Int {
    /// 12345 → "1.2万", like the web client.
    var compactCount: String {
        if self >= 10_000 {
            let value = Double(self) / 10_000
            return String(format: value >= 100 ? "%.0f万" : "%.1f万", value)
        }
        return "\(self)"
    }
}
