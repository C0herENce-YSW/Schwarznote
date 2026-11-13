//
//  SchwarznoteApp.swift
//  Schwarznote
//
//  Created by C0herENce on 13/11/2026.
//

import SwiftUI

@main
struct SchwarznoteApp: App {
    @State private var auth = AuthModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(auth)
        }
    }
}
