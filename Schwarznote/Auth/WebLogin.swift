//
//  WebLogin.swift
//  Schwarznote
//

import Foundation
import OSLog

/// The site's own QR login page, hidden. The TV shows the page's QR code;
/// when the phone confirms, the page logs in and its cookies carry the new session.
@MainActor
final class WebLogin {
    struct State {
        /// The page's QR code picture (PNG).
        var qrImage: Data?
        /// The dialog's scan state: 0 waiting, 1 scanned, 2 confirmed, 3 expired.
        var codeStatus: Int?
    }

    let region: XHSRegion
    private let page: WebPage

    init(region: XHSRegion) throws {
        self.region = region
        page = try WebPage()
    }

    func close() {
        page.close()
    }

    /// Loads the site's login page, which shows its QR code right away. Logs the pages out
    /// first, so it always asks for a fresh scan.
    func open() async throws {
        await WebPage.deleteCookies(named: SessionStore.sessionCookieName, for: region.siteDomain)
        page.load(URL(string: region.webOrigin + "/login")!)
        try await page.waitUntilReady()
        if let site = page.siteDomain, site != region.siteDomain { throw OtherSiteError(site: site) }
        _ = try await page.evaluate(Self.watchScript)

        let deadline = ContinuousClock.now + .seconds(20)
        while ContinuousClock.now < deadline {
            if await state().qrImage != nil { return }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw WebPageError.script("login page didn't show a QR code")
    }

    /// What the dialog shows now. Empty while the page reloads after the phone confirms.
    func state() async -> State {
        // Again each time: if the page reloaded itself, the watcher went with it.
        _ = try? await page.evaluate(Self.watchScript)
        let script = """
            JSON.stringify({img: document.querySelector('.qrcode-img')?.src || null,
                            code: window.__schwarznoteLogin?.code ?? null})
            """
        guard let value = try? await page.evaluate(script) as? String,
              let json = try? JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any]
        else { return State() }
        // The picture is a data URL: "data:image/png;base64,…".
        let image = (json["img"] as? String)
            .flatMap { src in src.range(of: "base64,").map { String(src[$0.upperBound...]) } }
            .flatMap { Data(base64Encoded: $0) }
        return State(qrImage: image, codeStatus: json["code"] as? Int)
    }

    /// Where the page is now, for the log.
    var pagePath: String { page.url.map { ($0.host() ?? "") + $0.path() } ?? "-" }

    /// The pages' session cookie, which changes when the login goes through.
    func sessionCookie() async -> String? {
        await WebPage.cookies(for: region.siteDomain).first { $0.name == SessionStore.sessionCookieName }?.value
    }

    /// Records the scan state the page polls for.
    private static let watchScript = """
        (() => {
          if (window.__schwarznoteLogin) return true;
          const state = window.__schwarznoteLogin = {};
          const open = XMLHttpRequest.prototype.open;
          const send = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open = function (method, url) {
            this.__schwarznoteURL = String(url);
            return open.apply(this, arguments);
          };
          XMLHttpRequest.prototype.send = function () {
            this.addEventListener("load", () => {
              const url = this.__schwarznoteURL || "";
              if (!url.includes("/qrcode/userinfo")) return;
              try {
                const data = (JSON.parse(this.responseText) || {}).data || {};
                if (data.codeStatus !== undefined) state.code = data.codeStatus;
              } catch (e) {}
            });
            return send.apply(this, arguments);
          };
          return true;
        })()
        """
}
