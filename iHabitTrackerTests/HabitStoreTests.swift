import Foundation
import XCTest
@testable import iHabitTracker

final class HabitStoreTests: XCTestCase {
    private var databaseURL: URL!

    override func setUpWithError() throws {
        databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("ihabittracker-tests-\(UUID().uuidString).sqlite3")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: databaseURL)
    }

    func testPendingIsRepresentedByNoLogAndCanBeUndone() throws {
        let store = try HabitStore(databaseURL: databaseURL)
        let day = Calendar(identifier: .gregorian).startOfDay(for: .now)
        try store.createHabit(name: "Read", startDate: day)
        let habit = try XCTUnwrap(store.habits(on: day).first)
        XCTAssertEqual(habit.status, .pending)

        try store.setStatus(.done, for: habit.id, on: day)
        XCTAssertEqual(try store.habits(on: day).first?.status, .done)

        try store.setStatus(.pending, for: habit.id, on: day)
        XCTAssertEqual(try store.habits(on: day).first?.status, .pending)
    }

    func testHistoricalPendingBreaksCurrentStreak() throws {
        let store = try HabitStore(databaseURL: databaseURL)
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        try store.createHabit(name: "Exercise", startDate: twoDaysAgo, today: today)
        let habit = try XCTUnwrap(store.habits(on: today).first)
        try store.setStatus(.pending, for: habit.id, on: yesterday)
        try store.setStatus(.done, for: habit.id, on: today)
        XCTAssertEqual(try store.statistics(through: today).first?.currentStreak, 1)
    }

    func testMonthSummaryUsesDatesWithinTheRequestedMonth() throws {
        let store = try HabitStore(databaseURL: databaseURL)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let august15 = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15))!
        let august26 = calendar.date(from: DateComponents(year: 2026, month: 8, day: 26))!
        let september15 = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15))!

        try store.createHabit(name: "Read", startDate: august15, today: august26)
        let habit = try XCTUnwrap(store.habits(on: august15).first)
        try store.setStatus(.missed, for: habit.id, on: august15)

        let summary = try store.monthSummary(for: august26)
        XCTAssertEqual(summary.count, 31)
        XCTAssertEqual(summary[august15]?.done, 0)
        XCTAssertEqual(summary[august15]?.missed, 1)
        XCTAssertNil(summary[september15])
    }

    func testInvalidImportIsRejected() throws {
        let invalid = FileManager.default.temporaryDirectory.appendingPathComponent("invalid-\(UUID().uuidString).sqlite3")
        FileManager.default.createFile(atPath: invalid.path, contents: Data("not sqlite".utf8))
        XCTAssertThrowsError(try HabitStore.validateImport(at: invalid))
        try? FileManager.default.removeItem(at: invalid)
    }
}
