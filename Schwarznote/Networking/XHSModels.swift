//
//  XHSModels.swift
//  Schwarznote
//

import Foundation

/// Common envelope: `{"code":0,"success":true,"msg":"成功","data":{...}}`
nonisolated struct XHSResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let code: Int
    let success: Bool
    let msg: String?
    let data: T?
}

/// `POST /api/sns/web/v1/login/qrcode/create` → data
nonisolated struct QRCodeTicket: Decodable, Sendable, Equatable {
    let qrId: String
    let code: String
    /// The URL encoded into the QR code; the phone app opens it when scanned.
    let url: String

    enum CodingKeys: String, CodingKey {
        case qrId = "qr_id"
        case code
        case url
    }
}

/// `POST /api/qrcode/userinfo` → data
nonisolated struct QRCodeStatusPayload: Decodable, Sendable {
    let codeStatus: Int?
}

/// Scan state shown on screen.
///
/// Observed codes: 0 = waiting, 1 = scanned, 2 = confirmed on the phone,
/// 3 = code no longer valid ("二维码为空"); a new code is then made.
enum QRCodeStatus: Equatable, Sendable {
    case waitingForScan
    case scanned
    case confirmed
    /// The page is replacing an expired code.
    case expired
    case unknown(String)

    /// From the API's `codeStatus`.
    init(code: Int) {
        switch code {
        case 0: self = .waitingForScan
        case 1: self = .scanned
        case 2: self = .confirmed
        case 3: self = .expired
        default: self = .unknown(String(code))
        }
    }

    /// From the signer's web login status.
    init(_ status: String) {
        switch status {
        case "waiting": self = .waitingForScan
        case "scanned": self = .scanned
        case "confirmed": self = .confirmed
        case "expired", "loading": self = .expired
        default: self = .unknown(status)
        }
    }
}

/// `POST /api/sns/web/v1/homefeed` → data
nonisolated struct HomefeedPayload: Decodable, Sendable {
    let cursor: String
    let notes: [Note]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        cursor = c.string("cursor_score") ?? ""
        notes = c.value(LossyArray<Note>.self, "items")?.elements ?? []
    }
}

/// `GET /api/sns/web/v2/user/me` → data (only the fields we use).
nonisolated struct XHSUser: Decodable, Sendable, Equatable {
    let userId: String?
    let nickname: String?
    let avatarURL: String?
    let guest: Bool?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case nickname
        case avatarURL = "images"
        case guest
    }
}
