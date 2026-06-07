import SwiftUI
import AppKit

@main
struct VaniApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            Image(systemName: state.menuIcon)
        }

        Window("Vani Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }
}

/// Makes the app a menu-bar accessory (no Dock icon) and kicks off permission setup.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { await AppState.shared.bootstrap() }
        if !SettingsStore.shared.onboardingCompleted {
            OnboardingWindowController.shared.show()
        }
    }
}
