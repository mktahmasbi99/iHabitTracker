import Foundation

enum HabitStatus: String, CaseIterable, Codable, Identifiable {
    case pending
    case done
    case missed

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct Habit: Identifiable, Equatable {
    let id: Int64
    var name: String
    let startDate: Date
    let archivedAt: Date?
}

struct HabitDay: Identifiable, Equatable {
    let habit: Habit
    let status: HabitStatus
    let currentStreak: Int

    var id: Int64 { habit.id }
}

struct HabitNote: Identifiable, Equatable {
    let habitID: Int64
    let habitName: String
    let date: Date
    let body: String

    var id: String { "\(habitID)-\(date.timeIntervalSince1970)" }
}

struct HabitStreak: Identifiable, Equatable {
    let startDate: Date
    let endDate: Date
    let length: Int

    var id: String { "\(startDate.timeIntervalSince1970)-\(endDate.timeIntervalSince1970)" }
}

struct HabitStatistics: Identifiable, Equatable {
    let habit: Habit
    let currentStreak: Int
    let longestStreak: HabitStreak?
    let streaks: [HabitStreak]
    let noteCount: Int

    var id: Int64 { habit.id }
}

struct PendingNotification: Identifiable, Equatable {
    let day: Date
    let pendingCount: Int

    var id: Date { day }
}

enum HabitTrackerError: LocalizedError {
    case invalidHabitName
    case inactiveHabit
    case invalidImport(String)

    var errorDescription: String? {
        switch self {
        case .invalidHabitName: "Habit names cannot be empty."
        case .inactiveHabit: "This habit was not active on the selected date."
        case let .invalidImport(message): message
        }
    }
}
