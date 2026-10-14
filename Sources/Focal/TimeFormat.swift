import Foundation

enum TimeFormat {
    /// "04:32" or "1:00:00"
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, sec)
        }
        return String(format: "%02d:%02d", m, sec)
    }

    /// Idle menu bar label: "25m" or "1h 00m"
    static func duration(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        if minutes >= 60 {
            return String(format: "%dh %02dm", minutes / 60, minutes % 60)
        }
        return "\(minutes)m"
    }

    /// Compact running label: "25m", "42s"
    static func compact(_ seconds: Int) -> String {
        if seconds >= 60 {
            return "\(Int((Double(seconds) / 60).rounded(.up)))m"
        }
        return "\(max(0, seconds))s"
    }

    /// Preset button label: "5m", "1h", "1h30m"
    static func preset(minutes: Int) -> String {
        if minutes >= 60 {
            return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h\(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    /// Today's total: "45m", "1h 15m"
    static func total(_ seconds: Int) -> String {
        let minutes = seconds / 60
        if minutes >= 60 {
            return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }
}
