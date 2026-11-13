//
//  Pager.swift
//  Schwarznote
//

import Foundation
import Observation

/// Cursor-based infinite list, shared by the explore feed and notifications.
@Observable
final class Pager<Item: Identifiable & Sendable> {
    struct Page {
        let items: [Item]
        let cursor: String
        let hasMore: Bool
    }

    /// Fetches the page after `cursor`; `count` is how many items are already loaded.
    typealias Fetch = (_ cursor: String, _ count: Int) async throws -> Page

    private(set) var items: [Item] = []
    private(set) var isLoading = false
    private(set) var error: String?

    private var fetch: Fetch?
    private var cursor = ""
    private var hasMore = true
    /// Bumped on reset so responses for an old source are dropped.
    private var generation = 0

    func reset(_ fetch: @escaping Fetch) async {
        self.fetch = fetch
        generation += 1
        items = []
        cursor = ""
        hasMore = true
        error = nil
        isLoading = false
        await loadMore()
    }

    func retry() async {
        if let fetch { await reset(fetch) }
    }

    /// Call when an item near the end appears.
    func loadMoreIfNeeded(current item: Item) async {
        guard let index = items.firstIndex(where: { $0.id == item.id }), index >= items.count - 8 else { return }
        await loadMore()
    }

    private func loadMore() async {
        guard let fetch, hasMore, !isLoading else { return }
        let generation = generation
        isLoading = true
        do {
            let page = try await fetch(cursor, items.count)
            guard generation == self.generation else { return }
            var seen = Set(items.map(\.id))
            items += page.items.filter { seen.insert($0.id).inserted }
            cursor = page.cursor
            hasMore = page.hasMore && !page.items.isEmpty
        } catch {
            guard generation == self.generation else { return }
            let cancelled = error is CancellationError || (error as? URLError)?.code == .cancelled
            if !cancelled { self.error = error.localizedDescription }
        }
        isLoading = false
    }
}
