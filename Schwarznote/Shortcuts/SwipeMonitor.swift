//
//  SwipeMonitor.swift
//  Schwarznote
//
//  Reports swipes on the remote's touch surface. SwiftUI's move commands only cover clicks on
//  the edges, so swipe recognizers go on the window, alongside the focus engine, for as long as
//  the view that owns this monitor is on screen. Swipes are ignored while another screen is
//  presented on top of the owner, so stacked full-screen pages don't all react at once.
//

import SwiftUI
import UIKit

struct SwipeMonitor: UIViewRepresentable {
    var directions: [UISwipeGestureRecognizer.Direction] = [.up, .down]
    let onSwipe: (UISwipeGestureRecognizer.Direction) -> Void

    func makeUIView(context: Context) -> InstallerView {
        InstallerView(directions: directions)
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

        init(directions: [UISwipeGestureRecognizer.Direction]) {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            recognizers = directions.map { direction in
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
            guard isFrontmost else { return }
            onSwipe?(recognizer.direction)
        }

        /// False while the screen holding this view has presented another one over itself.
        private var isFrontmost: Bool {
            var responder: UIResponder? = self
            while let current = responder, !(current is UIViewController) { responder = current.next }
            var controller = responder as? UIViewController
            while let current = controller {
                if current.presentedViewController != nil { return false }
                controller = current.parent
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
