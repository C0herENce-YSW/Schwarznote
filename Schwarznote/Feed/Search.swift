//
//  Search.swift
//  Schwarznote
//

import Foundation
import Observation

/// Result order. 综合 is 小红书's own ranking; the others reorder the same matches.
enum SearchSort: String, CaseIterable, Hashable, Sendable {
    case general
    case latest = "time_descending"
    case popular = "popularity_descending"

    var title: String {
        switch self {
        case .general: "综合"
        case .latest: "最新"
        case .popular: "最热"
        }
    }
}

enum SearchNoteType: Int, CaseIterable, Hashable, Sendable {
    case all = 0
    case video = 1
    case image = 2

    var title: String {
        switch self {
        case .all: "全部"
        case .video: "视频"
        case .image: "图文"
        }
    }
}

/// `POST /api/sns/web/v1/search/notes` → data
nonisolated struct SearchNotesPage: Decodable, Sendable {
    let notes: [Note]
    let hasMore: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        // Besides notes, items can be related-search rows; Note's decoder skips those.
        notes = c.value(LossyArray<Note>.self, "items")?.elements ?? []
        hasMore = c.value(Bool.self, "has_more") ?? false
    }
}

/// `GET /api/sns/web/v1/search/recommend` → data.sug_items, and
/// `GET /api/sns/web/v1/search/querytrending` → data.queries
nonisolated struct SearchWordsPayload: Decodable, Sendable {
    let words: [String]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let entries = c.value([Word].self, "sug_items") ?? c.value([Word].self, "queries") ?? []
        var seen = Set<String>()
        words = entries.compactMap(\.text).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private struct Word: Decodable {
        let text: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            text = c.string("search_word", "text", "title")
        }
    }
}

/// Search ID as the web client makes it: (milliseconds << 64) + a random number, in base 36.
/// One ID covers every page and sort of the same query.
nonisolated func makeSearchID(now: Date = .now) -> String {
    var high = UInt64(now.timeIntervalSince1970 * 1000)
    var low = UInt64.random(in: 1...0x7ffffffe)
    let digits = Array("0123456789abcdefghijklmnopqrstuvwxyz")
    var result: [Character] = []
    while high > 0 || low > 0 {
        let (highQuotient, highRemainder) = high.quotientAndRemainder(dividingBy: 36)
        let (lowQuotient, remainder) = UInt64(36).dividingFullWidth((high: highRemainder, low: low))
        high = highQuotient
        low = lowQuotient
        result.append(digits[Int(remainder)])
    }
    return String(result.reversed())
}

/// The 搜索 page's state: the query, its results, and the words 小红书 suggests.
@Observable
final class SearchModel {
    /// What the results are for; empty before the first search.
    private(set) var keyword = ""
    var sort = SearchSort.general
    var noteType = SearchNoteType.all
    let results = Pager<Note>()
    /// Completions for what's being typed.
    private(set) var suggestions: [String] = []
    /// 猜你想搜, shown before searching.
    private(set) var trending: [String] = []

    private var searchID = ""

    func loadTrending(client: XHSClient) async {
        guard trending.isEmpty else { return }
        trending = (try? await client.trendingSearches()) ?? []
    }

    func loadSuggestions(for text: String, client: XHSClient) async {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            suggestions = []
            return
        }
        let words = (try? await client.searchSuggestions(for: text)) ?? []
        guard !Task.isCancelled else { return }
        suggestions = words
    }

    /// Runs the search for `text` with the current sort and type. A new keyword gets a new search ID.
    func search(_ text: String, client: XHSClient) async {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            keyword = ""
            return
        }
        if text != keyword || searchID.isEmpty {
            keyword = text
            searchID = makeSearchID()
        }
        let id = searchID
        let sort = sort
        let noteType = noteType
        await results.reset { cursor, _ in
            try await client.searchNotes(keyword: text, page: Int(cursor) ?? 1, searchID: id,
                                         sort: sort, noteType: noteType)
        }
    }
}
