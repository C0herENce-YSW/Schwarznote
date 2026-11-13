//
//  ContentView.swift
//  Schwarznote
//
//  Created by C0herENce on 13/11/2026.
//

import SwiftUI

struct ContentView: View {
    @Environment(AuthModel.self) private var auth

    var body: some View {
        Group {
            switch auth.state {
            case .restoring:
                ProgressView()
            case .loggedOut:
                LoginView()
            case .loggedIn(let user):
                HomeView(user: user)
            }
        }
        .task { await auth.restore() }
    }
}

#Preview {
    ContentView()
        .environment(AuthModel())
}
