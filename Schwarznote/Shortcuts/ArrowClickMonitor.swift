//
//  ArrowClickMonitor.swift
//  Schwarznote
//
//  Takes left and right clicks on the remote's clickpad for the owning screen, so they don't
//  move focus. Swipes are touches, not presses, so they still reach the focus engine: the note
//  page uses clicks to change the picture and swipes to move around its right-hand column.
//

import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

struct ArrowClickMonitor: UIViewRepresentable {
    /// When false, clicks go to the focus engine as usual.
    var isEnabled = true
    let onClick: (_ step: Int) -> Void

    func makeUIView(context: Context) -> InstallerView {
        InstallerView()
    }

    func updateUIView(_ view: InstallerView, context: Context) {
        view.isMonitoring = isEnabled
        view.onClick = onClick
    }

    static func dismantleUIView(_ view: InstallerView, coordinator: ()) {
        view.uninstall()
    }

    final class InstallerView: UIView, UIGestureRecognizerDelegate {
        var isMonitoring = true
        var onClick: ((Int) -> Void)?
        private let recognizer = ArrowClickRecognizer()

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            recognizer.delegate = self
            recognizer.onClick = { [weak self] step in self?.onClick?(step) }
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            uninstall()
            window?.addGestureRecognizer(recognizer)
        }

        func uninstall() {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool {
            isMonitoring && isFrontmost
        }

        /// False while the screen holding this view has presented another one (keyboard, alert,
        /// full-screen photo) over itself.
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
    }
}

/// Recognizes as soon as a left or right click begins, which cancels the press for the
/// responder chain and with it the focus move.
private final class ArrowClickRecognizer: UIGestureRecognizer {
    var onClick: ((Int) -> Void)?

    init() {
        super.init(target: nil, action: nil)
        allowedPressTypes = [UIPress.PressType.leftArrow, .rightArrow].map { NSNumber(value: $0.rawValue) }
        allowedTouchTypes = []
        cancelsTouchesInView = true
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
        guard let press = presses.first(where: { $0.type == .leftArrow || $0.type == .rightArrow }) else {
            state = .failed
            return
        }
        onClick?(press.type == .rightArrow ? 1 : -1)
        state = .recognized
    }
}
