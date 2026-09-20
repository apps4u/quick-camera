import Foundation

/// Naming and collision handling for saved snapshots. Time zone, locale and calendar are
/// parameters rather than implicit globals so the naming can be exercised deterministically.
enum QCSnapshotFile {
    /// e.g. "Quick Camera Image 2026-09-19 at 10.30.24 pm.png"
    static func filename(
        for date: Date,
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        calendar: Calendar = .current
    ) -> String {
        let dateFormat: Date.FormatString =
            "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)"
        let timeFormat: Date.FormatString =
            "\(hour: .defaultDigits(clock: .twelveHour, hourCycle: .oneBased)).\(minute: .twoDigits).\(second: .twoDigits) \(dayPeriod: .standard(.abbreviated))"

        let day: String = date.formatted(
            Date.VerbatimFormatStyle(format: dateFormat, timeZone: timeZone, calendar: calendar))
        let time: String = date.formatted(
            Date.VerbatimFormatStyle(format: timeFormat, timeZone: timeZone, calendar: calendar)
                .locale(locale))
        return "Quick Camera Image \(day) at \(time).png"
    }

    /* The timestamp only has one-second resolution, so two captures in the same second would
       collide. Append a counter rather than silently overwriting the earlier snapshot. */
    static func uniqueURL(
        forFilename filename: String,
        in folder: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let name = (filename as NSString).deletingPathExtension
        let fileExtension = (filename as NSString).pathExtension
        var candidate: URL = folder.appendingPathComponent(filename)
        var counter: Int = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(name) \(counter).\(fileExtension)")
            counter += 1
        }
        return candidate
    }
}
