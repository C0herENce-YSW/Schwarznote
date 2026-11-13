//
//  SessionStore.swift
//  Schwarznote
//

import Foundation
import Security

/// Persists the login cookies (notably `web_session`) in the Keychain.
///
/// tvOS can purge an app's caches at any time, so HTTPCookieStorage alone is not a
/// reliable place to keep a login across launches.
struct SessionStore {
    private let service = "com.seal-yue.Schwarznote.session"
    private let account = "cookies"

    /// Name of the cookie that marks a logged-in web session.
    static let sessionCookieName = "web_session"

    func save(_ cookies: [HTTPCookie]) {
        let properties = cookies.compactMap { cookie -> [String: Any]? in
            guard let props = cookie.properties else { return nil }
            // Keep only plist-friendly values.
            return props.reduce(into: [String: Any]()) { result, pair in
                switch pair.value {
                case let date as Date: result[pair.key.rawValue] = date
                case let string as String: result[pair.key.rawValue] = string
                case let number as NSNumber: result[pair.key.rawValue] = number
                case let url as URL: result[pair.key.rawValue] = url.absoluteString
                default: break
                }
            }
        }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: properties, format: .binary, options: 0) else {
            return
        }
        clear()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func load() -> [HTTPCookie] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]]
        else { return [] }

        return list.compactMap { dict in
            let props = Dictionary(uniqueKeysWithValues: dict.map { (HTTPCookiePropertyKey($0.key), $0.value) })
            return HTTPCookie(properties: props)
        }
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
