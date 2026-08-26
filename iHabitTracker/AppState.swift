import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var selectedDate = Calendar.current.startOfDay(for: .now)
    @Published private(set) var habits: [HabitDay] = []
    @Published private(set) var statistics: [HabitStatistics] = []
    @Published private(set) var notifications: [PendingNotification] = []
    @Published private(set) var habitNoteSummaries: [HabitNoteSummary] = []
    @Published var errorMessage: String?

    private var store: HabitStore?

    init() { openStore() }

    func openStore() {
        do {
            store = try HabitStore()
            reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func reload() {
        guard let store else { return }
        do {
            habits = try store.habits(on: selectedDate)
            statistics = try store.statistics()
            notifications = try store.pendingNotifications()
            habitNoteSummaries = try store.habitNoteSummaries()
        } catch { errorMessage = error.localizedDescription }
    }

    func select(_ date: Date) {
        selectedDate = Calendar.current.startOfDay(for: date)
        reload()
    }

    func setStatus(_ status: HabitStatus, for habitID: Int64) {
        do { try store?.setStatus(status, for: habitID, on: selectedDate); reload() }
        catch { errorMessage = error.localizedDescription }
    }

    func createHabit(name: String, startDate: Date) {
        do { try store?.createHabit(name: name, startDate: startDate); reload() }
        catch { errorMessage = error.localizedDescription }
    }

    func note(for habitID: Int64) -> String {
        note(for: habitID, on: selectedDate)
    }

    func note(for habitID: Int64, on day: Date) -> String {
        do { return try store?.note(for: habitID, on: day) ?? "" }
        catch { errorMessage = error.localizedDescription; return "" }
    }

    func saveNote(_ body: String, for habitID: Int64) {
        saveNote(body, for: habitID, on: selectedDate)
    }

    func saveNote(_ body: String, for habitID: Int64, on day: Date) {
        do { try store?.saveNote(body, for: habitID, on: day); reload() }
        catch { errorMessage = error.localizedDescription }
    }

    func notes(for habitID: Int64) -> [HabitNote] {
        do { return try store?.notes(for: habitID) ?? [] }
        catch { errorMessage = error.localizedDescription; return [] }
    }

    func importDatabase(from url: URL) {
        do { store = try HabitStore.replaceDatabase(with: url); reload() }
        catch { errorMessage = error.localizedDescription }
    }

    func monthSummary(for month: Date) -> [Date: (done: Int, missed: Int)] {
        do { return try store?.monthSummary(for: month) ?? [:] }
        catch { errorMessage = error.localizedDescription; return [:] }
    }
}
