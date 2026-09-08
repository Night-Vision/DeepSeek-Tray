import Foundation

/// Serialises the platform session so it can live in the Keychain.
///
/// Property lists, not JSON: cookie expiry is an `NSDate`, which plists preserve
/// natively and JSON does not. Losing it would turn every persistent cookie into
/// a session cookie on restore.
enum CookieCodec {
    struct Payload {
        let cookies: [HTTPCookie]
        let lastSuccessfulAuth: Date?
    }

    /// Plist values must be one of these; anything else is dropped rather than
    /// failing the whole encode.
    private static func plistSafe(_ value: Any) -> Any? {
        switch value {
        case is String, is Date, is NSNumber, is Bool, is Data: return value
        case let url as URL: return url.absoluteString
        default: return nil
        }
    }

    static func encode(cookies: [HTTPCookie], lastSuccessfulAuth: Date?) -> String? {
        let rows: [[String: Any]] = cookies.compactMap { cookie in
            guard let props = cookie.properties else { return nil }
            var row: [String: Any] = [:]
            for (key, value) in props {
                if let safe = plistSafe(value) { row[key.rawValue] = safe }
            }
            return row.isEmpty ? nil : row
        }
        var root: [String: Any] = ["cookies": rows]
        if let lastSuccessfulAuth { root["lastSuccessfulAuth"] = lastSuccessfulAuth }
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: root, format: .binary, options: 0
        ) else { return nil }
        return data.base64EncodedString()
    }

    static func decode(_ base64: String) -> Payload {
        guard let data = Data(base64Encoded: base64),
              let root = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ) as? [String: Any]
        else { return Payload(cookies: [], lastSuccessfulAuth: nil) }

        let rows = root["cookies"] as? [[String: Any]] ?? []
        let cookies = rows.compactMap { row -> HTTPCookie? in
            var props: [HTTPCookiePropertyKey: Any] = [:]
            for (key, value) in row { props[HTTPCookiePropertyKey(rawValue: key)] = value }
            return HTTPCookie(properties: props)
        }
        return Payload(cookies: cookies, lastSuccessfulAuth: root["lastSuccessfulAuth"] as? Date)
    }
}
