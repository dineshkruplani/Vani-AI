import SwiftUI

/// The dropdown shown from the menu-bar icon.
struct MenuContent: View {
    @ObservedObject private var state = AppState.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(state.statusText)
            .font(.caption)

        if !state.accessibilityGranted || !state.hotkeyInstalled {
            Divider()
            Text("⚠️ Accessibility not active — hotkeys & paste won't work")
                .font(.caption2)
            Button("Open Accessibility Settings…") {
                state.openAccessibilitySettings()
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        Divider()

        Button(state.isRecording ? "Stop & Insert" : "Test Dictation") {
            state.toggleDictation()
        }

        Button("Teach a Word…") { state.teachWord() }
        Button("Correct Last Result…") { state.correctLast() }
            .disabled(state.lastInserted.isEmpty)

        if !state.lastInserted.isEmpty {
            Divider()
            Text("Last: \(snippet(state.lastInserted))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        Divider()

        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: .command)

        Button("Setup Guide…") {
            OnboardingWindowController.shared.show()
        }

        Button("Quit Vani") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private func snippet(_ text: String) -> String {
        text.count > 50 ? String(text.prefix(50)) + "…" : text
    }
}
