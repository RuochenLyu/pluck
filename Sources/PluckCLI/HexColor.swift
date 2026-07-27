import Foundation
import PluckKit

enum HexColor {
    /// Accepts `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, with or without the `#`.
    static func parse(_ text: String) -> PluckColor? {
        var digits = text.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.allSatisfy(\.isHexDigit) else { return nil }

        let expanded: String
        switch digits.count {
        case 3, 4:
            expanded = digits.map { "\($0)\($0)" }.joined()
        case 6, 8:
            expanded = digits
        default:
            return nil
        }

        var components: [Double] = []
        var index = expanded.startIndex
        while index < expanded.endIndex {
            let next = expanded.index(index, offsetBy: 2)
            guard let value = UInt8(expanded[index..<next], radix: 16) else { return nil }
            components.append(Double(value) / 255)
            index = next
        }

        return PluckColor(
            red: components[0],
            green: components[1],
            blue: components[2],
            alpha: components.count == 4 ? components[3] : 1
        )
    }
}
