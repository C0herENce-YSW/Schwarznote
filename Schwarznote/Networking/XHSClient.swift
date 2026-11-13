//
//  XHSClient.swift
//  Schwarznote
//

import Foundation

enum XHSError: LocalizedError, Equatable {
    /// HTTP 406: the request was missing a valid signature.
    case signatureRequired
    case http(Int)
    case api(code: Int, message: String?)
    case emptyData
    case notLoggedIn

    var errorDescription: String? {
        switch self {
        case .signatureRequired:
            "服务器拒绝了请求（HTTP 406）：缺少有效的请求签名。请先配置签名来源。"
        case .http(let status):
            "网络请求失败（HTTP \(status)）"
        case .api(let code, let message):
            "接口返回错误 \(code)：\(message ?? "未知错误")"
        case .emptyData:
            "接口没有返回数据"
        case .notLoggedIn:
            "登录已失效，请重新扫码"
        }
    }
}

/// Thin client for the Xiaohongshu / rednote web API.
final class XHSClient {
    let region: XHSRegion
    private let signer: RequestSigner
    private let session: URLSession
    private let cookieStorage: HTTPCookieStorage

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    init(region: XHSRegion, signer: RequestSigner, cookieStorage: HTTPCookieStorage = .shared) {
        self.region = region
        self.signer = signer
        self.cookieStorage = cookieStorage
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = cookieStorage
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        self.session = URLSession(configuration: config)
    }

    var cookies: [HTTPCookie] {
        cookieStorage.cookies(for: region.apiBaseURL) ?? []
    }

    // MARK: - Login

    func createQRCode() async throws -> QRCodeTicket {
        try await post("/api/sns/web/v1/login/qrcode/create", body: ["qr_type": 1])
    }

    func qrCodeStatus(for ticket: QRCodeTicket) async throws -> QRCodeStatus {
        let payload: QRCodeStatusPayload = try await post(
            "/api/qrcode/userinfo",
            body: ["qrId": ticket.qrId, "code": ticket.code]
        )
        return QRCodeStatus(rawValue: payload.codeStatus ?? 0)
    }

    func currentUser() async throws -> XHSUser {
        try await get("/api/sns/web/v2/user/me")
    }

    // MARK: - Requests

    private func get<T: Decodable & Sendable>(_ path: String) async throws -> T {
        var request = makeRequest(path: path)
        request.httpMethod = "GET"
        return try await send(request, path: path, body: nil)
    }

    private func post<T: Decodable & Sendable>(_ path: String, body: [String: Any]) async throws -> T {
        // Compact JSON with no spaces: the signature covers the exact body bytes.
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
        var request = makeRequest(path: path)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json;charset=utf-8", forHTTPHeaderField: "Content-Type")
        return try await send(request, path: path, body: data)
    }

    private func makeRequest(path: String) -> URLRequest {
        var request = URLRequest(url: URL(string: path, relativeTo: region.apiBaseURL)!)
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(region.webOrigin, forHTTPHeaderField: "Origin")
        request.setValue(region.webOrigin + "/", forHTTPHeaderField: "Referer")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        return request
    }

    private func send<T: Decodable & Sendable>(_ request: URLRequest, path: String, body: Data?) async throws -> T {
        var request = request
        let headers = try await signer.signatureHeaders(region: region, path: path, body: body)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: break
        case 406: throw XHSError.signatureRequired
        case 401: throw XHSError.notLoggedIn
        default: throw XHSError.http(status)
        }

        let envelope = try JSONDecoder().decode(XHSResponse<T>.self, from: data)
        guard envelope.success else {
            throw XHSError.api(code: envelope.code, message: envelope.msg)
        }
        guard let payload = envelope.data else { throw XHSError.emptyData }
        return payload
    }
}
