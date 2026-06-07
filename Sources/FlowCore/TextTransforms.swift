import Foundation

/// Post-processing transforms applied to produced text before insertion.
public enum TextTransforms {
    /// Apply literal text replacements/snippets (case-insensitive). Order matters:
    /// earlier pairs run first. Empty triggers are ignored.
    public static func applyReplacements(_ text: String, _ replacements: [(from: String, to: String)]) -> String {
        var result = text
        for pair in replacements {
            let from = pair.from.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !from.isEmpty else { continue }
            result = result.replacingOccurrences(of: from, with: pair.to, options: [.caseInsensitive])
        }
        return result
    }
}
