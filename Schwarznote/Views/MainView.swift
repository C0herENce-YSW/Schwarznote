//
//  MainView.swift
//  Schwarznote
//

import SwiftUI

/// App shell: a tab bar across the top of the screen (发现 / 搜索 / 消息 / 设置, and 我 with
/// the account's avatar at the right end) over the selected page. Browsing works without
/// logging in, like on the web.
struct MainView: View {
    enum TabID: String, CaseIterable {
        case explore, search, messages, settings, me

        var title: String {
            switch self {
            case .explore: "发现"
            case .search: "搜索"
            case .messages: "消息"
            case .settings: "设置"
            case .me: "我"
            }
        }
    }

    /// Start tab can be set with a launch argument, e.g. `-selectedTab me`.
    @State private var selection = UserDefaults.standard.string(forKey: "selectedTab")
        .flatMap(TabID.init(rawValue:)) ?? .explore
    /// Pages are created on first visit and then kept, so each keeps its place.
    @State private var visited: Set<TabID> = []

    @State private var exitGuard = ExitGuard()

    var body: some View {
        VStack(spacing: 0) {
            TopTabBar(selection: $selection)
            pages
        }
        .environment(exitGuard)
        .overlay(alignment: .top) {
            if exitGuard.showsHint {
                ExitHint()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: exitGuard.showsHint)
        .onChange(of: selection, initial: true) { visited.insert(selection) }
    }

    private var pages: some View {
        ZStack {
            ForEach(TabID.allCases, id: \.self) { tab in
                if visited.contains(tab) {
                    page(tab)
                        .opacity(tab == selection ? 1 : 0)
                        // Hidden pages must not take focus.
                        .disabled(tab != selection)
                        .accessibilityHidden(tab != selection)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func page(_ tab: TabID) -> some View {
        switch tab {
        case .explore: ExploreView()
        case .search: SearchView()
        case .messages: MessagesView()
        case .settings: SettingsView()
        case .me: ProfileView()
        }
    }
}

/// The row of tabs at the top. Like the system tab bar, landing on a tab switches to it.
/// The back button here follows the top-level rule: press twice to leave the app.
struct TopTabBar: View {
    @Binding var selection: MainView.TabID
    @Environment(AuthModel.self) private var auth
    @Environment(ExitGuard.self) private var exitGuard
    @FocusState private var focused: MainView.TabID?

    var body: some View {
        HStack(spacing: 20) {
            ForEach(MainView.TabID.allCases.filter { $0 != .me }, id: \.self) { tab in
                tabButton(tab) {
                    Text(tab.title)
                }
            }
            Spacer()
            tabButton(.me) {
                HStack(spacing: 16) {
                    avatar
                    Text(MainView.TabID.me.title)
                }
            }
        }
        .padding(.horizontal, 60)
        .padding(.top, 30)
        .padding(.bottom, 10)
        .focusSection()
        .onChange(of: focused) { old, tab in
            guard let tab else { return }
            // Coming up from a page, the focus engine picks the tab nearest the focused item,
            // which would switch pages; go back to the current tab instead.
            if old == nil, tab != selection {
                focused = selection
            } else {
                selection = tab
            }
        }
        .onAppear { focused = selection }
        .onExitCommand { exitGuard.backPressedAtTop() }
    }

    private func tabButton(_ tab: MainView.TabID, @ViewBuilder label: () -> some View) -> some View {
        Button {
            selection = tab
        } label: {
            label()
                .font(.headline)
                .fontWeight(tab == selection ? .bold : .regular)
                .padding(.horizontal, 12)
        }
        .buttonStyle(ChipStyle(isSelected: tab == selection))
        .focused($focused, equals: tab)
    }

    /// The account's avatar, or a placeholder when logged out.
    @ViewBuilder
    private var avatar: some View {
        if let user = auth.currentUser {
            AvatarView(
                author: Author(id: user.userId ?? "", nickname: user.nickname ?? "我",
                               avatarURL: URL(webImage: user.avatarURL)),
                size: 44
            )
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: 44, height: 44)
                .foregroundStyle(.secondary)
        }
    }
}

struct SearchView: View {
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                query.isEmpty ? "搜索笔记、用户" : "搜索“\(query)”",
                systemImage: "magnifyingglass",
                description: Text("搜索需要接通登录后才能使用")
            )
            .searchable(text: $query, prompt: "搜索小红书")
        }
        // Nothing to scroll here yet, so the page is always at the top.
        .backButtonReturnsToTop(isAtTop: true) {}
    }
}

/// Shown for features that need an account.
struct LoginRequiredView: View {
    let feature: String

    var body: some View {
        ContentUnavailableView(
            "登录后查看\(feature)",
            systemImage: "lock",
            description: Text("请在“我”页面扫码登录")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Focusable so the remote can move up from this page into the tab bar.
        .focusable()
    }
}

/// 我: profile when logged in, QR login otherwise.
struct ProfileView: View {
    @Environment(AuthModel.self) private var auth

    var body: some View {
        switch auth.state {
        case .restoring:
            ProgressView()
        case .loggedOut:
            LoginView()
        case .loggedIn(let user):
            HomeView(user: user)
        }
    }
}
