//
//  WebSigner.swift
//  Schwarznote
//

import Foundation

/// The site's page couldn't be used for `region`: it ended up on another site, as
/// xiaohongshu.com does (→ rednote.com) on a network outside mainland China.
struct OtherSiteError: LocalizedError {
    let site: String

    var errorDescription: String? {
        let region = XHSRegion.allCases.first { $0.siteDomain == site }
        return "这台设备的网络不在中国大陆，打开小红书时被跳转到了 \(site)。"
            + "请在“我”页面把地区切换到\(region?.displayName ?? site)（国内账号也可以在那里登录）。"
    }
}

/// Signs requests with the site's own code, in a hidden page of the site.
///
/// For each request, the page's HTTP client builds it, so the site's interceptors add every
/// header they normally add (X-s, X-t, X-S-Common, trace ids); the headers are recorded and the
/// request is aborted before anything is sent. Nothing is reimplemented or de-obfuscated.
/// The signature is bound to the page's device cookies (`a1`, …), which are copied to the app.
@MainActor
final class WebSigner: RequestSigner {
    static let shared = WebSigner()

    private var page: WebPage?
    private var pageRegion: XHSRegion?
    /// Signing patches the page's XMLHttpRequest for a moment, so requests are signed one at a time.
    private var queue: Task<Void, Never>?

    /// Device cookies the signature depends on.
    private static let deviceCookies: Set<String> = ["a1", "webId", "gid", "websectiga", "sec_poison_id", "xsecappid"]
    /// The app sets these itself.
    private static let skippedHeaders: Set<String> = ["accept", "content-type"]

    func sign(region: XHSRegion, path: String, body: Data?) async throws -> Signature {
        let previous = queue
        let task = Task { () -> Result<Signature, Error> in
            await previous?.value
            do { return .success(try await signNow(region: region, path: path, body: body)) }
            catch { return .failure(error) }
        }
        queue = Task { _ = await task.value }
        return try await task.value.get()
    }

    /// Loads the site's page for `region` if it isn't up yet.
    func prepare(region: XHSRegion) async throws -> WebPage {
        if let page, pageRegion == region { return page }
        page?.close()
        page = nil
        let fresh = try WebPage()
        fresh.load(URL(string: region.webOrigin + "/explore")!)
        do {
            try await fresh.waitUntilReady()
        } catch {
            fresh.close()
            throw error
        }
        if let site = fresh.siteDomain, site != region.siteDomain {
            fresh.close()
            throw OtherSiteError(site: site)
        }
        page = fresh
        pageRegion = region
        return fresh
    }

    private func signNow(region: XHSRegion, path: String, body: Data?) async throws -> Signature {
        var attempt = 0
        while true {
            let page = try await prepare(region: region)
            do {
                let result = try await page.callAsync(Self.captureScript, arguments: [
                    "method": body == nil ? "GET" : "POST",
                    "path": path,
                    // Passed as text and parsed in the page, so the keys keep the order the app sends.
                    "bodyJSON": body.map { String(decoding: $0, as: UTF8.self) } ?? NSNull(),
                ]) as? [String: Any]
                guard let url = result?["url"] as? String,
                      let headers = result?["headers"] as? [String: String]
                else { throw WebPageError.script("no headers") }

                // The device cookies always; the page's session only while the app has none, so a
                // logged-out app browses as the page's guest.
                let appHasSession = (HTTPCookieStorage.shared.cookies(for: region.apiBaseURL) ?? [])
                    .contains { $0.name == SessionStore.sessionCookieName }
                for cookie in await WebPage.cookies(for: region.siteDomain)
                where Self.deviceCookies.contains(cookie.name)
                    || (cookie.name == SessionStore.sessionCookieName && !appHasSession) {
                    HTTPCookieStorage.shared.setCookie(cookie)
                }
                let signed = URLComponents(string: url)
                let signedPath = signed.map { $0.percentEncodedPath + ($0.percentEncodedQuery.map { "?" + $0 } ?? "") }
                return Signature(
                    headers: headers.filter { !Self.skippedHeaders.contains($0.key.lowercased()) },
                    path: signedPath?.isEmpty == false ? signedPath! : path
                )
            } catch {
                // The site's modules can still be loading just after the page reports ready, or
                // the page navigated away: give it a moment, then start over with a fresh page.
                attempt += 1
                guard attempt < 4 else { throw error }
                if attempt == 3 {
                    self.page?.close()
                    self.page = nil
                }
                try await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Sends the request through the site's own HTTP client, records the headers its
    /// interceptors add, and aborts it before anything leaves.
    private static let captureScript = """
        const body = bodyJSON === null ? null : JSON.parse(bodyJSON);

        // Sends one request through `http`, records its URL and headers, and aborts it.
        const capture = async (http) => {
          const proto = XMLHttpRequest.prototype;
          const original = { open: proto.open, setRequestHeader: proto.setRequestHeader, send: proto.send };
          const restore = () => Object.assign(proto, original);
          try {
            return await new Promise((resolve, reject) => {
              const timer = setTimeout(() => reject(new Error("timed out waiting for the request")), 10000);
              proto.open = function (m, url) {
                this.__signerURL = String(url);
                return original.open.apply(this, arguments);
              };
              proto.setRequestHeader = function (key, value) {
                (this.__signerHeaders ||= {})[key] = String(value);
                return original.setRequestHeader.apply(this, arguments);
              };
              proto.send = function () {
                clearTimeout(timer);
                restore();
                resolve({ url: this.__signerURL, headers: this.__signerHeaders || {} });
                this.abort();
              };
              const request = method === "GET" ? http.get(path) : http.post(path, body);
              if (request && request.catch) request.catch(() => {});
            });
          } finally {
            restore();
          }
        };
        const signed = (result) => Object.keys(result.headers).some((k) => k.toLowerCase() === "x-s");

        if (window.__signerHttp) return await capture(window.__signerHttp);

        // Find the site's own HTTP client: the one whose requests come out signed. Its export
        // name changes between builds (`LV` on rednote.com, another on xiaohongshu.com).
        const chunk = Object.keys(window).find((k) => k.startsWith("webpackChunk"));
        if (!chunk) throw new Error("site modules not loaded");
        let require;
        window[chunk].push([[Symbol("signer")], {}, (r) => { require = r; }]);
        const candidates = new Set();
        for (const m of Object.values(require.c)) {
          const e = m && m.exports;
          if (!e || e === window) continue;
          let values = [e];
          try { values = values.concat(Object.keys(e).map((k) => e[k])); } catch (err) {}
          for (const v of values) {
            if (v && v !== window && typeof v.post === "function" && typeof v.get === "function" && v.interceptors) {
              candidates.add(v);
            }
          }
        }
        for (const http of candidates) {
          let result;
          try { result = await capture(http); } catch (err) { continue; }
          if (signed(result)) {
            window.__signerHttp = http;
            return result;
          }
        }
        throw new Error("site HTTP client not found on " + location.host + location.pathname
          + " (" + candidates.size + " candidates)");
        """
}
