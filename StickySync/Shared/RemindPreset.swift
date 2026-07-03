// RemindPreset.swift
//
// 0.12.1: quick-preset date computation for the /remind popover.
// The 4 presets that cover ~80% of real /remind usage per the UX
// research (Fantastical / Todoist / Things / iOS 26 Reminders all
// converge here).
//
// Time computation is pure + testable. `now` is injected so a test
// can pin exactly what "Tomorrow 9am" resolves to given a specific
// moment.

import Foundation

enum RemindPreset: CaseIterable, Equatable {
    case in30Minutes
    case tomorrow9am
    case nextMonday9am
    case custom

    /// Menu label shown in the popover.
    var label: String {
        switch self {
        case .in30Minutes:   return "In 30 minutes"
        case .tomorrow9am:   return "Tomorrow, 9:00 AM"
        case .nextMonday9am: return "Next Monday, 9:00 AM"
        case .custom:        return "Custom time…"
        }
    }

    /// Concrete fire date for the preset relative to `now`. Returns
    /// nil for `.custom` (the caller shows a date picker instead).
    /// Uses the current calendar + timezone — matches user's local
    /// time intuition ("tomorrow 9am at LAX" fires at 9am local
    /// wherever they are at fire time).
    func fireAt(now: Date,
                calendar: Calendar = .current) -> Date? {
        switch self {
        case .in30Minutes:
            return now.addingTimeInterval(30 * 60)

        case .tomorrow9am:
            // Start of tomorrow, then set to 9am.
            let startOfToday = calendar.startOfDay(for: now)
            guard let tomorrow = calendar.date(byAdding: .day, value: 1,
                                               to: startOfToday) else {
                return nil
            }
            return calendar.date(bySettingHour: 9, minute: 0, second: 0,
                                 of: tomorrow)

        case .nextMonday9am:
            // Weekday numbering: Sunday=1, Monday=2, …, Saturday=7.
            let today = calendar.component(.weekday, from: now)
            // Days to add: if today is Sun (1), we want +1; if Mon
            // (2), we want the NEXT Monday, so +7; if Tue (3), +6;
            // …; if Sat (7), +2.
            let daysToAdd: Int
            if today == 1 { daysToAdd = 1 }             // Sun → next Mon
            else if today == 2 { daysToAdd = 7 }        // Mon → next Mon (never today)
            else { daysToAdd = 9 - today }              // Tue..Sat → next Mon
            let startOfToday = calendar.startOfDay(for: now)
            guard let target = calendar.date(byAdding: .day,
                                             value: daysToAdd,
                                             to: startOfToday) else {
                return nil
            }
            return calendar.date(bySettingHour: 9, minute: 0, second: 0,
                                 of: target)

        case .custom:
            return nil
        }
    }
}
