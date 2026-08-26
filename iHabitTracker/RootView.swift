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
        case .statistics: StatisticsView()
        case .more: MoreView()
        }
    }
}

private enum AppTab: CaseIterable, Identifiable {
    case today, statistics, more

    var id: Self { self }
    var title: String {
        switch self { case .today: "Today"; case .statistics: "Stats"; case .more: "More" }
    }
    var symbol: String {
        switch self { case .today: "checkmark.circle.fill"; case .statistics: "chart.line.uptrend.xyaxis"; case .more: "ellipsis.circle" }
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
                    .font(.system(size: 27, weight: .medium))
                Text(tab.title)
                    .font(.caption)
            }
            .fontWeight(isSelected ? .semibold : .regular)
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity, minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TodayView: View {
    @EnvironmentObject private var state: AppState
    @State private var showingAddHabit = false
    @State private var showingCalendar = false
    @State private var noteHabit: Habit?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DayNavigationHeader(
                title: dayTitle,
                previousDay: { selectDay(offset: -1) },
                nextDay: { selectDay(offset: 1) },
                showCalendar: { showingCalendar = true }
            )

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
        .sheet(isPresented: $showingCalendar) {
            CalendarView(selectedDate: state.selectedDate) { date in
                state.select(date)
                showingCalendar = false
            }
        }
        .sheet(item: $noteHabit) { NoteEditor(habit: $0, date: state.selectedDate, body: state.note(for: $0.id)) { state.saveNote($0, for: $1.id); noteHabit = nil } }
    }

    private var dayTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(state.selectedDate) { return "Today" }
        if calendar.isDateInYesterday(state.selectedDate) { return "Yesterday" }
        if calendar.isDateInTomorrow(state.selectedDate) { return "Tomorrow" }
        return state.selectedDate.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func selectDay(offset: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: offset, to: state.selectedDate) else { return }
        state.select(date)
    }
}

private struct DayNavigationHeader: View {
    let title: String
    let previousDay: () -> Void
    let nextDay: () -> Void
    let showCalendar: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: previousDay) {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel("Previous day")

            Button(action: showCalendar) {
                Text(title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .accessibilityLabel("Show calendar")

            Button(action: nextDay) {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel("Next day")
        }
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
    @State private var month: Date
    let selectDate: (Date) -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private var calendar: Calendar { Calendar.current }

    init(selectedDate: Date, selectDate: @escaping (Date) -> Void) {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)) ?? calendar.startOfDay(for: selectedDate)
        _month = State(initialValue: monthStart)
        self.selectDate = selectDate
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let summary = state.monthSummary(for: month)

                ScrollView {
                    VStack {
                        calendarGrid(summary: summary)
                            // Center the calendar within the sheet's usable area.
                            .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: state.selectedDate) { _, date in
                if !calendar.isDate(date, equalTo: month, toGranularity: .month) {
                    month = startOfMonth(for: date)
                }
            }
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
                ForEach(calendar.shortWeekdaySymbols, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
                ForEach(0..<leadingWeekdayCount(), id: \.self) { _ in Color.clear.frame(height: 34) }
                ForEach(daysInMonth(), id: \.self) { date in
                    Button { selectDate(date) } label: {
                        VStack(spacing: 1) {
                            Text("\(calendar.component(.day, from: date))")
                            if let counts = summary[date], counts.done > 0 || counts.missed > 0 {
                                HStack(spacing: 2) { if counts.done > 0 { Circle().fill(.green).frame(width: 4, height: 4) }; if counts.missed > 0 { Circle().fill(.red).frame(width: 4, height: 4) } }
                            } else { Color.clear.frame(height: 4) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(highlight(for: date))
                        .foregroundStyle(foreground(for: date))
                        .clipShape(Circle())
                    }
                }
            }
        }
    }

    private func daysInMonth() -> [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        return range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
    }

    private func leadingWeekdayCount() -> Int { calendar.component(.weekday, from: month) - 1 }

    private func shiftMonth(_ value: Int) {
        guard let shifted = calendar.date(byAdding: .month, value: value, to: month) else { return }
        month = startOfMonth(for: shifted)
    }

    private func startOfMonth(for date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    private func highlight(for date: Date) -> Color {
        if calendar.isDateInToday(date) { return Color.accentColor.opacity(0.35) }
        if calendar.isDate(date, inSameDayAs: state.selectedDate) { return Color.gray.opacity(0.3) }
        return .clear
    }

    private func foreground(for date: Date) -> Color {
        calendar.isDateInToday(date) ? Color.accentColor : .primary
    }
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
