import SwiftUI
import AppKit
import CoreGraphics

/// Human-readable symbols for a modifier combo, e.g. ⌃⌥.
func modifierSymbols(_ flags: CGEventFlags) -> String {
    var s = ""
    if flags.contains(.maskSecondaryFn) { s += "fn" }
    if flags.contains(.maskControl) { s += "⌃" }
    if flags.contains(.maskAlternate) { s += "⌥" }
    if flags.contains(.maskShift) { s += "⇧" }
    if flags.contains(.maskCommand) { s += "⌘" }
    return s.isEmpty ? "—" : s
}

/// Records a held modifier combo (hold-to-talk). User presses & holds the modifiers,
/// then releases; the union is captured. Modifier-only by design.
struct ShortcutRecorder: View {
    @Binding var flagsRaw: Int
    @State private var recording = false
    @State private var monitor: Any?
    @State private var captured: CGEventFlags = []

    var body: some View {
        HStack(spacing: 10) {
            Text(recording
                 ? (captured.isEmpty ? "Hold modifiers… then release" : modifierSymbols(captured))
                 : "Combo: \(modifierSymbols(CGEventFlags(rawValue: UInt64(flagsRaw))))")
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 160, alignment: .leading)
                .foregroundStyle(recording ? .secondary : .primary)
            Button(recording ? "Cancel" : "Record") {
                recording ? stop() : start()
            }
        }
    }

    private func start() {
        captured = []
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let ns = event.modifierFlags
            var cg: CGEventFlags = []
            // Fn excluded on purpose — unreliable across external keyboards.
            if ns.contains(.command) { cg.insert(.maskCommand) }
            if ns.contains(.option) { cg.insert(.maskAlternate) }
            if ns.contains(.control) { cg.insert(.maskControl) }
            if ns.contains(.shift) { cg.insert(.maskShift) }

            if cg.isEmpty {
                finalize() // all released → done
            } else {
                captured.formUnion(cg)
            }
            return event
        }
    }

    private func finalize() {
        if !captured.isEmpty { flagsRaw = Int(captured.rawValue) }
        stop()
    }

    private func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        recording = false
    }
}
