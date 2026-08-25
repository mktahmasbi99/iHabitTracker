import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @State private var selectedTab: AppTab = .today

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                activeTab
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                AppTabBar(selection: $selectedTab)
                    .safeAreaPadding(.bottom)
                    .background(.bar)
            }
            // The root view draws behind the system status area. Keep page
            // controls clear of it without reintroducing a top screen margin.
            .padding(.top, 24)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var activeTab: some View {
        switch selectedTab {
        case .today: TodayView()
        case .calendar: CalendarView()
        case .statistics: StatisticsView()
        case .more: MoreView()
        }
    }
}

private enum AppTab: CaseIterable, Identifiable {
    case today, calendar, statistics, more

    var id: Self { self }
    var title: String {
        switch self { case .today: "Today"; case .calendar: "Calendar"; case .statistics: "Stats"; case .more: "More" }
    }
    var symbol: String {
        switch self { case .today: "checkmark.circle.fill"; case .calendar: "calendar"; case .statistics: "chart.line.uptrend.xyaxis"; case .more: "ellipsis.circle" }
    }
}

private struct AppTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                AppTabBarItem(tab: tab, isSelected: selection == tab) { selection = tab }
            }
        }
        .padding(.top, 7)
    }
}

private struct AppTabBarItem: View {
    let tab: AppTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .font(.title3)
                Text(tab.title)
                    .font(.caption)
            }
            .fontWeight(isSelected ? .semibold : .regular)
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TodayView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingAddHabit = false
    @State private var noteHabit: Habit?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.largeTitle.bold())
            Text(state.selectedDate.formatted(date: .complete, time: .omitted))
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button { showingAddHabit = true } label: {
                    Image(systemName: "plus")
                        .font(.title2.weight(.medium))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
            }

            if state.habits.isEmpty {
                ContentUnavailableView("No habits", systemImage: "checkmark.circle", description: Text("Add a daily habit to begin."))
                    .frame(maxWidth: .infinity, minHeight: 200, alignment: .top)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                    ForEach(state.habits) { habitDay in
                        HabitDayRow(habitDay: habitDay, select: { state.setStatus($0, for: habitDay.habit.id) }, note: { noteHabit = habitDay.habit })
                            .padding(14)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showingAddHabit) { AddHabitSheet(defaultDate: state.selectedDate) { state.createHabit(name: $0, startDate: $1); showingAddHabit = false } }
        .sheet(item: $noteHabit) { NoteEditor(habit: $0, date: state.selectedDate, body: state.note(for: $0.id)) { state.saveNote($0, for: $1.id); noteHabit = nil } }
    }
}

private struct HabitDayRow: View {
    let habitDay: HabitDay
    let select: (HabitStatus) -> Void
    let note: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(habitDay.habit.name).font(.headline); Spacer(); Text("\(habitDay.currentStreak) streak").font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 8) {
                ForEach(HabitStatus.allCases) { status in
                    Button(status.title) { select(status) }
                        .buttonStyle(.bordered)
                        .tint(status == habitDay.status ? tint(for: status) : .gray)
                        .accessibilityLabel("Set \(habitDay.habit.name) to \(status.title)")
                }
                Spacer()
                Button(action: note) { Image(systemName: "note.text") }.buttonStyle(.borderless).accessibilityLabel("Edit note for \(habitDay.habit.name)")
            }
        }
        .padding(.vertical, 3)
    }

    private func tint(for status: HabitStatus) -> Color {
        switch status { case .pending: .orange; case .done: .green; case .missed: .red }
    }
}

private struct CalendarView: View {
    @EnvironmentObject private var state: AppState
    @State private var month = Calendar.current.startOfDay(for: .now)
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let summary = state.monthSummary(for: month)

                ScrollView {
                    VStack(spacing: 24) {
                        calendarGrid(summary: summary)
                            // The calendar itself is centered in the usable tab
                            // area; selected-day controls remain available below.
                            .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)

                        if !state.habits.isEmpty {
                            LazyVStack(spacing: 12) {
                                ForEach(state.habits) { habitDay in
                                    HabitDayRow(
                                        habitDay: habitDay,
                                        select: { state.setStatus($0, for: habitDay.habit.id) },
                                        note: {}
                                    )
                                    .padding(14)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Calendar")
            .onChange(of: state.selectedDate) { _, date in if !Calendar.current.isDate(date, equalTo: month, toGranularity: .month) { month = date } }
        }
    }

    private func calendarGrid(summary: [Date: (done: Int, missed: Int)]) -> some View {
        VStack(spacing: 20) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(month.formatted(.dateTime.year().month(.wide))).font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
            }

            LazyVGrid(columns: columns, spacing: 9) {
                ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
                ForEach(0..<leadingWeekdayCount(), id: \.self) { _ in Color.clear.frame(height: 34) }
                ForEach(daysInMonth(), id: \.self) { date in
                    Button { state.select(date) } label: {
                        VStack(spacing: 1) {
                            Text("\(Calendar.current.component(.day, from: date))")
                            if let counts = summary[date], counts.done > 0 || counts.missed > 0 {
                                HStack(spacing: 2) { if counts.done > 0 { Circle().fill(.green).frame(width: 4, height: 4) }; if counts.missed > 0 { Circle().fill(.red).frame(width: 4, height: 4) } }
                            } else { Color.clear.frame(height: 4) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Calendar.current.isDate(date, inSameDayAs: state.selectedDate) ? Color.accentColor : Color.clear)
                        .foregroundStyle(Calendar.current.isDate(date, inSameDayAs: state.selectedDate) ? .white : .primary)
                        .clipShape(Circle())
                    }
                }
            }
        }
    }

    private func daysInMonth() -> [Date] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let dates = range.compactMap { calendar.date(bySetting: .day, value: $0, of: month) }
        return dates
    }

