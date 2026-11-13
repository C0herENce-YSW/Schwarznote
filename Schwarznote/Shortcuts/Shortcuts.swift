//
//  Shortcuts.swift
//  Schwarznote
//

import Foundation
import Observation
import UIKit

enum ShortcutAction: String, CaseIterable, Identifiable, Codable {
    case backToTop, like, collect, comment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .backToTop: "返回顶部"
        case .like: "点赞"
        case .collect: "收藏"
        case .comment: "评论"
        }
    }

    /// 返回顶部 always uses the back button; see BackButton.swift.
    var isEditable: Bool { self != .backToTop }
}

/// A button the app can receive: a remote button that isn't used for navigation, or a keyboard key.
struct ShortcutKey: Codable, Hashable {
    /// `UIPress.PressType` raw value, or 10_000 + HID usage for keyboard keys.
    let code: Int
    let name: String

    static let playPause = ShortcutKey(code: UIPress.PressType.playPause.rawValue, name: "播放/暂停")

    private init(code: Int, name: String) {
        self.code = code
        self.name = name
    }

    /// nil for navigation buttons (arrows, select, back), which stay with the focus engine.
    init?(_ press: UIPress) {
        if let key = press.key {
            guard !Self.navigationKeys.contains(key.keyCode) else { return nil }
            let characters = key.charactersIgnoringModifiers
            let name = switch key.keyCode {
            case .keyboardSpacebar: "空格"
            case .keyboardDeleteOrBackspace: "删除"
            default: characters.isEmpty ? "按键 \(key.keyCode.rawValue)" : characters.uppercased()
            }
            self.init(code: 10_000 + key.keyCode.rawValue, name: "键盘 \(name)")
            return
        }
        switch press.type {
        case .playPause: self = .playPause
        case .pageUp: self.init(code: press.type.rawValue, name: "上一页键")
        case .pageDown: self.init(code: press.type.rawValue, name: "下一页键")
        case .tvRemoteOneTwoThree: self.init(code: press.type.rawValue, name: "123 键")
        case .tvRemoteFourColors: self.init(code: press.type.rawValue, name: "彩色键")
        default: return nil
        }
    }

    private static let navigationKeys: Set<UIKeyboardHIDUsage> = [
        .keyboardUpArrow, .keyboardDownArrow, .keyboardLeftArrow, .keyboardRightArrow,
        .keyboardReturnOrEnter, .keypadEnter, .keyboardEscape, .keyboardTab,
    ]
}

/// Key bindings, the press router, and the "press a key to assign it" mode.
@Observable
final class ShortcutCenter {
    private(set) var bindings: [ShortcutAction: ShortcutKey]
    /// Set while Settings waits for the user to press the new key for this action.
    var recording: ShortcutAction?
    /// Paused while something else owns the media keys, e.g. the full-screen video player.
    var isPaused = false
    /// Installed by the screen that can act on shortcuts (the note detail).
    @ObservationIgnored var handler: ((ShortcutAction) -> Void)?

    static let defaults: [ShortcutAction: ShortcutKey] = [.like: .playPause]
    private static let storageKey = "shortcutBindings"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([ShortcutAction: ShortcutKey].self, from: data) {
            bindings = saved
        } else {
            bindings = Self.defaults
        }
    }

    func assign(_ key: ShortcutKey, to action: ShortcutAction) {
        // One key, one action: take it away from whatever had it.
        for (other, bound) in bindings where bound == key { bindings[other] = nil }
        bindings[action] = key
        save()
    }

    func clear(_ action: ShortcutAction) {
        bindings[action] = nil
        save()
    }

    func resetToDefaults() {
        bindings = Self.defaults
        save()
    }

    /// Called by the press monitor for every non-navigation press.
    func handle(_ key: ShortcutKey) {
        if let action = recording {
            assign(key, to: action)
            recording = nil
        } else if !isPaused, let action = bindings.first(where: { $0.value == key })?.key {
            handler?(action)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(bindings) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
