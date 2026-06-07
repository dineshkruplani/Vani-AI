import AppKit
import CoreGraphics

/// A push-to-talk trigger key. Right-side modifiers are detected by keycode so they
/// don't clash with their left twins; Fn is detected by its flag.
enum HotkeyTrigger: String, CaseIterable, Identifiable {
    case fn
    case rightOption
    case rightCommand
    case rightControl
    case custom
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fn: return "Fn"
        case .rightOption: return "Right Option (⌥)"
        case .rightCommand: return "Right Command (⌘)"
        case .rightControl: return "Right Control (⌃)"
        case .custom: return "Custom combo…"
        case .off: return "Off"
        }
    }

    /// Keycode for right-side modifier keys (nil for Fn / off).
    fileprivate var keycode: Int64? {
        switch self {
        case .rightOption: return 61
        case .rightCommand: return 54
        case .rightControl: return 62
        case .fn, .custom, .off: return nil
        }
    }

    fileprivate var flag: CGEventFlags? {
        switch self {
        case .fn: return .maskSecondaryFn
        case .rightOption: return .maskAlternate
        case .rightCommand: return .maskCommand
        case .rightControl: return .maskControl
        case .custom, .off: return nil
        }
    }
}

/// Modifier bits used to match custom combos. Fn is deliberately excluded — it's
/// reported inconsistently across keyboards (many external keyboards set it spuriously).
let customMatchMask: CGEventFlags = [
    .maskCommand, .maskAlternate, .maskControl, .maskShift,
]

/// Global push-to-talk via a single `CGEventTap` on `flagsChanged`. Supports two
/// independent triggers (e.g. dictation + Command Mode). Requires Accessibility.
@MainActor
final class HotkeyManager {
    private final class Registration {
        let trigger: HotkeyTrigger
        let customFlags: CGEventFlags
        var isDown = false
        let onPress: () -> Void
        let onRelease: () -> Void
        init(_ t: HotkeyTrigger, customFlags: CGEventFlags,
             onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
            self.trigger = t; self.customFlags = customFlags
            self.onPress = onPress; self.onRelease = onRelease
        }
    }

    private var registrations: [Registration] = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Register a trigger. No-op if `.off`, or `.custom` with no modifiers chosen.
    func register(_ trigger: HotkeyTrigger,
                  customFlags: CGEventFlags = [],
                  onPress: @escaping () -> Void,
                  onRelease: @escaping () -> Void) {
        guard trigger != .off else { return }
        if trigger == .custom && customFlags.isEmpty { return }
        registrations.append(Registration(trigger, customFlags: customFlags,
                                          onPress: onPress, onRelease: onRelease))
    }

    func clearRegistrations() { registrations.removeAll() }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: hotkeyEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false // Accessibility not granted
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    fileprivate func handle(flags: CGEventFlags, keycode: Int64) {
        for reg in registrations {
            let active: Bool
            if reg.trigger == .custom {
                // Match on ⌘⌥⌃⇧ only — exclude Fn. Many external keyboards set the Fn
                // bit spuriously, which would otherwise break an exact match that works
                // on the built-in keyboard.
                let required = reg.customFlags.intersection(customMatchMask)
                active = !required.isEmpty && flags.intersection(customMatchMask) == required
            } else {
                guard let flag = reg.trigger.flag else { continue }
                // Keycode-based modifiers only react to their own key event; Fn reacts to any.
                if let kc = reg.trigger.keycode, kc != keycode { continue }
                active = flags.contains(flag)
            }
            if active && !reg.isDown {
                reg.isDown = true
                reg.onPress()
            } else if !active && reg.isDown {
                reg.isDown = false
                reg.onRelease()
            }
        }
    }
}

private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .flagsChanged, let refcon {
        let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
        let flags = event.flags
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        DispatchQueue.main.async { manager.handle(flags: flags, keycode: keycode) }
    }
    return Unmanaged.passUnretained(event)
}
