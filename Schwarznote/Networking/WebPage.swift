//
//  WebPage.swift
//  Schwarznote
//

import Foundation
import ObjectiveC
import UIKit

// tvOS ships WebKit, but its SDK doesn't publish it to apps. The classes are looked up at run
// time and called through these declarations of the few methods the app uses. This is private
// to Apple's SDK, so the app can't go through App Store review.

@objc private protocol WebViewAPI: NSObjectProtocol {
    @objc(loadRequest:) func load(_ request: URLRequest) -> AnyObject?
    @objc(evaluateJavaScript:completionHandler:)
    func evaluateJavaScript(_ script: String, completionHandler: ((Any?, Error?) -> Void)?)
    @objc(callAsyncJavaScript:arguments:inFrame:inContentWorld:completionHandler:)
    func callAsyncJavaScript(_ functionBody: String, arguments: [String: Any]?, inFrame frame: AnyObject?,
                             inContentWorld world: AnyObject, completionHandler: ((Any?, Error?) -> Void)?)
    @objc var customUserAgent: String? { get set }
    @objc(URL) var pageURL: URL? { get }
}

@objc private protocol DataStoreAPI: NSObjectProtocol {
    @objc var httpCookieStore: AnyObject { get }
}

@objc private protocol CookieStoreAPI: NSObjectProtocol {
    @objc(getAllCookies:) func getAllCookies(_ completion: @escaping ([HTTPCookie]) -> Void)
    @objc(setCookie:completionHandler:) func setCookie(_ cookie: HTTPCookie, completionHandler: (() -> Void)?)
    @objc(deleteCookie:completionHandler:) func deleteCookie(_ cookie: HTTPCookie, completionHandler: (() -> Void)?)
}

enum WebPageError: LocalizedError {
    case unavailable
    case notReady
    case script(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: "这台设备的系统里找不到网页引擎（WebKit），无法连接小红书。"
        case .notReady: "小红书网页加载超时，请检查网络后重试。"
        case .script(let message): "网页脚本出错：\(message)"
        }
    }
}

/// One hidden page of the site in tvOS's WebKit. Every page shares the same cookie store, so
/// the device cookies (`a1`, `webId`, …) and the login are the same in all of them.
@MainActor
final class WebPage {
    /// Sent by the pages and by the app's own requests, so the server sees one browser.
    /// WebKit is Safari's engine, so this is what it is.
    static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    private let view: UIView
    private let api: WebViewAPI

    private static let classes: (webView: UIView.Type, contentWorld: AnyObject)? = {
        guard dlopen("/System/Library/Frameworks/WebKit.framework/WebKit", RTLD_NOW) != nil,
              let webView = NSClassFromString("WKWebView") as? UIView.Type,
              let dataStore = NSClassFromString("WKWebsiteDataStore"),
              let cookieStore = NSClassFromString("WKHTTPCookieStore"),
              let world = NSClassFromString("WKContentWorld") as? NSObject.Type,
              let pageWorld = world.perform(NSSelectorFromString("pageWorld"))?.takeUnretainedValue()
        else { return nil }
        class_addProtocol(webView, WebViewAPI.self)
        class_addProtocol(dataStore, DataStoreAPI.self)
        class_addProtocol(cookieStore, CookieStoreAPI.self)
        return (webView, pageWorld)
    }()

    init() throws {
        guard let classes = Self.classes else { throw WebPageError.unavailable }
        // Desktop-sized, so the site lays out its desktop page (login dialog included).
        view = classes.webView.init(frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        api = view as! WebViewAPI
        api.customUserAgent = Self.userAgent
        view.isUserInteractionEnabled = false
        // Too faint to see, but not hidden, which would let WebKit pause the page.
        view.alpha = 0.001
        attach()
    }

    /// Keeps the page in the window, behind everything, so WebKit doesn't pause it as hidden.
    private func attach() {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first?.windows.first
        window?.insertSubview(view, at: 0)
    }

    func close() {
        view.removeFromSuperview()
    }

    var url: URL? { api.pageURL }

    func load(_ url: URL) {
        if view.superview == nil { attach() }
        _ = api.load(URLRequest(url: url))
    }

    func evaluate(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            api.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: WebPageError.script(error.localizedDescription))
                } else {
                    continuation.resume(returning: value)
                }
            }
        }
    }

    /// Runs `body` as the body of an async function in the page, with `arguments` as its locals.
    func callAsync(_ body: String, arguments: [String: Any]) async throws -> Any? {
        guard let world = Self.classes?.contentWorld else { throw WebPageError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            api.callAsyncJavaScript(body, arguments: arguments, inFrame: nil, inContentWorld: world) { value, error in
                if let error {
                    let message = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String
                    continuation.resume(throwing: WebPageError.script(message ?? error.localizedDescription))
                } else {
                    continuation.resume(returning: value)
                }
            }
        }
    }

    /// Waits until the site's scripts are up: its signing function is the last thing it sets.
    func waitUntilReady(timeout: Duration = .seconds(30)) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if (try? await evaluate("typeof window._webmsxyw === 'function'")) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(400))
        }
        throw WebPageError.notReady
    }

    /// The site's registrable domain the page ended up on, e.g. "rednote.com".
    var siteDomain: String? {
        url?.host()?.split(separator: ".").suffix(2).joined(separator: ".")
    }

    // MARK: - Cookies (shared by all pages)

    /// The default data store's cookies, which every page uses.
    private static let sharedCookieStore: CookieStoreAPI? = {
        guard classes != nil,
              let dataStoreClass = NSClassFromString("WKWebsiteDataStore") as? NSObject.Type,
              let dataStore = dataStoreClass.perform(NSSelectorFromString("defaultDataStore"))?
                  .takeUnretainedValue() as? DataStoreAPI
        else { return nil }
        return dataStore.httpCookieStore as? CookieStoreAPI
    }()

    private static func store() -> CookieStoreAPI? { sharedCookieStore }

    /// The pages' cookies for `domain` (e.g. "rednote.com") and its subdomains.
    static func cookies(for domain: String) async -> [HTTPCookie] {
        guard let store = store() else { return [] }
        let all = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        return all.filter {
            let host = $0.domain.hasPrefix(".") ? String($0.domain.dropFirst()) : $0.domain
            return host == domain || host.hasSuffix("." + domain)
        }
    }

    static func setCookies(_ cookies: [HTTPCookie]) async {
        guard let store = store() else { return }
        for cookie in cookies {
            await withCheckedContinuation { continuation in
                store.setCookie(cookie) { continuation.resume() }
            }
        }
    }

    static func deleteCookies(named name: String, for domain: String) async {
        guard let store = store() else { return }
        for cookie in await cookies(for: domain) where cookie.name == name {
            await withCheckedContinuation { continuation in
                store.deleteCookie(cookie) { continuation.resume() }
            }
        }
    }
}
