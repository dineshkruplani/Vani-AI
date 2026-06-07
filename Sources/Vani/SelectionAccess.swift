import AppKit
import ApplicationServices

/// Reads the currently selected text in the frontmost app for Command Mode.
/// Tries the Accessibility API first; falls back to synthesizing ⌘C and reading
/// the clipboard (then restoring it).
@MainActor
enum SelectionAccess {
    /// Returns the selected text, or nil if nothing is selected / unavailable.
    static func read() -> String? {
        if let viaAX = readViaAccessibility(), !viaAX.isEmpty { return viaAX }
        return readViaCopy()
    }

    /// Used on every press to decide command-vs-dictation routing.
    /// - If Accessibility gives a definitive answer (even ""), trust it — no clipboard touch.
    /// - Only when AX can't see the selection at all (nil, e.g. Chrome/Electron) do we fall
    ///   back to a clipboard-restoring ⌘C so Command Mode still works there.
    static func readForRouting() -> String {
        if let ax = readViaAccessibility() { return ax }
        return readViaCopy() ?? ""
    }

    /// Text immediately before the caret in the focused field (via Accessibility),
    /// used to prime transcription so it continues in-style and knows on-screen terms.
    /// Returns "" when the app doesn't expose it.
    static func contextBeforeCursor(maxChars: Int = 400) -> String {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return "" }
        let el = element as! AXUIElement

        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &valueRef) == .success,
              let text = valueRef as? String, !text.isEmpty else { return "" }

        let ns = text as NSString
        var caret = ns.length // default: end of text
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let rr = rangeRef {
            var r = CFRange()
            if AXValueGetValue(rr as! AXValue, .cfRange, &r) { caret = r.location }
        }

        let safe = max(0, min(caret, ns.length))
        let preceding = ns.substring(to: safe)
        return String(preceding.suffix(maxChars))
    }

    private static func readViaAccessibility() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let element = focused else { return nil }

        var selected: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element as! AXUIElement,
                                                   kAXSelectedTextAttribute as CFString, &selected)
        guard result == .success, let text = selected as? String else { return nil }
        return text
    }

    /// Fallback: copy the selection via ⌘C, read it, then restore the clipboard.
    private static func readViaCopy() -> String? {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        let beforeChange = pasteboard.changeCount

        synthesizeCopy()

        // Give the frontmost app a moment to service the copy.
        let deadline = Date().addingTimeInterval(0.5)
        while pasteboard.changeCount == beforeChange && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        let copied = pasteboard.string(forType: .string)
        // Restore the user's clipboard.
        pasteboard.clearContents()
        if let saved { pasteboard.setString(saved, forType: .string) }

        if let copied, copied != saved, !copied.isEmpty { return copied }
        return nil
    }

    private static func synthesizeCopy() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cKey: CGKeyCode = 8 // 'c'
        let down = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
