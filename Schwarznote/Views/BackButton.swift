//
//  BackButton.swift
//  Schwarznote
//
//  Menu / back button on the top-level pages, replacing the system behaviour:
//  1. not at the top → jump back to the top
//  2. at the top     → show "再按一次返回键退出"
//  3. again within 2 seconds → leave the app
//

import SwiftUI
import UIKit

@Observable
final class ExitGuard {
    private(set) var showsHint = false
    private var hideTask: Task<Void, Never>?

    func backPressedAtTop() {
        if showsHint {
            leaveApp()
        } else {
            showsHint = true
            hideTask?.cancel()
            hideTask = Task {
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled { showsHint = false }
            }
        }
    }

    func reset() {
        hideTask?.cancel()
        showsHint = false
    }

    /// Goes back to the Home screen like the system back button does. There is no public API
    /// for this; `suspend` is what the system itself calls. An App Store build would need another way.
    private func leaveApp() {
        reset()
        UIApplication.shared.perform(NSSelectorFromString("suspend"))
    }
}

extension View {
    /// Handles the back button on a top-level page. `isAtTop` is true while focus is in the
    /// page's top row; `scrollToTop` moves focus there.
    func backButtonReturnsToTop(isAtTop: Bool, scrollToTop: @escaping () -> Void) -> some View {
        modifier(BackToTop(isAtTop: isAtTop, scrollToTop: scrollToTop))
    }
}

private struct BackToTop: ViewModifier {
    @Environment(ExitGuard.self) private var exitGuard
    let isAtTop: Bool
    let scrollToTop: () -> Void

    func body(content: Content) -> some View {
        content.onExitCommand {
            if isAtTop {
                exitGuard.backPressedAtTop()
            } else {
                exitGuard.reset()
                scrollToTop()
            }
        }
    }
}

/// The hint shown at the top of the screen after the first back press at the top.
struct ExitHint: View {
    var body: some View {
        Label("再按一次返回键退出", systemImage: "arrow.uturn.backward")
            .font(.headline)
            .padding(.horizontal, 36)
            .padding(.vertical, 18)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 50)
    }
}
