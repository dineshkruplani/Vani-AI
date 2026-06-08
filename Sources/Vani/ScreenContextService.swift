import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision

/// Captures what the user is currently looking at, to give the cleanup/command LLM
/// context (so it spells on-screen names right, matches surrounding style, etc.).
///
/// Two tiers, cheapest first:
///  1. **Accessibility** (default): the frontmost app name + window title + visible
///     text read from the AX tree. No extra permission beyond the one we already use.
///  2. **Screen OCR** (opt-in): ScreenCaptureKit screenshot of the active window +
///     Vision OCR, for apps the AX tree can't read (some Electron/web). Needs the
///     Screen Recording permission.
enum ScreenContextService {
    /// Build a context string for the frontmost window. Returns "" if nothing usable.
    /// `maxChars` caps the payload sent to the provider.
    static func capture(useOCR: Bool, maxChars: Int = 1500) async -> String {
        guard AXIsProcessTrusted() else { return "" }

        let app = await MainActor.run { NSWorkspace.shared.frontmostApplication }
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return "" }
        let appName = app.localizedName ?? "Unknown app"

        var header = "Application: \(appName)"
        var body = ""

        if let (title, axText) = axWindowText(pid: app.processIdentifier, budget: maxChars) {
            if let title, !title.isEmpty { header += "\nWindow: \(title)" }
            body = axText
        }

        // Fall back to OCR when AX gave us little/nothing and the user opted in.
        if body.count < 40, useOCR {
            if let ocr = await ocrActiveWindow(maxChars: maxChars), !ocr.isEmpty {
                body = ocr
            }
        }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return header }     // at least the app/window name is useful
        return header + "\n\nVisible text:\n" + String(trimmed.prefix(maxChars))
    }

    // MARK: - Accessibility tier

    /// (window title, concatenated visible text) for the app's focused window.
    private static func axWindowText(pid: pid_t, budget: Int) -> (String?, String)? {
        let appElement = AXUIElementCreateApplication(pid)

        var focused: CFTypeRef?
        var window: AXUIElement?
        if AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focused) == .success,
           let w = focused {
            window = (w as! AXUIElement)
        } else {
            var main: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &main) == .success,
               let w = main {
                window = (w as! AXUIElement)
            }
        }
        guard let window else { return nil }

        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
        let title = titleRef as? String

        var remaining = budget
        var seen = 0
        let text = collectText(window, budget: &remaining, nodeBudget: &seen, depth: 0)
        return (title, text)
    }

    /// Depth/size-bounded walk of the AX subtree collecting human-readable strings.
    private static func collectText(_ element: AXUIElement, budget: inout Int,
                                    nodeBudget: inout Int, depth: Int) -> String {
        if budget <= 0 || depth > 14 || nodeBudget > 1500 { return "" }
        nodeBudget += 1
        var parts: [String] = []

        for attr in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            var ref: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attr as CFString, &ref) == .success,
               let s = ref as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.count > 1 {
                    parts.append(t)
                    budget -= t.count
                }
            }
        }

        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for child in children {
                if budget <= 0 || nodeBudget > 1500 { break }
                let c = collectText(child, budget: &budget, nodeBudget: &nodeBudget, depth: depth + 1)
                if !c.isEmpty { parts.append(c) }
            }
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - OCR tier (opt-in)

    private static func ocrActiveWindow(maxChars: Int) async -> String? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let myPID = ProcessInfo.processInfo.processIdentifier
            let frontPID = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
            guard let window = content.windows.first(where: {
                $0.owningApplication?.processID == frontPID &&
                $0.owningApplication?.processID != myPID &&
                $0.windowLayer == 0 && $0.isOnScreen
            }) else { return nil }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width) * 2
            config.height = Int(window.frame.height) * 2
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return await recognizeText(in: cgImage, maxChars: maxChars)
        } catch {
            return nil
        }
    }

    private static func recognizeText(in cgImage: CGImage, maxChars: Int) async -> String? {
        await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                let text = (request.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                return text.isEmpty ? nil : String(text.prefix(maxChars))
            } catch {
                return nil
            }
        }.value
    }
}
