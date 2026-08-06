import Foundation

enum TokenFormatter {
    static func short(_ value: Int) -> String {
        let abs = Swift.abs(value)
        switch abs {
        case 0..<1_000:
            return "\(value)"
        case 1_000..<1_000_000:
            return String(format: "%.1fK", Double(value) / 1_000)
        case 1_000_000..<1_000_000_000:
            return String(format: "%.2fM", Double(value) / 1_000_000)
        default:
            return String(format: "%.2fB", Double(value) / 1_000_000_000)
        }
    }
}
