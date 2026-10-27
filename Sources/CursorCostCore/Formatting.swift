import Foundation

public enum Formatting {
    private static let dollar: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let tokenFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    public static func dollars(_ value: Double) -> String {
        let amount = value.isFinite ? value : 0
        let body = dollar.string(from: NSNumber(value: amount)) ?? "0.00"
        return "\(body) $"
    }

    public static func dollarSign(_ value: Double) -> String {
        let amount = value.isFinite ? value : 0
        let body = dollar.string(from: NSNumber(value: amount)) ?? "0.00"
        return "$\(body)"
    }

    public static func percentUsed(_ percent: Double) -> String {
        let value = percent.isFinite ? max(0, percent.rounded()) : 0
        return "\(Int(value))%"
    }

    public static func percentPoint(_ percent: Double) -> String {
        guard percent.isFinite else { return "0%" }
        let tenths = (max(0, percent) * 10).rounded() / 10
        if abs(tenths - tenths.rounded()) < 0.05 {
            return "\(Int(tenths.rounded()))%"
        }
        return String(format: "%.1f%%", tenths)
    }

    public static func tokens(_ value: Double) -> String {
        let amount = value.isFinite ? value.rounded() : 0
        return tokenFormatter.string(from: NSNumber(value: amount)) ?? "0"
    }

    public static func compactTokens(_ value: Double) -> String {
        let amount = value.isFinite ? max(0, value) : 0
        if amount < 1000 {
            return String(Int(amount.rounded()))
        }
        if amount < 1_000_000 {
            return "\(oneDecimal(amount / 1000))k"
        }
        return "\(oneDecimal(amount / 1_000_000))M"
    }

    public static func shortTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    public static func dateTime(_ milliseconds: Double) -> String {
        let date = Date(timeIntervalSince1970: milliseconds / 1000)
        guard milliseconds.isFinite else { return "—" }
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.day, .month, .year, .hour, .minute, .second], from: date)
        let day = parts.day ?? 0
        let month = String(format: "%02d", parts.month ?? 0)
        let year = parts.year ?? 0
        let hours = String(format: "%02d", parts.hour ?? 0)
        let minutes = String(format: "%02d", parts.minute ?? 0)
        let seconds = String(format: "%02d", parts.second ?? 0)
        return "\(day).\(month).\(year), \(hours):\(minutes):\(seconds)"
    }

    public static func kind(_ kind: String?) -> String {
        guard let kind, !kind.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "—"
        }
        var stripped = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = stripped.range(of: "^USAGE_EVENT_KIND_", options: [.regularExpression, .caseInsensitive]) {
            stripped.removeSubrange(range)
        }
        let humanized = stripped
            .split { $0 == "_" || $0.isWhitespace }
            .filter { !$0.isEmpty }
            .map { part -> String in
                let word = String(part).lowercased()
                return word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
        return humanized.isEmpty ? "—" : humanized
    }

    public static func stripModelPrefix(_ model: String?) -> String? {
        guard let model else { return nil }
        if model.hasPrefix("cursor-") {
            return String(model.dropFirst("cursor-".count))
        }
        return model
    }

    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", (value * 10).rounded() / 10)
    }
}
