//
//  SearchView.swift
//  Schwarznote
//

import SwiftUI

/// 搜索: the system search keyboard on top, then 猜你想搜 before typing, or the results with
/// 小红书's sort and type filters. Results follow the text as it's typed, like other tvOS apps.
struct SearchView: View {
    @Environment(AuthModel.self) private var auth
    @State private var model = SearchModel()
    @State private var text = ""
    @State private var selectedNote: Note?
    @FocusState private var focusedSort: SearchSort?
    @FocusState private var focusedType: SearchNoteType?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    if model.keyword.isEmpty {
                        trending
                    } else {
                        filters
                        results
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 40)
            }
            .searchable(text: $text, prompt: "搜索小红书")
            .searchSuggestions {
                ForEach(model.suggestions, id: \.self) { word in
                    Text(word).searchCompletion(word)
                }
            }
        }
        // Nothing above the keyboard to return to, so the page counts as at the top.
        .backButtonReturnsToTop(isAtTop: true) {}
        .task(id: auth.contentKey) {
            guard auth.contentKey != nil else { return }
            await model.loadTrending(client: auth.client)
            #if DEBUG
            // Launch argument for testing without a remote, e.g. `-searchFor 猫`.
            if let query = UserDefaults.standard.string(forKey: "searchFor"), text.isEmpty { text = query }
            #endif
        }
        // Wait for a pause in typing before asking for completions and results.
        .task(id: text) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, auth.contentKey != nil else { return }
            let client = auth.client
            async let suggestions: Void = model.loadSuggestions(for: text, client: client)
            await model.search(text, client: client)
            await suggestions
        }
        .task(id: "\(model.sort.rawValue)-\(model.noteType.rawValue)") {
            guard !model.keyword.isEmpty else { return }
            await model.search(model.keyword, client: auth.client)
        }
        .fullScreenCover(item: $selectedNote) { note in
            NoteDetailView(note: note, xsecSource: "pc_search")
        }
    }

    // MARK: - Before searching

    @ViewBuilder
    private var trending: some View {
        if !model.trending.isEmpty {
            VStack(alignment: .leading, spacing: 24) {
                Text("猜你想搜")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .leading),
                                         count: 4), alignment: .leading, spacing: 24) {
                    ForEach(model.trending, id: \.self) { word in
                        Button {
                            text = word
                        } label: {
                            Text(word)
                                .font(.callout)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(ChipStyle(isSelected: false))
                    }
                }
            }
            .focusSection()
        }
    }

    // MARK: - Results

    private var filters: some View {
        HStack(spacing: 40) {
            ChipBar(items: SearchSort.allCases, title: \.title, selection: $model.sort, focus: $focusedSort)
                .fixedSize(horizontal: true, vertical: false)
            Divider()
                .frame(height: 40)
            ChipBar(items: SearchNoteType.allCases, title: \.title, selection: $model.noteType, focus: $focusedType)
                .fixedSize(horizontal: true, vertical: false)
            Spacer()
        }
    }

    @ViewBuilder
    private var results: some View {
        let pager = model.results

        if pager.items.isEmpty, let error = pager.error {
            ErrorView(message: error) { await pager.retry() }
        } else if pager.items.isEmpty, !pager.isLoading {
            ContentUnavailableView("没有找到“\(model.keyword)”相关的笔记", systemImage: "magnifyingglass")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 80)
                .focusable()
        }

        LazyVGrid(columns: columns, spacing: 50) {
            ForEach(pager.items) { note in
                Button {
                    selectedNote = note
                } label: {
                    NoteCard(note: note)
                }
                .buttonStyle(.card)
                .task { await pager.loadMoreIfNeeded(current: note) }
            }
        }

        if pager.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }
}
