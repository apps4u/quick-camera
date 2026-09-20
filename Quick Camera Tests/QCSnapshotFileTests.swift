import Foundation
import Testing

@testable import Quick_Camera

@Suite("Snapshot file naming")
struct QCSnapshotFileTests {

    /// Fixed calendar/time zone so the generated names don't depend on where the tests run.
    private static let utc = TimeZone(identifier: "UTC")!

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }

    private static func date(
        year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    private static func filename(for date: Date) -> String {
        QCSnapshotFile.filename(
            for: date, timeZone: utc, locale: Locale(identifier: "en_US"), calendar: calendar)
    }

    @Test("Filename carries the date and 12-hour time")
    func filenameFormat() {
        let name = Self.filename(
            for: Self.date(year: 2026, month: 9, day: 19, hour: 22, minute: 30, second: 24))
        // the trailing day period is locale-dependent, so only its presence is asserted
        #expect(name.hasPrefix("Quick Camera Image 2026-09-19 at 10.30.24 "))
        #expect(name.hasSuffix(".png"))
    }

    @Test("Minutes and seconds are zero padded, the hour is not")
    func zeroPadding() {
        let name = Self.filename(
            for: Self.date(year: 2026, month: 1, day: 5, hour: 9, minute: 5, second: 7))
        #expect(name.hasPrefix("Quick Camera Image 2026-01-05 at 9.05.07 "))
    }

    @Test("Midnight and noon are written as 12, not 0")
    func twelveHourClockUsesTwelve() {
        let midnight = Self.filename(
            for: Self.date(year: 2026, month: 9, day: 19, hour: 0, minute: 5, second: 0))
        let noon = Self.filename(
            for: Self.date(year: 2026, month: 9, day: 19, hour: 12, minute: 5, second: 0))
        #expect(midnight.contains(" at 12.05.00 "))
        #expect(noon.contains(" at 12.05.00 "))
        // midnight and noon differ only by the day period
        #expect(midnight != noon)
    }
}

@Suite("Snapshot file collisions")
struct QCSnapshotFileCollisionTests {

    /// Runs the body against a freshly created, automatically removed directory.
    private func withTemporaryFolder(_ body: (URL) throws -> Void) throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QCSnapshotFileTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try body(folder)
    }

    private func createFile(named name: String, in folder: URL) throws {
        try Data().write(to: folder.appendingPathComponent(name))
    }

    @Test("An unused name is returned unchanged")
    func noCollision() throws {
        try withTemporaryFolder { folder in
            let url = QCSnapshotFile.uniqueURL(forFilename: "Snapshot.png", in: folder)
            #expect(url.lastPathComponent == "Snapshot.png")
        }
    }

    @Test("A taken name gains a counter rather than overwriting")
    func singleCollision() throws {
        try withTemporaryFolder { folder in
            try createFile(named: "Snapshot.png", in: folder)
            let url = QCSnapshotFile.uniqueURL(forFilename: "Snapshot.png", in: folder)
            #expect(url.lastPathComponent == "Snapshot 2.png")
        }
    }

    @Test("The counter keeps climbing while names are taken")
    func repeatedCollisions() throws {
        try withTemporaryFolder { folder in
            try createFile(named: "Snapshot.png", in: folder)
            try createFile(named: "Snapshot 2.png", in: folder)
            try createFile(named: "Snapshot 3.png", in: folder)
            let url = QCSnapshotFile.uniqueURL(forFilename: "Snapshot.png", in: folder)
            #expect(url.lastPathComponent == "Snapshot 4.png")
        }
    }

    @Test("Names containing dots keep their extension")
    func preservesExtension() throws {
        try withTemporaryFolder { folder in
            let name = "Quick Camera Image 2026-09-19 at 10.30.24 pm.png"
            try createFile(named: name, in: folder)
            let url = QCSnapshotFile.uniqueURL(forFilename: name, in: folder)
            #expect(url.lastPathComponent == "Quick Camera Image 2026-09-19 at 10.30.24 pm 2.png")
            #expect(url.pathExtension == "png")
        }
    }

    @Test("Successive captures in the same second never reuse a path")
    func successiveCapturesAreDistinct() throws {
        try withTemporaryFolder { folder in
            var seen: Set<String> = []
            for _ in 0..<3 {
                let url = QCSnapshotFile.uniqueURL(forFilename: "Snapshot.png", in: folder)
                #expect(!seen.contains(url.lastPathComponent))
                seen.insert(url.lastPathComponent)
                // the real save writes the file, which is what pushes the next name along
                try Data().write(to: url)
            }
            #expect(seen.count == 3)
        }
    }
}
