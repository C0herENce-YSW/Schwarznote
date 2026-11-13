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

    var region: XHSRegion {
        didSet {
            guard region != oldValue else { return }
            UserDefaults.standard.set(region.rawValue, forKey: Self.regionKey)
            rebuildClient()
        }
    }

    /// Address of the signing service from `signer/`, e.g. `http://192.168.1.10:8790`.
    var signerURL: String {
        didSet {
            guard signerURL != oldValue else { return }
            UserDefaults.standard.set(signerURL, forKey: Self.signerURLKey)
            rebuildClient()
        }
    }

    /// Optional shared secret matching `SIGNER_TOKEN` on the Mac.
    var signerToken: String {
        didSet {
            guard signerToken != oldValue else { return }
            UserDefaults.standard.set(signerToken, forKey: Self.signerTokenKey)
            rebuildClient()
        }
    }

    private let store = SessionStore()
    private static let regionKey = "region"
    private static let signerURLKey = "signerURL"
    private static let signerTokenKey = "signerToken"

    init() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: Self.regionKey).flatMap(XHSRegion.init(rawValue:))
        let region = saved ?? (Locale.current.region?.identifier == "CN" ? .china : .international)
        let signerURL = defaults.string(forKey: Self.signerURLKey) ?? "http://localhost:8790"
        let signerToken = defaults.string(forKey: Self.signerTokenKey) ?? ""
        self.region = region
        self.signerURL = signerURL
        self.signerToken = signerToken
        self.client = XHSClient(region: region, signer: Self.makeSigner(url: signerURL, token: signerToken))
    }

    private static func makeSigner(url: String, token: String) -> RequestSigner {
        guard let base = URL(string: url.trimmingCharacters(in: .whitespaces)), base.host() != nil else {
            return UnsignedSigner()
        }
        return RemoteSigner(baseURL: base, token: token.isEmpty ? nil : token)
    }

    private func rebuildClient() {
        client = XHSClient(region: region, signer: Self.makeSigner(url: signerURL, token: signerToken))
    }

    /// Restores saved cookies and checks whether the session is still valid.
    func restore() async {
        let saved = store.load()
        guard saved.contains(where: { $0.name == SessionStore.sessionCookieName }) else {
            state = .loggedOut
            return
        }
        saved.forEach { HTTPCookieStorage.shared.setCookie($0) }
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

    /// Call after the QR flow reports success. Returns false if no session cookie arrived.
    @discardableResult
    func completeLogin() async -> Bool {
        let cookies = client.cookies
        guard cookies.contains(where: { $0.name == SessionStore.sessionCookieName }) else { return false }
        store.save(cookies)
        let user = try? await client.currentUser()
        state = .loggedIn(user)
        return true
    }

    func logOut() {
        store.clear()
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        state = .loggedOut
    }
}
