import AppKit

/// Inserts text at the current cursor location in whatever app is focused,
/// by writing to the pasteboard and synthesizing ⌘V, then restoring the clipboard.
@MainActor
enum TextInserter {
    static func insert(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general

        // Save whatever the user had on the clipboard.
        let saved = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Give the pasteboard a beat to settle before sending ⌘V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            synthesizePaste()
        }

        // Restore the original clipboard after the paste has had time to land.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            pasteboard.clearContents()
            if let saved { pasteboard.setString(saved, forType: .string) }
        }
    }

    /// Whether the app can post synthetic key events (Accessibility permission).
    static var canSynthesizeKeys: Bool {
        AXIsProcessTrusted()
    }

    private static func synthesizePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9 // 'v'
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
