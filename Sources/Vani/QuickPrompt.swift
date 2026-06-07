import AppKit

/// A tiny modal text prompt (used for "Teach a word" / "Correct last result").
@MainActor
enum QuickPrompt {
    static func text(title: String, message: String, prefill: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: prefill)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        field.lineBreakMode = .byTruncatingTail
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
