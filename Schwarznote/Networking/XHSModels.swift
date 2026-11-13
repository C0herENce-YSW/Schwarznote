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
/// Observed: 0 = waiting, 1 = scanned, 2 = confirmed on the phone,
/// 3 = code no longer valid ("二维码为空"); the app then creates a new code.
enum QRCodeStatus: Equatable, Sendable {
    case waitingForScan
    case scanned
    case confirmed
    case expired
    case unknown(Int)

    init(rawValue: Int) {
        switch rawValue {
        case 0: self = .waitingForScan
        case 1: self = .scanned
        case 2: self = .confirmed
        case 3: self = .expired
        default: self = .unknown(rawValue)
        }
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
