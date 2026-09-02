import Foundation

/// Recomputes the date-window query on a captured dashboard usage URL so each
/// request tracks "now" instead of replaying the window frozen at sign-in time.
enum UsageWindow {
    /// Returns `url` with its `start`/`end`/`tz` query items replaced by a live
    /// window of `days`, ending at the start of the day after `now` (so today is
    /// always included — the captured `end` was an exclusive upcoming midnight,
    /// which is why today never appeared). URLs without `start`/`end` are
    /// returned byte-identical (schema-drift guard). `now`/`timeZone` are
    /// parameters purely so the behaviour is deterministic to verify.
    static func live(url: String, days: Int, now: Date, timeZone: TimeZone) -> String {
        guard var components = URLComponents(string: url),
              var items = components.queryItems,
              items.contains(where: { $0.name == "start" }),
              items.contains(where: { $0.name == "end" }) else {
            return url
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
            return url
        }
        let start = end.addingTimeInterval(-Double(days) * 86_400)
        let tz = timeZone.secondsFromGMT(for: now)

        for i in items.indices {
            switch items[i].name {
            case "start": items[i].value = String(Int(start.timeIntervalSince1970))
            case "end": items[i].value = String(Int(end.timeIntervalSince1970))
            case "tz": items[i].value = String(tz)
            default: break
            }
        }
        components.queryItems = items
        return components.url?.absoluteString ?? url
    }
}
