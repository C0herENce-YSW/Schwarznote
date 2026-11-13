//
//  FlexibleDecoding.swift
//  Schwarznote
//
//  The web API is loosely typed: the same field can be a string or a number, and
//  the same object can use different key names in different endpoints.
//

import Foundation

nonisolated struct AnyKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

nonisolated extension KeyedDecodingContainer where Key == AnyKey {
    /// First of `keys` that holds a string or number, as a string.
    func string(_ keys: String...) -> String? {
        for key in keys.map(AnyKey.init) {
            if let value = try? decode(String.self, forKey: key) { return value }
            if let value = try? decode(Int.self, forKey: key) { return String(value) }
            if let value = try? decode(Double.self, forKey: key) { return String(value) }
        }
        return nil
    }

    func double(_ key: String) -> Double? {
        (try? decode(Double.self, forKey: AnyKey(key))) ?? string(key).flatMap(Double.init)
    }

    /// Timestamps come in seconds in some endpoints and milliseconds in others.
    func date(_ key: String) -> Date? {
        double(key).map { Date(timeIntervalSince1970: $0 > 1e12 ? $0 / 1000 : $0) }
    }

    func value<T: Decodable>(_ type: T.Type, _ keys: String...) -> T? {
        for key in keys.map(AnyKey.init) {
            if let value = try? decode(T.self, forKey: key) { return value }
        }
        return nil
    }

    func nested(_ key: String) -> KeyedDecodingContainer<AnyKey>? {
        try? nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey(key))
    }
}

nonisolated extension URL {
    /// Image URLs from the API are often plain `http`, which App Transport Security blocks.
    /// The CDNs serve the same paths over https.
    init?(webImage string: String?) {
        guard var string, !string.isEmpty else { return nil }
        if string.hasPrefix("//") { string = "https:" + string }
        if string.hasPrefix("http://") { string = "https://" + string.dropFirst(7) }
        self.init(string: string)
    }
}

/// Decodes an array, skipping elements that fail to decode (ads, unknown card types).
nonisolated struct LossyArray<Element: Decodable & Sendable>: Decodable, Sendable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                _ = try? container.decode(IgnoredPayload.self)
            }
        }
        self.elements = elements
    }
}
