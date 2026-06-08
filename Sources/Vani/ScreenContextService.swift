import AppKit
import ApplicationServices
import CoreGraphics
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
    /// Result of a capture: the context text plus which source produced the body
    /// (so Diagnostics can show whether OCR actually ran).
    struct Capture: Sendable {
        var text: String
        /// "none", "accessibility", "accessibility (chrome only)", or "ocr".
        var source: String
    }

    /// Build a context string for the frontmost window.
    /// `maxChars` caps the payload sent to the provider.
    static func capture(useOCR: Bool, maxChars: Int = 1500) async -> Capture {
        guard AXIsProcessTrusted() else { return Capture(text: "", source: "none (no accessibility)") }

        let app = await MainActor.run { NSWorkspace.shared.frontmostApplication }
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return Capture(text: "", source: "none")
        }
        let appName = app.localizedName ?? "Unknown app"
        let bundleID = app.bundleIdentifier ?? ""

        var header = "Application: \(appName)"
        var title: String?
        var body = ""
        var source = "none"

        if let (t, axText) = axWindowText(pid: app.processIdentifier, budget: maxChars) {
            title = t
            if let t, !t.isEmpty { header += "\nWindow: \(t)" }
            body = dedupeLines(axText)
            source = body.isEmpty ? "none" : "accessibility"
        }

        // How much *useful* text did AX give us (excluding the window title / app chrome)?
        let meaningful = meaningfulCount(body, title: title, appName: appName)
        if meaningful < 120, source == "accessibility" { source = "accessibility (chrome only)" }

        // Chromium browsers (Chrome/Brave/Edge/Arc/…) almost never expose page content via
        // AX — only chrome. So when OCR is on, prefer it for them rather than trusting AX.
        // Other apps OCR only as a fallback when AX came back thin.
        let shouldOCR = useOCR && (isChromiumBrowser(bundleID) || meaningful < 120)
        if shouldOCR {
            // Distinguish "no permission" from "permission OK but capture/OCR found nothing"
            // so the diagnostic is truthful instead of always blaming permissions.
            if !CGPreflightScreenCaptureAccess() {
                let note = "ocr blocked — Screen Recording not granted to THIS build"
                source = body.isEmpty ? note : source + " · " + note
            } else {
                let result = await ocrActiveWindow(maxChars: maxChars)
                if let ocr = result.text, !ocr.isEmpty {
                    body = dedupeLines(ocr)
                    source = "ocr"
                } else {
                    let note = "ocr: \(result.reason)"
                    source = body.isEmpty ? note : source + " · " + note
                }
            }
        }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return Capture(text: header, source: source) }
        return Capture(text: header + "\n\nVisible text:\n" + String(trimmed.prefix(maxChars)), source: source)
    }

    /// Chromium-family browsers whose AX trees expose only chrome, not page content.
    private static func isChromiumBrowser(_ bundleID: String) -> Bool {
        let ids: Set<String> = [
            "com.google.Chrome", "com.google.Chrome.canary", "com.google.Chrome.beta",
            "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly",
            "com.microsoft.edgemac", "com.microsoft.edgemac.Beta",
            "company.thebrowser.Browser",      // Arc
            "com.vivaldi.Vivaldi", "com.operasoftware.Opera", "com.operasoftware.OperaGX",
        ]
        return ids.contains(bundleID)
    }

    /// Collapse repeated/blank lines (browser chrome spams the same tab title many times).
    private static func dedupeLines(_ text: String) -> String {
        var seen = Set<String>()
        var out: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.count > 1 else { continue }
            let key = line.lowercased()
            if seen.insert(key).inserted { out.append(line) }
        }
        return out.joined(separator: "\n")
    }

    /// Chars of body that aren't just the window title or the app name repeated.
    private static func meaningfulCount(_ body: String, title: String?, appName: String) -> Int {
        let titleN = (title ?? "").lowercased()
        let appN = appName.lowercased()
        return body.split(separator: "\n").reduce(0) { sum, raw in
            let l = raw.trimmingCharacters(in: .whitespaces).lowercased()
            if l.isEmpty || l == titleN || l.contains(appN) || titleN.contains(l) { return sum }
            return sum + l.count
        }
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

    /// Returns (recognized text or nil, reason for the diagnostic).
    private static func ocrActiveWindow(maxChars: Int) async -> (text: String?, reason: String) {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let frontPID = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
            guard let frontPID else { return (nil, "no frontmost app") }

            // Find the frontmost app's largest on-screen window, then capture the WHOLE
            // DISPLAY it sits on. Single-window capture returns a blank/chrome-only frame
            // for GPU-rendered (Chromium) content; full-display capture is reliable.
            let appWindows = content.windows.filter {
                $0.owningApplication?.processID == frontPID && $0.isOnScreen
                    && $0.frame.width * $0.frame.height > 10_000
            }
            guard let window = appWindows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
            else { return (nil, "no on-screen window for the app") }

            let display = content.displays.first(where: { $0.frame.intersects(window.frame) })
                ?? content.displays.first
            guard let display else { return (nil, "no display") }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width * 2
            config.height = display.height * 2
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

            if let text = await recognizeText(in: cgImage, maxChars: maxChars), !text.isEmpty {
                return (text, "ok")
            }
            return (nil, "captured \(cgImage.width)x\(cgImage.height) but no text recognized")
        } catch {
            return (nil, "capture error: \(error.localizedDescription)")
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
