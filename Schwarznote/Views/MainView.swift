//
//  MainView.swift
//  Schwarznote
//

import SwiftUI

/// App shell modeled on the web client's left navigation: 发现 / 搜索 / 通知 / 我.
/// Browsing works without logging in, like on the web.
struct MainView: View {
    var body: some View {
        TabView {
            Tab("发现", systemImage: "house") {
                ExploreView()
            }
            Tab("搜索", systemImage: "magnifyingglass", role: .search) {
                SearchView()
            }
            Tab("通知", systemImage: "bell") {
                LoginRequiredView(feature: "通知")
            }
            Tab("我", systemImage: "person") {
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
