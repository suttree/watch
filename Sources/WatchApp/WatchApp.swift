import SwiftUI

@main
struct WatchApp: App {
    @StateObject private var model = WatchAppModel()

    init() {
        AppIconTheming.applyStoredSelection()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 760, minHeight: 560)
        }
        .commands {
            // Replacing rather than adding, so ⌘, lands on the app's own
            // settings sheet and macOS doesn't also offer an empty Settings
            // item of its own in the app menu.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    model.isShowingSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(!model.isUnlocked || model.isLockedByInactivity)
            }

        }
    }
}

struct ContentView: View {
    @ObservedObject var model: WatchAppModel

    var body: some View {
        Group {
            if model.isUnlocked, !model.isLockedByInactivity {
                navigation
                    .overlay {
                        if model.isRefreshing, !model.hasSkippedRefreshScreen {
                            RefreshScreen(
                                status: model.refreshStatus,
                                progress: model.refreshProgress,
                                skip: { model.hasSkippedRefreshScreen = true }
                            )
                            .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.35), value: model.isRefreshing)
            } else {
                UnlockView(
                    isCreatingPassword: !model.hasStoredPassword,
                    isUnlocking: model.isUnlocking,
                    errorMessage: model.passwordErrorMessage,
                    unlock: model.isLockedByInactivity ? model.unlockFromInactivityLock : model.unlock
                )
            }
        }
        .environment(\.readerTheme, model.theme)
    }

    private var navigation: some View {
        NavigationStack {
            HomepageView(model: model)
        }
    }
}
