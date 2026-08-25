import SwiftUI

@main
struct iHabitTrackerApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .alert("iHabitTracker", isPresented: Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })) {
                    Button("OK", role: .cancel) { state.errorMessage = nil }
                } message: {
                    Text(state.errorMessage ?? "")
                }
                .ignoresSafeArea(.keyboard)
        }
    }
}
