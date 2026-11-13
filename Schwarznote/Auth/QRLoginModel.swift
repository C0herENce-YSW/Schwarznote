//
//  QRLoginModel.swift
//  Schwarznote
//

import Foundation
import Observation

/// Drives the QR login screen: create a code, poll its status, refresh it when it expires.
@Observable
final class QRLoginModel {
    enum Phase: Equatable {
        case loading
        case showing(QRCodeTicket, QRCodeStatus)
        case failed(String)
    }

    private(set) var phase: Phase = .loading

    private let pollInterval: Duration = .seconds(2)
    /// The web client refreshes its QR code after about two minutes.
    private let ticketLifetime: Duration = .seconds(120)

    /// Runs until login succeeds or the calling task is cancelled.
    func run(auth: AuthModel) async {
        while !Task.isCancelled {
            phase = .loading
            let ticket: QRCodeTicket
            do {
                ticket = try await auth.client.createQRCode()
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }

            let deadline = ContinuousClock.now + ticketLifetime
            var status = QRCodeStatus.waitingForScan
            phase = .showing(ticket, status)

            while !Task.isCancelled, ContinuousClock.now < deadline {
                try? await Task.sleep(for: pollInterval)
                do {
                    status = try await auth.client.qrCodeStatus(for: ticket)
                } catch {
                    phase = .failed(error.localizedDescription)
                    return
                }
                phase = .showing(ticket, status)

                // Observed: 0 = waiting, 1 = scanned, 2 = confirmed on the phone.
                if status == .confirmed {
                    do {
                        try await auth.client.completeQRLogin(for: ticket)
                    } catch {
                        phase = .failed("手机已确认，但服务器拒绝登录：\(error.localizedDescription)")
                        return
                    }
                    if await auth.completeLogin() { return }
                    phase = .failed("手机已确认，但服务器没有下发登录凭证")
                    return
                }
                if await auth.completeLogin() { return }
                if status == .expired { break }
            }
            // Expired: loop around and create a fresh code.
        }
    }
}
