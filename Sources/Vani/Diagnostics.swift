import AppKit

/// Local-only diagnostics for the dictation pipeline — keeps the last few captures in
/// memory (and can dump them to a file) so you can see exactly what screen context was
/// captured and whether a context leak was stripped. Nothing is ever sent anywhere.
@MainActor
final class Diagnostics: ObservableObject {
    static let shared = Diagnostics()

    struct Entry: Identifiable {
        let id = UUID()
        let when: Date
        let app: String
        let mode: String
        let transcript: String
        let contextChars: Int
        let contextSource: String
        let contextPreview: String
        let output: String
        let leakStripped: Bool
        let ms: Int

        var formatted: String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return """
            [\(f.string(from: when))]  \(mode.uppercased())  app=\(app)  \(ms)ms\(leakStripped ? "  ⚠️ context-leak stripped" : "")
            transcript: \(transcript)
            screen-context: \(contextChars) chars · source: \(contextSource)
            context-preview: \(contextPreview)
            output: \(output)
            """
        }
    }

    @Published private(set) var entries: [Entry] = []

    func record(app: String, mode: String, transcript: String, context: String,
                contextSource: String, output: String, leakStripped: Bool, ms: Int) {
        let preview = String(context.replacingOccurrences(of: "\n", with: " ").prefix(220))
        let entry = Entry(when: Date(), app: app, mode: mode, transcript: transcript,
                          contextChars: context.count, contextSource: contextSource, contextPreview: preview,
                          output: output, leakStripped: leakStripped, ms: ms)
        entries.insert(entry, at: 0)
        if entries.count > 25 { entries.removeLast(entries.count - 25) }
    }

    /// All entries as text, newest first.
    var report: String {
        guard !entries.isEmpty else { return "No dictations recorded yet." }
        return entries.map(\.formatted).joined(separator: "\n\n———\n\n")
    }

    /// Copy the latest entry to the clipboard.
    func copyLatest() {
        guard let latest = entries.first else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(latest.formatted, forType: .string)
    }

    /// Write the full report to a temp file and reveal it in Finder.
    func revealLog() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Vani-diagnostics.txt")
        try? report.write(to: url, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
