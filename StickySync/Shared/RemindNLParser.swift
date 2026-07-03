// RemindNLParser.swift
//
// 0.12.2: natural-language date parser for the free-text portion of
// a /remind trigger. `/remind tomorrow 9am` → skip the popover and
// set the reminder directly.
//
// Strategy (per the UX research pass — start narrow, expand if
// users complain):
//   1. Small custom pre-processor for phrases NSDataDetector
//      misses or gets wrong: "in N min/hour/day", "tomorrow
//      morning/evening", "next monday morning".
//   2. Fall through to NSDataDetector for everything else
//      ("tomorrow 9am", "friday 3pm", "june 25", etc.).
//   3. Empty / no-match → return nil, caller shows the preset
//      popover.
//
// All time math takes an injected `now` so tests can pin every
// case deterministically.

import Foundation

enum RemindNLParser {

    /// Parse the free-text portion of a /remind trigger into a
    /// concrete future Date. Returns nil if we couldn't confidently
    /// interpret it — caller should fall back to the popover.
    static func parse(_ input: String,
                       now: Date,
                       calendar: Calendar = .current) -> Date? {
        let text = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return nil }

        if let d = parseRelative(text, now: now) { return d }
        if let d = parseDayOfWeekPhrase(text, now: now, calendar: calendar) { return d }
        if let d = parseDataDetector(input, now: now, calendar: calendar) { return d }
        return nil
    }

    // MARK: - "in N minute(s) / hour(s) / day(s)"

    /// Matches "in 5 min", "in 30 minutes", "in 2 hours", "in 3
    /// days" (and their singular forms). Returns the resolved date
    /// or nil.
    private static func parseRelative(_ text: String, now: Date) -> Date? {
        let pattern = #"^in\s+(\d+)\s+(min(?:ute)?s?|h(?:ou)?rs?|days?)\.?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let m = regex.firstMatch(in: text, range: range) else { return nil }

        let nsText = text as NSString
        guard let n = Int(nsText.substring(with: m.range(at: 1))) else { return nil }
        let unit = nsText.substring(with: m.range(at: 2))

        let seconds: TimeInterval
        switch unit.prefix(1) {
        case "m": seconds = TimeInterval(n * 60)
        case "h": seconds = TimeInterval(n * 3600)
        case "d": seconds = TimeInterval(n * 86400)
        default:  return nil
        }
        return now.addingTimeInterval(seconds)
    }

    // MARK: - "tomorrow morning", "next monday 9am", etc.

    private static let timeOfDayHour: [String: Int] = [
        "morning":   9,
        "noon":      12,
        "afternoon": 14,
        "evening":   19,
        "night":     21,
    ]

    /// Handles "today" / "tomorrow" / "next {weekday}" combined
    /// with an optional named time-of-day. Returns the resolved
    /// date at the chosen hour (default 9:00 if no time).
    private static func parseDayOfWeekPhrase(_ text: String,
                                              now: Date,
                                              calendar: Calendar) -> Date? {
        // Split off an optional trailing time-of-day word.
        var words = text.split(separator: " ").map(String.init)
        var hour = 9
        if let last = words.last, let h = timeOfDayHour[last] {
            hour = h
            words.removeLast()
        }
        let phrase = words.joined(separator: " ")

        // Base day resolution.
        let startOfToday = calendar.startOfDay(for: now)
        let targetDay: Date?
        switch phrase {
        case "today":
            targetDay = startOfToday
        case "tonight":
            hour = 21
            targetDay = startOfToday
        case "tomorrow":
            targetDay = calendar.date(byAdding: .day, value: 1, to: startOfToday)
        default:
            targetDay = parseNextWeekday(phrase, now: now, calendar: calendar)
        }
        guard let day = targetDay else { return nil }
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)
    }

    /// "next monday" through "next sunday" → the next occurrence of
    /// that weekday, always in the future (a Monday saying "next
    /// monday" means 7 days out, not today).
    private static func parseNextWeekday(_ phrase: String,
                                         now: Date,
                                         calendar: Calendar) -> Date? {
        let weekdayNames: [String: Int] = [
            "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
            "thursday": 5, "friday": 6, "saturday": 7,
        ]
        let stripped = phrase.hasPrefix("next ") ? String(phrase.dropFirst("next ".count)) : phrase
        guard let target = weekdayNames[stripped] else { return nil }
        let today = calendar.component(.weekday, from: now)
        var daysToAdd = (target - today + 7) % 7
        if daysToAdd == 0 { daysToAdd = 7 } // "next Monday" from a Monday = next week
        let startOfToday = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: daysToAdd, to: startOfToday)
    }

    // MARK: - Fall-through to NSDataDetector

    /// Uses Apple's NSDataDetector for phrases the custom parser
    /// doesn't cover ("tomorrow 9am", "friday 3pm", "june 25").
    /// Only returns dates in the FUTURE — a past match is treated
    /// as "user meant next occurrence" for common cases (e.g., "9am"
    /// after 9am today means tomorrow 9am), but returned nil for
    /// ambiguity so caller can prompt instead.
    private static func parseDataDetector(_ input: String,
                                          now: Date,
                                          calendar: Calendar) -> Date? {
        guard let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let range = NSRange(location: 0, length: input.utf16.count)
        guard let match = detector.firstMatch(in: input, range: range),
              let date = match.date else {
            return nil
        }
        // If NSDataDetector returned a past date but the user said
        // "9am" (no explicit day) → shift to tomorrow.
        if date < now {
            let shifted = calendar.date(byAdding: .day, value: 1, to: date)
            if let s = shifted, s > now { return s }
            return nil
        }
        return date
    }
}
