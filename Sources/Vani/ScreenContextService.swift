import AppKit
import ApplicationServices
import CoreGraphics
import FlowCore
import ScreenCaptureKit

/// Captures what the user is currently looking at, to give the cleanup/command LLM
/// context (so it spells on-screen names right, matches surrounding style, etc.).
///
/// Two tiers:
///  1. **Accessibility** (default): frontmost app + window title + visible text from
///     the AX tree. Free, local, no extra permission.
///  2. **AI Vision** (opt-in): screenshots the active window, downscales it, and sends
///     it to a vision model (gpt-4o-mini via OpenRouter) which returns distilled,
///     structured context. Runs while the user is dictating, so its latency is hidden.
///     Results are cached per window for 60s. Needs Screen Recording permission.
enum ScreenContextService {
    struct Capture: Sendable {
        var text: String
        /// e.g. "accessibility", "vision", "vision (cached)", "vision failed: …".
        var source: String
    }

    private static let cache = VisionCache()

    /// Build context for the frontmost window. `visionEnabled` + an OpenRouter key turn
    /// on the vision tier; otherwise the AX tier is used.
    static func capture(visionEnabled: Bool, openRouterKey: String,
                        visionModel: String, maxChars: Int = 1500) async -> Capture {
        guard AXIsProcessTrusted() else { return Capture(text: "", source: "none (no accessibility)") }

        let app = await MainActor.run { NSWorkspace.shared.frontmostApplication }
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return Capture(text: "", source: "none")
        }
        let appName = app.localizedName ?? "Unknown app"
        let bundleID = app.bundleIdentifier ?? ""

        // AX is always read — cheap, and the window title doubles as the vision cache key.
        var header = "Application: \(appName)"
        var title: String?
        var axBody = ""
        if let (t, axText) = axWindowText(pid: app.processIdentifier, budget: maxChars) {
            title = t
            if let t, !t.isEmpty { header += "\nWindow: \(t)" }
            axBody = dedupeLines(axText)
        }

        guard visionEnabled, !openRouterKey.isEmpty else {
            return axCapture(header: header, axBody: axBody, extra: nil, maxChars: maxChars)
        }

        // --- Vision tier ---
        guard CGPreflightScreenCaptureAccess() else {
            return axCapture(header: header, axBody: axBody,
                             extra: "vision blocked — Screen Recording not granted to THIS build",
                             maxChars: maxChars)
        }

        let cacheKey = "\(bundleID)|\(title ?? "")"
        if let cached = await cache.get(cacheKey, ttl: 60) {
            return Capture(text: cached, source: "vision (cached)")
        }

        guard let jpeg = await captureActiveWindowJPEG() else {
            return axCapture(header: header, axBody: axBody,
                             extra: "vision failed: no screenshot", maxChars: maxChars)
        }
        do {
            let provider = VisionContextProvider(apiKey: openRouterKey, model: visionModel)
            let insight = try await provider.extract(imageJPEG: jpeg, appName: appName, fieldHint: title ?? "")
            guard !insight.isEmpty else {
                return axCapture(header: header, axBody: axBody,
                                 extra: "vision returned empty", maxChars: maxChars)
            }
            let text = formatInsight(insight, header: header)
            await cache.set(cacheKey, text)
            return Capture(text: text, source: "vision")
        } catch {
            return axCapture(header: header, axBody: axBody,
                             extra: "vision failed: \(shortError(error))", maxChars: maxChars)
        }
    }

    // MARK: - Formatting

    private static func axCapture(header: String, axBody: String, extra: String?, maxChars: Int) -> Capture {
        let trimmed = axBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.isEmpty ? header : header + "\n\nVisible text:\n" + String(trimmed.prefix(maxChars))
        let base = trimmed.isEmpty ? "accessibility (title only)" : "accessibility"
        return Capture(text: text, source: extra == nil ? base : "\(base) · \(extra!)")
    }

    private static func formatInsight(_ i: ScreenInsight, header: String) -> String {
        var lines = [header]
        if let s = i.summary, !s.isEmpty { lines.append("On screen: \(s)") }
        if let r = i.replyingTo, !r.isEmpty { lines.append("Replying to: \(r)") }
        if let f = i.focusedField, !f.isEmpty { lines.append("Cursor is in: \(f)") }
        if let n = i.names, !n.isEmpty { lines.append("Names/terms: \(n.joined(separator: ", "))") }
        if let t = i.tone, !t.isEmpty { lines.append("Suggested tone: \(t)") }
        return lines.joined(separator: "\n")
    }

    private static func shortError(_ error: Error) -> String {
        String(String(describing: (error as? FlowError) ?? error).prefix(80))
    }

    // MARK: - Screenshot (crop active window, downscale, JPEG)

    private static func captureActiveWindowJPEG(maxWidth: CGFloat = 1280, quality: CGFloat = 0.6) async -> Data? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let frontPID = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
            guard let frontPID else { return nil }

            // Capture the whole DISPLAY (single-window capture is blank for Chromium),
            // cropped via sourceRect to the active window's region.
            let appWindows = content.windows.filter {
                $0.owningApplication?.processID == frontPID && $0.isOnScreen
                    && $0.frame.width * $0.frame.height > 10_000
            }
            guard let window = appWindows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
                  let display = content.displays.first(where: { $0.frame.intersects(window.frame) }) ?? content.displays.first
            else { return nil }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.sourceRect = CGRect(x: window.frame.minX - display.frame.minX,
                                       y: window.frame.minY - display.frame.minY,
                                       width: window.frame.width, height: window.frame.height)
            config.width = Int(window.frame.width * 2)
            config.height = Int(window.frame.height * 2)
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return jpeg(downscale(cgImage, maxWidth: maxWidth), quality: quality)
        } catch {
            return nil
        }
    }

    private static func downscale(_ cg: CGImage, maxWidth: CGFloat) -> CGImage {
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        guard w > maxWidth else { return cg }
        let scale = maxWidth / w
        let tw = Int(w * scale), th = Int(h * scale)
        guard let ctx = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cg }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: tw, height: th))
        return ctx.makeImage() ?? cg
    }

    private static func jpeg(_ cg: CGImage, quality: CGFloat) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    // MARK: - Accessibility tier

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
                if t.count > 1 { parts.append(t); budget -= t.count }
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

    private static func dedupeLines(_ text: String) -> String {
        var seen = Set<String>()
        var out: [String] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.count > 1 else { continue }
            if seen.insert(line.lowercased()).inserted { out.append(line) }
        }
        return out.joined(separator: "\n")
    }
}

/// 60s per-window cache of distilled vision context (the expensive part). Thread-safe.
private actor VisionCache {
    private var store: [String: (text: String, at: Date)] = [:]

    func get(_ key: String, ttl: TimeInterval) -> String? {
        guard let entry = store[key], Date().timeIntervalSince(entry.at) < ttl else { return nil }
        return entry.text
    }

    func set(_ key: String, _ text: String) {
        store[key] = (text, Date())
        if store.count > 16 { // bound memory: drop the oldest
            if let oldest = store.min(by: { $0.value.at < $1.value.at })?.key { store[oldest] = nil }
        }
    }
}
