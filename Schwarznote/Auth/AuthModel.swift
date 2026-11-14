//
//  AuthModel.swift
//  Schwarznote
//

import Foundation
import Observation

/// Owns the API client and the login state for the whole app.
@Observable
final class AuthModel {
    enum State: Equatable {
        case restoring
        case loggedOut
        case loggedIn(XHSUser?)
    }

    private(set) var state: State = .restoring
    private(set) var client: XHSClient

    var isLoggedIn: Bool {
        if case .loggedIn = state { true } else { false }
    }

    /// The signed-in account, when its profile has loaded.
    var currentUser: XHSUser? {
        if case .loggedIn(let user) = state { user } else { nil }
    }

    /// Changes whenever content should be reloaded: new client (region or signer) or login state.
    /// `nil` while the saved session is still being restored.
    var contentKey: String? {
        state == .restoring ? nil : "\(ObjectIdentifier(client).hashValue)-\(isLoggedIn)"
    }

    var region: XHSRegion {
        didSet {
            guard region != oldValue else { return }
            UserDefaults.standard.set(region.rawValue, forKey: Self.regionKey)
            rebuildClient()
        }
    }

    private let store = SessionStore()
    private static let regionKey = "region"

    init() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: Self.regionKey).flatMap(XHSRegion.init(rawValue:))
        let region = saved ?? (Locale.current.region?.identifier == "CN" ? .china : .international)
        self.region = region
        self.client = XHSClient(region: region, signer: WebSigner.shared)
    }

    private func rebuildClient() {
        client = XHSClient(region: region, signer: WebSigner.shared)
    }

    /// Restores saved cookies and checks whether the session is still valid.
    func restore() async {
        let saved = store.load()
        guard saved.contains(where: { $0.name == SessionStore.sessionCookieName }) else {
            state = .loggedOut
            return
        }
        saved.forEach { HTTPCookieStorage.shared.setCookie($0) }
        // The pages too, before they load, so they keep the device cookies the session belongs to.
        await WebPage.setCookies(saved)
        do {
            let user = try await client.currentUser()
            state = user.guest == true ? .loggedOut : .loggedIn(user)
        } catch XHSError.notLoggedIn {
            logOut()
        } catch {
            // Offline or signing not set up yet: keep the saved session instead of discarding it.
            state = .loggedIn(nil)
        }
    }

    /// For the app's own QR login: call after the phone confirms. Returns false if no logged-in
    /// session arrived.
    func completeAPILogin() async -> Bool {
        let cookies = client.cookies
        guard cookies.contains(where: { $0.name == SessionStore.sessionCookieName }) else { return false }
        let user = try? await client.currentUser()
        if user?.guest == true { return false }
        store.save(cookies)
        await WebPage.setCookies(cookies)
        state = .loggedIn(user)
        return true
    }

    /// Takes over the login the hidden login page just finished: its cookies become the app's.
    func completeWebLogin() async throws {
        let cookies = await WebPage.cookies(for: region.siteDomain)
        guard cookies.contains(where: { $0.name == SessionStore.sessionCookieName }) else {
            throw WebLoginError.noSession
        }
        cookies.forEach { HTTPCookieStorage.shared.setCookie($0) }
        let user: XHSUser
        do {
            user = try await client.currentUser()
            guard user.guest != true else { throw WebLoginError.noSession }
        } catch {
            client.cookies.filter { $0.name == SessionStore.sessionCookieName }
                .forEach { HTTPCookieStorage.shared.deleteCookie($0) }
            throw error
        }
        store.save(client.cookies)
        state = .loggedIn(user)
    }

    func logOut() {
        store.clear()
        let domain = region.siteDomain
        Task { await WebPage.deleteCookies(named: SessionStore.sessionCookieName, for: domain) }
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        state = .loggedOut
    }
}

enum WebLoginError: LocalizedError {
    case noSession
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noSession: "手机已确认，但没有拿到登录凭证，请重试。"
        case .failed(let message): "网页登录出错：\(message)"
        }
    }
}
