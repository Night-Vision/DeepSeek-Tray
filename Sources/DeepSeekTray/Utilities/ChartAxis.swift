import Foundation

enum ChartAxis {
    static func niceBounds(for values: [Int]) -> [Double] {
        guard let maxValue = values.max(), maxValue > 0 else { return [0, 0, 0] }
        let raw = Double(maxValue)
        let magnitude = pow(10, floor(log10(raw)))
        let normalized = raw / magnitude
        let niceMax: Double
        if normalized <= 1 { niceMax = magnitude }
        else if normalized <= 2 { niceMax = 2 * magnitude }
        else if normalized <= 5 { niceMax = 5 * magnitude }
        else { niceMax = 10 * magnitude }
        return [niceMax, niceMax / 2, 0]
    }
}
