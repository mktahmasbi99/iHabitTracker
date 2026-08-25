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

    func testInvalidImportIsRejected() throws {
        let invalid = FileManager.default.temporaryDirectory.appendingPathComponent("invalid-\(UUID().uuidString).sqlite3")
        FileManager.default.createFile(atPath: invalid.path, contents: Data("not sqlite".utf8))
        XCTAssertThrowsError(try HabitStore.validateImport(at: invalid))
        try? FileManager.default.removeItem(at: invalid)
    }
}
