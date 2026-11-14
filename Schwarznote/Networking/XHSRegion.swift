//
//  XHSRegion.swift
//  Schwarznote
//

import Foundation

/// Mainland China uses xiaohongshu.com; outside China the web app redirects to rednote.com.
/// The API paths are the same on both.
enum XHSRegion: String, CaseIterable, Identifiable, Sendable {
    case china
    case international

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .china: "小红书（国内）"
        case .international: "rednote（海外）"
        }
    }

    var apiBaseURL: URL {
        switch self {
        case .china: URL(string: "https://edith.xiaohongshu.com")!
        case .international: URL(string: "https://webapi.rednote.com")!
        }
    }

    var webOrigin: String {
        switch self {
        case .china: "https://www.xiaohongshu.com"
        case .international: "https://www.rednote.com"
        }
    }

    /// The site's registrable domain, which its cookies belong to.
    var siteDomain: String {
        switch self {
        case .china: "xiaohongshu.com"
        case .international: "rednote.com"
        }
    }
}
