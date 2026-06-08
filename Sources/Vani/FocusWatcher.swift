import AppKit
import ApplicationServices

/// Polls the system-wide focused UI element. When the user is in a text field in any
/// app (and Vani is idle), it shows the "Hold ⌥ to talk" prompt — like Wispr Flow.
@MainActor
final class FocusWatcher {
    static let shared = FocusWatcher()
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in FocusWatcher.shared.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        // Only prompt when idle and the indicator is enabled.
        guard SettingsStore.shared.showFloatingIndicator,
              SettingsStore.shared.showHoldPrompt,
              AppState.shared.status == .idle,
              !AnswerHUDController.shared.isVisible else {  // don't overlap an answer card
            HUDController.shared.setIdlePrompt(false)
            return
        }
        HUDController.shared.setIdlePrompt(isTextInputFocused())
    }

    /// True when the system-wide focused element looks like an editable text control.
    private func isTextInputFocused() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let system = AXUIElementCreateSystemWide()

        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let raw = focused else { return false }
        let element = raw as! AXUIElement

        var roleRef: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        let textRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            "AXSecureTextField",
        ]
        if textRoles.contains(role) { return true }

        // Fallback: an element whose value is settable text (covers some web/Electron fields).
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue, role.contains("Text") {
            return true
        }
        return false
    }
}