    private func leadingWeekdayCount() -> Int { Calendar.current.component(.weekday, from: month) - 1 }

    private func shiftMonth(_ value: Int) { month = Calendar.current.date(byAdding: .month, value: value, to: month) ?? month }
}

private struct StatisticsView: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        NavigationStack {
            List(state.statistics) { item in
                NavigationLink { StreakDetail(statistics: item) } label: { VStack(alignment: .leading) { Text(item.habit.name); Text("Current streak: \(item.currentStreak) · Notes: \(item.noteCount)").font(.caption).foregroundStyle(.secondary) } }
            }.navigationTitle("Stats")
        }
    }
}

private struct StreakDetail: View {
    let statistics: HabitStatistics
    var body: some View { List { Section("Summary") { LabeledContent("Current streak", value: "\(statistics.currentStreak)"); LabeledContent("Longest streak", value: "\(statistics.longestStreak?.length ?? 0)"); LabeledContent("Notes", value: "\(statistics.noteCount)") }; Section("Streak history") { ForEach(statistics.streaks) { streak in Text("\(streak.length) days · \(streak.startDate.formatted(date: .abbreviated, time: .omitted)) – \(streak.endDate.formatted(date: .abbreviated, time: .omitted))") } } }.navigationTitle(statistics.habit.name) }
}

private struct MoreView: View {
    @EnvironmentObject private var state: AppState
    @State private var importing = false
    var body: some View {
        NavigationStack {
            List {
                Section("Review") { NavigationLink("Unresolved dates") { NotificationsView() }; NavigationLink("Notes") { NotesView() } }
                Section("Data") { Button("Import terminal database") { importing = true } }
                Section("Coming next") { Label("Habit management and archive", systemImage: "archivebox").foregroundStyle(.secondary); Label("Challenges", systemImage: "flag").foregroundStyle(.secondary); Label("Backup and restore", systemImage: "externaldrive").foregroundStyle(.secondary) }
            }.navigationTitle("More")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
                guard case let .success(url) = result else { return }
                let granted = url.startAccessingSecurityScopedResource(); defer { if granted { url.stopAccessingSecurityScopedResource() } }
                state.importDatabase(from: url)
            }
        }
    }
}

private struct NotificationsView: View { @EnvironmentObject private var state: AppState; var body: some View { List(state.notifications) { notification in Button { state.select(notification.day) } label: { Text("\(notification.day.formatted(date: .abbreviated, time: .omitted)): \(notification.pendingCount) pending") } }.navigationTitle("Unresolved dates") } }
private struct NotesView: View { @EnvironmentObject private var state: AppState; var body: some View { List(state.notes) { note in VStack(alignment: .leading) { Text(note.habitName).font(.headline); Text(note.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary); Text(note.body).lineLimit(2) } }.navigationTitle("Notes") } }

private struct AddHabitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var startDate: Date
    let save: (String, Date) -> Void
    init(defaultDate: Date, save: @escaping (String, Date) -> Void) { _startDate = State(initialValue: defaultDate); self.save = save }
    var body: some View { NavigationStack { Form { TextField("Habit name", text: $name); DatePicker("Start date", selection: $startDate, displayedComponents: .date) }.navigationTitle("New habit").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Add") { save(name, startDate) }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } } } }
}

private struct NoteEditor: View {
    @Environment(\.dismiss) private var dismiss
    let habit: Habit; let date: Date; @State private var noteText: String; let save: (String, Habit) -> Void
    init(habit: Habit, date: Date, body: String, save: @escaping (String, Habit) -> Void) { self.habit = habit; self.date = date; _noteText = State(initialValue: body); self.save = save }
    var body: some View { NavigationStack { TextEditor(text: $noteText).padding().navigationTitle(habit.name).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Save") { save(noteText, habit) } } } } }
}
