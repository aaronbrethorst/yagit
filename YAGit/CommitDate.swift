import Foundation

/// Commit timestamps relative to the calendar day: "Today at 08:14", "Yesterday at 17:48",
/// "Sep 14 at 11:02", and the year added when it differs from now's.
///
/// Every style is built from `calendar` (its locale and time zone), never the process defaults,
/// so the day boundaries and the printed time always agree.
enum CommitDate {
    static func string(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let locale = calendar.locale ?? .current
        let base = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale,
                                                   calendar: calendar, timeZone: calendar.timeZone))
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "Today at \(time)", locale: locale)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "Yesterday at \(time)", locale: locale)
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        let day = date.formatted(sameYear ? base.month(.abbreviated).day() : base.month(.abbreviated).day().year())
        return String(localized: "\(day) at \(time)", locale: locale)
    }
}
