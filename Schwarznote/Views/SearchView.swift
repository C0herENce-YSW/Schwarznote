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
    @State private var selectedUser: UserProfileModel?
    @FocusState private var focusedScope: SearchScope?
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
                        switch model.scope {
                        case .notes: results
                        case .users: userResults
                        }
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
            // Launch argument for testing without a remote, e.g. `-searchFor 猫 -searchScope users`.
            if let query = UserDefaults.standard.string(forKey: "searchFor"), text.isEmpty { text = query }
            if let scope = UserDefaults.standard.string(forKey: "searchScope").flatMap(SearchScope.init(rawValue:)) {
                model.scope = scope
            }
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
        .task(id: "\(model.scope.rawValue)-\(model.sort.rawValue)-\(model.noteType.rawValue)") {
            guard !model.keyword.isEmpty else { return }
            await model.search(model.keyword, client: auth.client)
        }
        .fullScreenCover(item: $selectedNote) { note in
            NoteDetailView(note: note, xsecSource: "pc_search")
        }
        .fullScreenCover(item: $selectedUser) { profile in
            UserProfileView(model: profile)
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

    /// 笔记 / 用户, then for notes the sort and type.
    private var filters: some View {
        HStack(spacing: 40) {
            ChipBar(items: SearchScope.allCases, title: \.title, selection: $model.scope, focus: $focusedScope)
                .fixedSize(horizontal: true, vertical: false)
            if model.scope == .notes {
                Divider()
                    .frame(height: 40)
                ChipBar(items: SearchSort.allCases, title: \.title, selection: $model.sort, focus: $focusedSort)
                    .fixedSize(horizontal: true, vertical: false)
                Divider()
                    .frame(height: 40)
                ChipBar(items: SearchNoteType.allCases, title: \.title, selection: $model.noteType,
                        focus: $focusedType)
                    .fixedSize(horizontal: true, vertical: false)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var userResults: some View {
        let pager = model.users

        if pager.items.isEmpty, let error = pager.error {
            ErrorView(message: error) { await pager.retry() }
        } else if pager.items.isEmpty, !pager.isLoading {
            ContentUnavailableView("没有找到“\(model.keyword)”相关的用户", systemImage: "person.slash")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 80)
                .focusable()
        }

        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 40), count: 2), spacing: 30) {
            ForEach(pager.items) { user in
                Button {
                    selectedUser = UserProfileModel(author: user.author, relation: user.relation,
                                                    fallbackToken: nil, xsecSource: "pc_search")
                } label: {
                    UserResultRow(user: user)
                }
                .buttonStyle(RowStyle())
                .task { await pager.loadMoreIfNeeded(current: user) }
            }
        }

        if pager.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
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

/// One account in the 用户 results: avatar, name, 小红书号, fans and notes.
private struct UserResultRow: View {
    let user: UserSearchResult

    var body: some View {
        HStack(spacing: 28) {
            AvatarView(author: user.author, size: 110)
            VStack(alignment: .leading, spacing: 10) {
                Text(user.author.nickname)
                    .font(.headline)
                    .lineLimit(1)
                let details = [user.redID.map { "小红书号：\($0)" },
                               user.fans.map { "粉丝 \($0)" },
                               user.noteCount.map { "笔记 \($0)" }].compactMap { $0 }
                if !details.isEmpty {
                    Text(details.joined(separator: "  ·  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if user.relation.isFollowing {
                Text("已关注")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
