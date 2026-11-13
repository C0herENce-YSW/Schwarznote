//
//  SwipeMonitor.swift
//  Schwarznote
//
//  Reports up/down swipes on the remote's touch surface. SwiftUI's move commands only cover
//  clicks on the edges, so swipe recognizers go on the window, alongside the focus engine,
//  for as long as the view that owns this monitor is on screen.
//

import SwiftUI
import UIKit

struct SwipeMonitor: UIViewRepresentable {
    let onSwipe: (UISwipeGestureRecognizer.Direction) -> Void

    func makeUIView(context: Context) -> InstallerView {
        InstallerView()
    }

    func updateUIView(_ view: InstallerView, context: Context) {
        view.onSwipe = onSwipe
    }

    static func dismantleUIView(_ view: InstallerView, coordinator: ()) {
        view.uninstall()
    }

    final class InstallerView: UIView, UIGestureRecognizerDelegate {
        var onSwipe: ((UISwipeGestureRecognizer.Direction) -> Void)?
        private var recognizers: [UISwipeGestureRecognizer] = []

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            recognizers = [UISwipeGestureRecognizer.Direction.up, .down].map { direction in
                let recognizer = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
                recognizer.direction = direction
                recognizer.cancelsTouchesInView = false
                recognizer.delegate = self
                return recognizer
            }
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            uninstall()
            if let window {
                recognizers.forEach(window.addGestureRecognizer)
            }
        }

        func uninstall() {
            for recognizer in recognizers {
                recognizer.view?.removeGestureRecognizer(recognizer)
            }
        }

        @objc private func swiped(_ recognizer: UISwipeGestureRecognizer) {
            onSwipe?(recognizer.direction)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
