import SwiftUI
import AppKit
import ServiceManagement

enum AppTheme: String, CaseIterable, Identifiable {
    case light, dark, auto
    var id: String { rawValue }
    var label: String {
        switch self { case .light: return "Light"; case .dark: return "Dark"; case .auto: return "Auto" }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .auto: return nil
        }
    }
}

@MainActor
enum Appearance {
    static func apply(_ theme: AppTheme) { NSApp.appearance = theme.nsAppearance }
}

/// Login item (SMAppService) + Dock visibility.
@MainActor
enum Startup {
    static var isLoginItemEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setLoginItem(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
        } catch {
            // Reflect actual status in the UI; ignore the error here.
        }
    }

    static func applyDockPolicy(showInDock: Bool) {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }
}
