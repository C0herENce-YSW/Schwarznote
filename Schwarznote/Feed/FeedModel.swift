//
//  FeedModel.swift
//  Schwarznote
//

import Foundation
import Observation

/// Source of notes for a channel. Placeholder data for now; the real
/// homefeed API plugs in here once login works.
protocol FeedProvider: Sendable {
    func notes(for channel: Channel, page: Int) async throws -> [Note]
}

@Observable
final class FeedModel {
    private(set) var notes: [Note] = []
    private(set) var isLoading = false
    var channel: Channel = .recommend {
        didSet { if channel != oldValue { Task { await reload() } } }
    }

    private let provider: FeedProvider
    private var page = 0

    init(provider: FeedProvider = PlaceholderFeedProvider()) {
        self.provider = provider
    }

    func reload() async {
        page = 0
        notes = []
        await loadMore()
    }

    /// Call when a card near the end gets focus.
    func loadMoreIfNeeded(current note: Note) async {
        guard let index = notes.firstIndex(of: note), index >= notes.count - 8 else { return }
        await loadMore()
    }

    private func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if let more = try? await provider.notes(for: channel, page: page) {
            notes += more
            page += 1
        }
    }
}

/// Generates deterministic fake notes so the UI can be built without the API.
struct PlaceholderFeedProvider: FeedProvider {
    private static let titles = [
        "周末去哪儿｜城市里的小众咖啡馆合集", "一周通勤穿搭不重样", "十分钟搞定的快手早餐",
        "租房改造｜三千块打造温馨小窝", "这部电影后劲太大了", "新手也能学会的日常妆",
        "第一次去冰岛的旅行攻略", "每天二十分钟，坚持一个月的变化", "职场沟通的五个小技巧",
        "秋天就该吃这一锅", "收纳博主都在用的好物", "猫咪的迷惑行为大赏",
        "独居女孩的周末日常", "阳台小花园养成记", "人生第一台相机怎么选",
    ]
    private static let names = ["小鹿酱", "momo", "今天吃什么", "旅行的意义", "阿忘", "Luna", "橘子汽水", "一只胖狸"]
    private static let ratios: [CGFloat] = [3.0 / 4.0, 1, 4.0 / 3.0, 3.0 / 4.0, 9.0 / 16.0, 3.0 / 4.0]

    func notes(for channel: Channel, page: Int) async throws -> [Note] {
        try await Task.sleep(for: .milliseconds(200))
        let seed = Channel.allCases.firstIndex(of: channel)! * 1000 + page * 30
        return (0..<30).map { offset in
            let n = seed + offset
            let author = Author(id: "u\(n % 8)", nickname: Self.names[n % Self.names.count], avatarURL: nil)
            return Note(
                id: "\(channel.rawValue)-\(n)",
                title: (channel == .recommend ? "" : "#\(channel.rawValue) ") + Self.titles[n % Self.titles.count],
                body: "这里是笔记正文的占位内容。登录功能接通后，会显示真实的笔记内容、图片和评论。",
                author: author,
                coverURL: nil,
                coverAspectRatio: Self.ratios[n % Self.ratios.count],
                likeCount: (n * 7919) % 50_000,
                isVideo: n % 5 == 0,
                placeholderHue: Double((n * 37) % 360) / 360
            )
        }
    }
}
