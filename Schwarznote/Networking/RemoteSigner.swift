//
//  RemoteSigner.swift
//  Schwarznote
//

import Foundation

enum RemoteSignerError: LocalizedError {
    case unreachable(String)
    case badResponse(Int, String)

    var errorDescription: String? {
        switch self {
        case .unreachable(let detail):
            "连不上签名服务：\(detail)。请确认 Mac 上的 signer 已启动，地址填写正确。"
        case .badResponse(let status, let message):
            "签名服务出错（\(status)）：\(message)"
        }
    }
}

/// Gets signatures from the signing service in `signer/` running on a Mac.
///
/// The signature is bound to the signing browser's device cookies (`a1`, `webId`, …) and
/// User-Agent, so those are copied into this app's cookie storage and request headers.
struct RemoteSigner: RequestSigner {
    let baseURL: URL
    let token: String?

    private nonisolated struct SignResponse: Decodable, Sendable {
        let headers: [String: String]
        let cookies: [String: String]
        let userAgent: String
    }

    private nonisolated struct ErrorResponse: Decodable, Sendable {
        let error: String
    }

    func signatureHeaders(region: XHSRegion, path: String, body: Data?) async throws -> [String: String] {
        var request = URLRequest(url: baseURL.appending(path: "sign"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // Embed the body bytes as-is so the page signs exactly what will be sent
        // (re-encoding could reorder keys and break the signature).
        let pathJSON = String(decoding: try JSONSerialization.data(withJSONObject: path, options: [.fragmentsAllowed, .withoutEscapingSlashes]), as: UTF8.self)
        let bodyJSON = body.map { String(decoding: $0, as: UTF8.self) } ?? "null"
        request.httpBody = Data(#"{"region":"\#(region.rawValue)","path":\#(pathJSON),"body":\#(bodyJSON)}"#.utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw RemoteSignerError.unreachable(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error ?? "HTTP \(status)"
            throw RemoteSignerError.badResponse(status, message)
        }
        let signed = try JSONDecoder().decode(SignResponse.self, from: data)

        let domain = "." + (region.apiBaseURL.host() ?? "").split(separator: ".").suffix(2).joined(separator: ".")
        for (name, value) in signed.cookies {
            if let cookie = HTTPCookie(properties: [
                .name: name, .value: value, .domain: domain, .path: "/",
                .secure: "TRUE", .expires: Date().addingTimeInterval(365 * 24 * 3600),
            ]) {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }

        var headers = signed.headers
        headers["User-Agent"] = signed.userAgent
        return headers
    }
}
