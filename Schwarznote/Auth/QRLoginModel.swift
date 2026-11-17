//
//  QRLoginModel.swift
//  Schwarznote
//

import Foundation
import OSLog
import Observation

/// How the login QR code is made.
enum LoginMethod: String, CaseIterable, Identifiable, Sendable {
    /// The site's own login dialog, in a hidden page.
    case web
    /// The app makes the web login calls itself.
    case api

    var id: String { rawValue }

    var title: String {
        switch self {
        case .web: "网页登录（推荐）"
        case .api: "接口登录"
        }
    }
}

/// Drives the QR login screen, by either method. Both end with the account logged in.
@Observable
final class QRLoginModel {
    /// What to draw as the QR code.
    enum Code: Equatable {
        /// A link the app draws as a QR code.
        case link(String)
        /// The login page's own QR code picture (PNG).
        case picture(Data)
    }

    enum Phase: Equatable {
        case loading
        case showing(Code, QRCodeStatus)
        case failed(String)
    }

    private(set) var phase: Phase = .loading

    /// Runs until login succeeds, fails, or the calling task is cancelled.
    func run(auth: AuthModel, method: LoginMethod) async {
        phase = .loading
        do {
            switch method {
            case .web: try await runWeb(auth: auth)
            case .api: try await runAPI(auth: auth)
            }
        } catch is CancellationError {
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Web page

    private static let log = Logger(subsystem: "com.seal-yue.Schwarznote", category: "login")

    /// Opens the site's login dialog in a hidden page, shows its code and follows its status.
    /// When the phone confirms, the page logs in and the app takes over its cookies.
    private func runWeb(auth: AuthModel) async throws {
        let login = try WebLogin(region: auth.region)
        defer { login.close() }
        try await login.open()
        var guestSession = await login.sessionCookie()
        let deadline = ContinuousClock.now + .seconds(600)
        var lastLog = ""
        var completionFailures = 0

        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .seconds(1))
            let state = await login.state()
            let session = await login.sessionCookie()
            // What the page shows, without any cookie values.
            let line = "page=\(login.pagePath) code=\(state.codeStatus.map(String.init) ?? "-") "
                + "qr=\(state.qrImage.map { String($0.hashValue, radix: 36) } ?? "-") "
                + "session=\(session == nil ? "none" : session == guestSession ? "guest" : "new")"
            if line != lastLog {
                Self.log.info("\(line, privacy: .public)")
                lastLog = line
            }
            if let image = state.qrImage {
                phase = .showing(.picture(image), QRCodeStatus(code: state.codeStatus ?? 0))
            }
            if state.codeStatus == 3 {
                // Expired: open the dialog again for a fresh code.
                phase = .loading
                try await login.open()
                guestSession = await login.sessionCookie()
                continue
            }
            // The page may skip straight past "confirmed" and reload, so watch for the new session.
            if let session, session != guestSession {
                do {
                    try await auth.completeWebLogin()
                    return
                } catch WebLoginError.noSession {
                    // Just a new guest session: keep waiting for the scan.
                    guestSession = session
                } catch {
                    // Logged in on the page, but the app couldn't take it over: say why instead
                    // of waiting on a page that has already moved on.
                    completionFailures += 1
                    Self.log.error("taking over the login failed: \(error.localizedDescription, privacy: .public)")
                    if completionFailures >= 3 { throw error }
                }
            }
        }
        throw WebLoginError.failed("登录超时，请重试")
    }

    // MARK: - App's own calls

    /// The web client refreshes its QR code after about two minutes.
    private let ticketLifetime: Duration = .seconds(120)

    private func runAPI(auth: AuthModel) async throws {
        while true {
            phase = .loading
            let ticket = try await auth.client.createQRCode()
            let deadline = ContinuousClock.now + ticketLifetime
            var status = QRCodeStatus.waitingForScan
            phase = .showing(.link(ticket.url), status)

            while ContinuousClock.now < deadline {
                try await Task.sleep(for: .seconds(2))
                status = try await auth.client.qrCodeStatus(for: ticket)
                phase = .showing(.link(ticket.url), status)

                if status == .confirmed {
                    do {
                        try await auth.client.completeQRLogin(for: ticket)
                    } catch {
                        throw WebLoginError.failed("手机已确认，但服务器拒绝登录：\(error.localizedDescription)")
                    }
                    if await auth.completeAPILogin() { return }
                    throw WebLoginError.failed("手机已确认，但服务器没有下发登录凭证")
                }
                if status == .expired { break }
            }
            // Expired: loop around and make a fresh code.
        }
    }
}
