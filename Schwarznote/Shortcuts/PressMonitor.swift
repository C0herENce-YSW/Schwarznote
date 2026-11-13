//
//  PressMonitor.swift
//  Schwarznote
//
//  Watches every button press in the window without taking it away from the focused view:
//  a gesture recognizer on the window sees presses before they reach the focus engine, reports
//  them, and then fails so normal handling continues.
//

import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Put once in the view hierarchy (e.g. as a background) to install the monitor on its window.
struct PressMonitor: UIViewRepresentable {
    let center: ShortcutCenter

    func makeUIView(context: Context) -> InstallerView {
        InstallerView(center: center)
    }

    func updateUIView(_ view: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        private let recognizer = PressRecognizer()

        init(center: ShortcutCenter) {
            super.init(frame: .zero)
            recognizer.onPress = { [weak center] key in center?.handle(key) }
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            recognizer.view?.removeGestureRecognizer(recognizer)
            window?.addGestureRecognizer(recognizer)
        }
    }
}

private final class PressRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var onPress: ((ShortcutKey) -> Void)?

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delegate = self
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        for press in presses {
            if let key = ShortcutKey(press) { onPress?(key) }
        }
        state = .failed
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
