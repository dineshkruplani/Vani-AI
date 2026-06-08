import SwiftUI
import AppKit

@main
struct VaniApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var state = AppState.shared
    @AppStorage("showMenuBarIcon") private var menuBarVisible = true

    var body: some Scene {
        MenuBarExtra(isInserted: $menuBarVisible) {
            MenuContent()
        } label: {
            Image(nsImage: state.menuBarImage)
        }

        Window("Vani Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }
}

/// Applies appearance/dock prefs and kicks off permission setup.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Appearance.apply(SettingsStore.shared.appTheme)
        Startup.applyDockPolicy(showInDock: SettingsStore.shared.showInDock)
        Fonts.registerBundled()
        Task { await AppState.shared.bootstrap() }
        if !SettingsStore.shared.onboardingCompleted {
            OnboardingWindowController.shared.show()
        }
    }

    // Vani lives in the menu bar — closing the Settings (or onboarding) window must
    // NOT quit the app. Without this, macOS terminates on last-window-close.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
