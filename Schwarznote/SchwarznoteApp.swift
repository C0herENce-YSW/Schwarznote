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
    @State private var shortcuts = ShortcutCenter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(auth)
                .environment(shortcuts)
                .background(PressMonitor(center: shortcuts))
        }
    }
}
