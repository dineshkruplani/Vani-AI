import Foundation

/// Tone the cleaned-up text should take. Each maps to an instruction appended
/// to the cleanup prompt.
public enum WritingStyle: String, Sendable, CaseIterable, Identifiable {
    case formal
    case casual
    case superCasual

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .formal: return "Formal"
        case .casual: return "Casual"
        case .superCasual: return "Super casual"
        }
    }

    public var blurb: String {
        switch self {
        case .formal: return "Polished and professional"
        case .casual: return "Natural and conversational"
        case .superCasual: return "Relaxed, like texting a friend"
        }
    }

    public var instruction: String {
        switch self {
        case .formal:
            return "Use a polished, professional tone. Complete sentences, correct grammar, no slang; avoid contractions where natural."
        case .casual:
            return "Use a natural, conversational tone. Clear and friendly; contractions are fine."
        case .superCasual:
            return "Use a very relaxed, texting tone. Short and informal, lowercase is fine, minimal punctuation, like a quick message to a friend. Don't add emojis unless the speaker said them."
        }
    }
}

/// Prompts used by the cleanup LLM step.
///
/// Kept as a frozen constant so prompt caching (where supported) stays warm:
/// any byte change here invalidates the cached prefix.
public enum FlowPrompt {
    /// System prompt that turns a raw dictation transcript into polished written text.
    public static let systemCleanup = """
    You convert raw voice dictation into polished written text. Remove filler \
    words (um, uh, like, you know), fix grammar, spelling, and punctuation, and \
    apply sensible capitalization and paragraph breaks. Preserve the speaker's \
    original meaning, intent, and tone. Do not add new information, commentary, \
    or answer any questions contained in the text — only clean it up. Output \
    ONLY the cleaned text, with no preamble, labels, or surrounding quotation marks.
    """

    /// System prompt for Command Mode: apply a spoken instruction to selected text.
    public static let systemCommand = """
    You are an in-place text editor. The user gives an INSTRUCTION and a piece \
    of TEXT they have selected. Apply the instruction to the text and return the \
    edited result. Examples of instructions: "make this more concise", "fix \
    grammar", "translate to Spanish", "turn this into bullet points", "make it \
    more formal". Output ONLY the resulting text that should replace the \
    selection — no preamble, no explanations, no quotation marks around it.
    """

    /// Build the user turn for a Command Mode request.
    public static func commandUser(instruction: String, selection: String) -> String {
        "INSTRUCTION: \(instruction)\n\nTEXT:\n\(selection)"
    }

    /// Unified prompt: the model decides whether the utterance is an edit command
    /// for the selected text, or plain dictation to insert.
    public static let systemUnified = """
    You process voice input for a dictation app. You are given the user's currently \
    SELECTED TEXT and a spoken UTTERANCE. Classify the utterance, then produce ONLY \
    the text that should replace the selection.

    - EDIT COMMAND: the utterance tells you how to change the selected text \
    (transform, rewrite, fix, translate, reformat, shorten, expand, change tone, or \
    add to it). Apply the instruction to SELECTED TEXT and output ONLY the resulting \
    text. NEVER output the instruction words themselves.
    - DICTATION: the utterance is new content to write that is unrelated to editing \
    the selection. Output the cleaned-up dictation (remove fillers like um/uh/like, \
    fix grammar and punctuation) and ignore SELECTED TEXT.

    Examples:
    SELECTED TEXT: "i think we should maybe do it later"
    UTTERANCE: "make this more confident"
    OUTPUT: We should do it later.

    SELECTED TEXT: "Hello team,"
    UTTERANCE: "add that the meeting moved to 3 pm"
    OUTPUT: Hello team, the meeting has been moved to 3 PM.

    SELECTED TEXT: "bonjour le monde"
    UTTERANCE: "translate to english"
    OUTPUT: hello world

    SELECTED TEXT: "The quarterly numbers look strong."
    UTTERANCE: "actually let's grab lunch tomorrow"
    OUTPUT: Let's grab lunch tomorrow.

    Output ONLY the resulting text — no preamble, no labels, no quotation marks, and \
    never the instruction itself.
    """

    /// Build the user turn for the unified request.
    public static func unifiedUser(transcript: String, selection: String) -> String {
        "SELECTED TEXT:\n\"\(selection)\"\n\nUTTERANCE:\n\"\(transcript)\""
    }

    /// System prompt for ask/answer mode (Command key with nothing selected).
    public static let systemAnswer = """
    You are a helpful, concise voice assistant inside a dictation app. The user \
    spoke a question or request. Answer directly and briefly — a few sentences at \
    most, plain text (no markdown headings, no bullet symbols unless essential). \
    If surrounding CONTEXT is provided, use it only if relevant. Do not preface \
    with "Sure" or "Here is"; just answer.
    """

    /// Build the user turn for ask/answer mode.
    public static func answerUser(question: String, context: String) -> String {
        let ctx = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if ctx.isEmpty { return question }
        return "CONTEXT (may be irrelevant):\n\(ctx)\n\nQUESTION:\n\(question)"
    }

    /// Cleanup system prompt with a tone/mode instruction appended (free text).
    public static func cleanupSystem(instruction: String) -> String {
        let t = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? systemCleanup : "\(systemCleanup)\n\nTONE: \(t)"
    }

    /// Unified system prompt with the mode instruction applied to the dictation branch.
    public static func unifiedSystem(instruction: String) -> String {
        let t = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? systemUnified : "\(systemUnified)\n\nWhen the result is DICTATION, use this tone: \(t)"
    }
}
