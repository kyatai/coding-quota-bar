import Foundation

// MARK: - Color Threshold Helper

struct ColorThresholds {
    var green: Double   // >= green% remaining → green
    var yellow: Double  // >= yellow% remaining → yellow, below → red

    func color(for remaining: Double) -> DisplayColor {
        if remaining >= green { return .green }
        if remaining >= yellow { return .yellow }
        return .red
    }
}

// MARK: - Number Formatting

func formatNumber(_ value: Double) -> String {
    if value >= 1_000_000_000 {
        return String(format: "%.1fB", value / 1_000_000_000)
    } else if value >= 1_000_000 {
        return String(format: "%.1fM", value / 1_000_000)
    } else if value >= 1_000 {
        return String(format: "%.1fK", value / 1_000)
    }
    return String(format: "%.0f", value)
}

// MARK: - Time Formatting

func formatResetTime(_ epochMs: Double) -> String {
    let date = Date(timeIntervalSince1970: epochMs / 1000)
    let now = Date()
    let interval = date.timeIntervalSince(now)

    if interval <= 0 {
        return "已重置"
    } else if interval < 3600 {
        let mins = Int(interval / 60)
        return "\(mins)分钟后重置"
    } else if interval < 86400 {
        let hours = Int(interval / 3600)
        return "\(hours)小时后重置"
    } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date) + " 重置"
    }
}

func formatRelativeTime(_ isoString: String) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = formatter.date(from: isoString) else { return "" }
    let interval = Date().timeIntervalSince(date)

    if interval < 60 { return "刚刚更新" }
    if interval < 3600 { return "\(Int(interval / 60))分钟前更新" }
    if interval < 86400 { return "\(Int(interval / 3600))小时前更新" }
    return "\(Int(interval / 86400))天前更新"
}
