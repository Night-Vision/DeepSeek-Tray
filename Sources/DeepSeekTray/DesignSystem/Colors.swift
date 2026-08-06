import SwiftUI

extension Color {
    static let dsBackground    = Color(hex: "0D0E12")
    static let dsCard          = Color(hex: "1C1C22")
    static let dsPopover       = Color(hex: "25252E")
    static let dsPopoverSubtle = Color(hex: "2D2D38")

    static let dsBorder        = Color.white.opacity(0.12)
    static let dsBorderHover   = Color.white.opacity(0.22)

    static let dsTextPrimary   = Color(hex: "F5F5F7")
    static let dsTextSecondary = Color(hex: "9A9A9E")
    static let dsTextTertiary  = Color(hex: "6E6E73")

    static let dsAccentBlue      = Color(hex: "0066FF")
    static let dsAccentBlueHover = Color(hex: "267DFF")
    static let dsAccentGreen     = Color(hex: "30D158")
    static let dsAccentAmber     = Color(hex: "FFD60A")
    static let dsAccentRed       = Color(hex: "FF453A")

    static let dsGradientStart = Color(hex: "0066FF")
    static let dsGradientEnd   = Color(hex: "5E5CE6")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
