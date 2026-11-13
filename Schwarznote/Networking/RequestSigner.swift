//
//  RequestSigner.swift
//  Schwarznote
//

import Foundation

/// Adds the signature headers (`X-s`, `X-t`, …) that the web API requires.
///
/// The app talks to the API only through this protocol, so the signing source can be
/// swapped without touching the rest of the networking code.
protocol RequestSigner: Sendable {
    /// - Parameters:
    ///   - region: Which site the request goes to.
    ///   - path: API path including the query string, e.g. `/api/sns/web/v1/login/qrcode/create`.
    ///   - body: The exact JSON bytes that will be sent, or `nil` for GET requests.
    /// - Returns: Headers to add to the request (may include `User-Agent`).
    func signatureHeaders(region: XHSRegion, path: String, body: Data?) async throws -> [String: String]
}

/// Sends requests unsigned. The server answers these with HTTP 406,
/// which the client reports as `XHSError.signatureRequired`.
struct UnsignedSigner: RequestSigner {
    func signatureHeaders(region: XHSRegion, path: String, body: Data?) async throws -> [String: String] {
        [:]
    }
}
