//
//  MainView.swift
//  Schwarznote
//

import SwiftUI

/// App shell modeled on the web client's left navigation: 发现 / 搜索 / 通知 / 我.
/// Browsing works without logging in, like on the web.
struct MainView: View {
    enum TabID: String { case explore, search, notifications, me }

    /// Start tab can be set with a launch argument, e.g. `-selectedTab me`.
    @State private var selection = UserDefaults.standard.string(forKey: "selectedTab")
        .flatMap(TabID.init(rawValue:)) ?? .explore

    var body: some View {
        TabView(selection: $selection) {
            Tab("发现", systemImage: "house", value: .explore) {
                ExploreView()
            }
            Tab("搜索", systemImage: "magnifyingglass", value: .search, role: .search) {
                SearchView()
            }
            Tab("通知", systemImage: "bell", value: .notifications) {
                LoginRequiredView(feature: "通知")
            }
            Tab("我", systemImage: "person", value: TabID.me) {
                ProfileView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
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
