import Foundation
import GRDB

/// SQLite persistence compatible with terminal-habit-tracker's database contract.
final class HabitStore {
    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private let database: DatabaseQueue
    let databaseURL: URL

    init(databaseURL: URL = HabitStore.defaultDatabaseURL()) throws {
        self.databaseURL = databaseURL
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        database = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        try migrateAndRepair()
    }

    static func defaultDatabaseURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iHabitTracker", isDirectory: true)
        return directory.appendingPathComponent("habit_tracker.sqlite3")
    }

    static func dayString(_ day: Date) -> String { dateOnlyFormatter.string(from: day) }

    static func date(from value: String) -> Date {
        dateOnlyFormatter.date(from: value) ?? .distantPast
    }

    private func migrateAndRepair() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("terminal-schema-v1") { database in
            try database.execute(sql: """
                CREATE TABLE IF NOT EXISTS habits (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    start_date TEXT NOT NULL,
                    completed_at TEXT,
                    archived_at TEXT,
                    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
                );
                CREATE TABLE IF NOT EXISTS habit_logs (
                    habit_id INTEGER NOT NULL,
                    log_date TEXT NOT NULL,
                    status TEXT NOT NULL CHECK (status IN ('done', 'missed')),
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (habit_id, log_date),
                    FOREIGN KEY (habit_id) REFERENCES habits(id) ON DELETE CASCADE
                );
                CREATE TABLE IF NOT EXISTS habit_notes (
                    habit_id INTEGER NOT NULL,
                    note_date TEXT NOT NULL,
                    body TEXT NOT NULL,
                    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (habit_id, note_date),
                    FOREIGN KEY (habit_id) REFERENCES habits(id) ON DELETE CASCADE
                );
                CREATE TABLE IF NOT EXISTS habit_challenges (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    habit_id INTEGER NOT NULL,
                    start_date TEXT NOT NULL,
                    end_date TEXT NOT NULL,
                    completed_at TEXT,
                    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (habit_id) REFERENCES habits(id) ON DELETE CASCADE
                );
                CREATE TABLE IF NOT EXISTS habit_archive_periods (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    habit_id INTEGER NOT NULL,
                    archived_at TEXT NOT NULL,
                    resurrected_at TEXT,
                    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (habit_id) REFERENCES habits(id) ON DELETE CASCADE
                );
                """)
        }
        try migrator.migrate(database)
        try database.write { database in
            let habitColumns = try Row.fetchAll(database, sql: "PRAGMA table_info(habits)").map { $0["name"] as String }
            if !habitColumns.contains("completed_at") { try database.execute(sql: "ALTER TABLE habits ADD COLUMN completed_at TEXT") }
            if !habitColumns.contains("archived_at") { try database.execute(sql: "ALTER TABLE habits ADD COLUMN archived_at TEXT") }
            let today = Self.dayString(.now)
            let legacyRows = try Row.fetchAll(database, sql: "SELECT id, completed_at, archived_at FROM habits WHERE completed_at IS NOT NULL")
            for habit in legacyRows {
                let id: Int64 = habit["id"]
                let completedAt: String = habit["completed_at"]
                let archivedAt: String? = habit["archived_at"]
                if archivedAt == nil && completedAt > today {
                    let challengeExists = try Bool.fetchOne(database, sql: "SELECT EXISTS(SELECT 1 FROM habit_challenges WHERE habit_id = ? AND start_date = ? AND end_date = ?)", arguments: [id, today, completedAt]) ?? false
                    if !challengeExists { try database.execute(sql: "INSERT INTO habit_challenges (habit_id, start_date, end_date) VALUES (?, ?, ?)", arguments: [id, today, completedAt]) }
                } else if archivedAt == nil {
                    try database.execute(sql: "UPDATE habits SET archived_at = ? WHERE id = ?", arguments: [completedAt, id])
                }
                try database.execute(sql: "UPDATE habits SET completed_at = NULL WHERE id = ?", arguments: [id])
            }
            let archivedHabits = try Row.fetchAll(database, sql: "SELECT id, archived_at FROM habits WHERE archived_at IS NOT NULL")
            for habit in archivedHabits {
                let id: Int64 = habit["id"]
                let archivedAt: String = habit["archived_at"]
                let exists = try Bool.fetchOne(database, sql: "SELECT EXISTS(SELECT 1 FROM habit_archive_periods WHERE habit_id = ? AND archived_at = ? AND resurrected_at IS NULL)", arguments: [id, archivedAt]) ?? false
                if !exists { try database.execute(sql: "INSERT INTO habit_archive_periods (habit_id, archived_at) VALUES (?, ?)", arguments: [id, archivedAt]) }
            }
        }
    }

    func createHabit(name: String, startDate: Date, today: Date = .now) throws {
        let cleaned = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !cleaned.isEmpty else { throw HabitTrackerError.invalidHabitName }
        let start = Self.dayString(startDate)
        let current = Self.dayString(today)
        try database.write { database in
            try database.execute(sql: "INSERT INTO habits (name, start_date) VALUES (?, ?)", arguments: [cleaned, start])
            let id = database.lastInsertedRowID
            guard start < current else { return }
            var day = startDate
            let calendar = Calendar(identifier: .gregorian)
            while Self.dayString(day) < current {
                try database.execute(sql: "INSERT INTO habit_logs (habit_id, log_date, status) VALUES (?, ?, 'done')", arguments: [id, Self.dayString(day)])
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
        }
    }

    func habits(on day: Date) throws -> [HabitDay] {
        let dayString = Self.dayString(day)
        let habits = try database.read { database -> [(Habit, HabitStatus)] in
            let rows = try Row.fetchAll(database, sql: """
                SELECT habits.id, habits.name, habits.start_date, habits.archived_at,
                       COALESCE(habit_logs.status, 'pending') AS status
                FROM habits
                LEFT JOIN habit_logs ON habit_logs.habit_id = habits.id AND habit_logs.log_date = ?
                WHERE habits.start_date <= ? AND habits.archived_at IS NULL
                  AND NOT EXISTS (
                    SELECT 1 FROM habit_archive_periods
                    WHERE habit_archive_periods.habit_id = habits.id
                      AND habit_archive_periods.archived_at <= ?
                      AND (habit_archive_periods.resurrected_at IS NULL OR habit_archive_periods.resurrected_at > ?)
                  )
                ORDER BY habits.start_date, habits.name
                """, arguments: [dayString, dayString, dayString, dayString])
            return rows.map { row in
                let habit = Habit(id: row["id"], name: row["name"], startDate: Self.date(from: row["start_date"]), archivedAt: nil)
                return (habit, HabitStatus(rawValue: row["status"]) ?? .pending)
            }
        }
        return try habits.map { HabitDay(habit: $0.0, status: $0.1, currentStreak: try currentStreak(for: $0.0.id, through: day)) }
    }

    func setStatus(_ status: HabitStatus, for habitID: Int64, on day: Date) throws {
        let date = Self.dayString(day)
        guard try habitIsActive(habitID, on: day) else { throw HabitTrackerError.inactiveHabit }
        try database.write { database in
            if status == .pending {
                try database.execute(sql: "DELETE FROM habit_logs WHERE habit_id = ? AND log_date = ?", arguments: [habitID, date])
            } else {
                try database.execute(sql: """
                    INSERT INTO habit_logs (habit_id, log_date, status, updated_at) VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                    ON CONFLICT(habit_id, log_date) DO UPDATE SET status = excluded.status, updated_at = CURRENT_TIMESTAMP
                    """, arguments: [habitID, date, status.rawValue])
            }
        }
    }

    func note(for habitID: Int64, on day: Date) throws -> String {
        try database.read { database in
            try String.fetchOne(database, sql: "SELECT body FROM habit_notes WHERE habit_id = ? AND note_date = ?", arguments: [habitID, Self.dayString(day)]) ?? ""
        }
    }

    func saveNote(_ body: String, for habitID: Int64, on day: Date) throws {
        guard try habitIsActive(habitID, on: day) else { throw HabitTrackerError.inactiveHabit }
        try database.write { database in
            if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try database.execute(sql: "DELETE FROM habit_notes WHERE habit_id = ? AND note_date = ?", arguments: [habitID, Self.dayString(day)])
            } else {
                try database.execute(sql: """
                    INSERT INTO habit_notes (habit_id, note_date, body, updated_at) VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                    ON CONFLICT(habit_id, note_date) DO UPDATE SET body = excluded.body, updated_at = CURRENT_TIMESTAMP
                    """, arguments: [habitID, Self.dayString(day), body])
            }
        }
    }

    func allNotes() throws -> [HabitNote] {
        try database.read { database in
            try Row.fetchAll(database, sql: """
                SELECT habit_notes.habit_id, habits.name, habit_notes.note_date, habit_notes.body
                FROM habit_notes JOIN habits ON habits.id = habit_notes.habit_id
                ORDER BY habit_notes.note_date DESC
                """).map { HabitNote(habitID: $0["habit_id"], habitName: $0["name"], date: Self.date(from: $0["note_date"]), body: $0["body"]) }
        }
    }

    func statistics(through day: Date = .now) throws -> [HabitStatistics] {
        let habits = try database.read { database in
            try Row.fetchAll(database, sql: "SELECT id, name, start_date, archived_at FROM habits WHERE archived_at IS NULL ORDER BY start_date, name")
                .map { Habit(id: $0["id"], name: $0["name"], startDate: Self.date(from: $0["start_date"]), archivedAt: nil) }
        }
        return try habits.map { habit in
            let streaks = try streaks(for: habit, through: day)
            let notes = try database.read { database in try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM habit_notes WHERE habit_id = ?", arguments: [habit.id]) ?? 0 }
            return HabitStatistics(habit: habit, currentStreak: try currentStreak(for: habit.id, through: day), longestStreak: streaks.first, streaks: streaks, noteCount: notes)
        }
    }

    func monthSummary(for month: Date) throws -> [Date: (done: Int, missed: Int)] {
        let calendar = Calendar(identifier: .gregorian)
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [:] }
        return try Dictionary(uniqueKeysWithValues: range.compactMap { number in
            guard let date = calendar.date(bySetting: .day, value: number, of: month) else { return nil }
            let habits = try habits(on: date)
            return (date, (habits.filter { $0.status == .done }.count, habits.filter { $0.status == .missed }.count))
        })
    }

    func pendingNotifications(today: Date = .now) throws -> [PendingNotification] {
        let calendar = Calendar(identifier: .gregorian)
        let todayStart = calendar.startOfDay(for: today)
        let activeHabits = try database.read { database in try Row.fetchAll(database, sql: "SELECT id, name, start_date FROM habits WHERE archived_at IS NULL ORDER BY start_date, name").map { Habit(id: $0["id"], name: $0["name"], startDate: Self.date(from: $0["start_date"]), archivedAt: nil) } }
        guard let earliest = activeHabits.map(\.startDate).min(), earliest < todayStart else { return [] }
        var result: [PendingNotification] = []
        var date = calendar.startOfDay(for: earliest)
        while date < todayStart {
            let pending = try habits(on: date).filter { $0.status == .pending }.count
            if pending > 0 { result.append(PendingNotification(day: date, pendingCount: pending)) }
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        return result
    }

    private func habitIsActive(_ id: Int64, on day: Date) throws -> Bool {
        let date = Self.dayString(day)
        return try database.read { database in
            try Bool.fetchOne(database, sql: """
                SELECT EXISTS(SELECT 1 FROM habits WHERE id = ? AND start_date <= ? AND archived_at IS NULL
                    AND NOT EXISTS (SELECT 1 FROM habit_archive_periods WHERE habit_id = habits.id AND archived_at <= ? AND (resurrected_at IS NULL OR resurrected_at > ?)))
                """, arguments: [id, date, date, date]) ?? false
        }
    }

    private func currentStreak(for habitID: Int64, through day: Date) throws -> Int {
        guard let habit = try database.read({ database in try Row.fetchOne(database, sql: "SELECT id, name, start_date FROM habits WHERE id = ?", arguments: [habitID]).map { Habit(id: $0["id"], name: $0["name"], startDate: Self.date(from: $0["start_date"]), archivedAt: nil) } }) else { return 0 }
        let streaks = try streaks(for: habit, through: day)
        let todayStatus = try database.read { database in try String.fetchOne(database, sql: "SELECT status FROM habit_logs WHERE habit_id = ? AND log_date = ?", arguments: [habitID, Self.dayString(day)]) }
        let expectedEnd = todayStatus == HabitStatus.done.rawValue ? day : Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: day)!
        return streaks.first(where: { Calendar(identifier: .gregorian).isDate($0.endDate, inSameDayAs: expectedEnd) })?.length ?? 0
    }

    private func streaks(for habit: Habit, through day: Date) throws -> [HabitStreak] {
        let rows = try database.read { database in try Row.fetchAll(database, sql: "SELECT log_date, status FROM habit_logs WHERE habit_id = ? AND log_date >= ? AND log_date <= ? ORDER BY log_date", arguments: [habit.id, Self.dayString(habit.startDate), Self.dayString(day)]) }
        let statuses = Dictionary(uniqueKeysWithValues: rows.map { (Self.date(from: $0["log_date"]), $0["status"] as String) })
        var output: [HabitStreak] = []
        var start: Date?
        var current = habit.startDate
        let calendar = Calendar(identifier: .gregorian)
        while current <= day {
            if statuses[current] == HabitStatus.done.rawValue {
                start = start ?? current
            } else if let streakStart = start {
                let end = calendar.date(byAdding: .day, value: -1, to: current)!
                output.append(HabitStreak(startDate: streakStart, endDate: end, length: calendar.dateComponents([.day], from: streakStart, to: end).day! + 1))
                start = nil
            }
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        if let start { output.append(HabitStreak(startDate: start, endDate: day, length: calendar.dateComponents([.day], from: start, to: day).day! + 1)) }
        return output.sorted { $0.length == $1.length ? $0.startDate < $1.startDate : $0.length > $1.length }
    }

    static func validateImport(at sourceURL: URL) throws {
        var configuration = Configuration(); configuration.foreignKeysEnabled = true
        let source = try DatabaseQueue(path: sourceURL.path, configuration: configuration)
        let expected = Set(["habits", "habit_logs", "habit_notes", "habit_challenges", "habit_archive_periods"])
        try source.read { database in
            guard (try String.fetchOne(database, sql: "PRAGMA quick_check")) == "ok" else { throw HabitTrackerError.invalidImport("The selected database is corrupted.") }
            let tables = Set(try String.fetchAll(database, sql: "SELECT name FROM sqlite_master WHERE type = 'table'"))
            guard expected.isSubset(of: tables) else { throw HabitTrackerError.invalidImport("The selected file is not a terminal-habit-tracker database.") }
        }
    }

    static func replaceDatabase(with sourceURL: URL) throws -> HabitStore {
        try validateImport(at: sourceURL)
        let destination = defaultDatabaseURL()
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: destination.path) {
            let backupDirectory = destination.deletingLastPathComponent().appendingPathComponent("backups", isDirectory: true)
            try manager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let backup = backupDirectory.appendingPathComponent("import-safety-\(Int(Date.now.timeIntervalSince1970)).sqlite3")
            try manager.copyItem(at: destination, to: backup)
            try manager.removeItem(at: destination)
        }
        try manager.copyItem(at: sourceURL, to: destination)
        return try HabitStore(databaseURL: destination)
    }
}
