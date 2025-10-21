//
//  TimestampFormatter.swift
//  GlobalBridge
//

import Foundation

enum TimestampFormatter {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func string(for date: Date, relativeTo now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) {
            return timeFormatter.string(from: date)
        }
        if let difference = calendar.dateComponents([.hour], from: date, to: now).hour, abs(difference) < 24 {
            return relativeFormatter.localizedString(for: date, relativeTo: now)
        }
        return dateFormatter.string(from: date)
    }
}
