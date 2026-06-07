import Testing
import Foundation
@testable import FlowCore

/// A scripted HTTP transport: returns a queued response per request and records what it received.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Stub { let status: Int; let body: Data }
    private let lock = NSLock()
    private var stubs: [Stub]
    private var _requests: [URLRequest] = []

    init(_ stubs: [Stub]) { self.stubs = stubs }

    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _requests }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.lock()
        _requests.append(request)
        let stub = stubs.isEmpty ? Stub(status: 500, body: Data()) : stubs.removeFirst()
        lock.unlock()
        let http = HTTPURLResponse(url: request.url!, statusCode: stub.status,
                                   httpVersion: nil, headerFields: nil)!
        return (stub.body, http)
    }
}

private func json(_ s: String) -> Data { Data(s.utf8) }
// Stand-in audio file; the MockTransport ignores the body contents.
private let dummyAudio = URL(fileURLWithPath: #filePath)

// MARK: - OpenAI STT

@Test func sttParsesAndTrimsTranscript() async throws {
    let transport = MockTransport([.init(status: 200, body: json(#"{"text":"  hello world  "}"#))])
    let provider = OpenAISTTProvider(config: .openAISTT(apiKey: "sk-test"), transport: transport)

    let text = try await provider.transcribe(audioFileURL: dummyAudio)
    #expect(text == "hello world")

    let req = transport.requests.first
    #expect(req?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
    #expect(req?.url?.absoluteString == "https://api.openai.com/v1/audio/transcriptions")
}

@Test func sttEmptyTranscriptThrows() async {
    let transport = MockTransport([.init(status: 200, body: json(#"{"text":"   "}"#))])
    let provider = OpenAISTTProvider(config: .openAISTT(apiKey: "sk-test"), transport: transport)
    await #expect(throws: FlowError.emptyTranscript) {
        try await provider.transcribe(audioFileURL: dummyAudio)
    }
}

@Test func sttHTTPErrorSurfaced() async throws {
    let transport = MockTransport([.init(status: 401, body: json(#"{"error":"bad key"}"#))])
    let provider = OpenAISTTProvider(config: .openAISTT(apiKey: "sk-bad"), transport: transport)
    do {
        _ = try await provider.transcribe(audioFileURL: dummyAudio)
        Issue.record("expected invalidResponse")
    } catch let FlowError.invalidResponse(code, _) {
        #expect(code == 401)
    }
}

@Test func sttMissingKeyThrows() async {
    let provider = OpenAISTTProvider(config: .openAISTT(apiKey: ""), transport: MockTransport([]))
    await #expect(throws: FlowError.missingAPIKey(provider: "OpenAI STT")) {
        try await provider.transcribe(audioFileURL: dummyAudio)
    }
}

// MARK: - OpenRouter STT (base64 JSON body)

@Test func openRouterSTTSendsBase64JSONAndParsesText() async throws {
    let transport = MockTransport([.init(status: 200, body: json(#"{"text":"  hello from openrouter  "}"#))])
    let provider = OpenRouterSTTProvider(apiKey: "sk-or-test", transport: transport)

    let text = try await provider.transcribe(audioFileURL: dummyAudio)
    #expect(text == "hello from openrouter")

    let req = transport.requests.first!
    #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-test")
    #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(req.url?.absoluteString == "https://openrouter.ai/api/v1/audio/transcriptions")

    let payload = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
    #expect(payload["model"] as? String == "openai/gpt-4o-mini-transcribe")
    let inputAudio = payload["input_audio"] as! [String: Any]
    #expect(inputAudio["format"] as? String == "swift") // #filePath ends in .swift
    #expect((inputAudio["data"] as? String)?.isEmpty == false)
}

@Test func sttSendsLanguageAndVocabularyPrompt() async throws {
    let transport = MockTransport([.init(status: 200, body: json(#"{"text":"hi"}"#))])
    let provider = OpenAISTTProvider(config: .openAISTT(apiKey: "sk-test"),
                                     language: "en", prompt: "Vocabulary: Dinesh, Vani, OpenRouter",
                                     transport: transport)
    _ = try await provider.transcribe(audioFileURL: dummyAudio)
    let body = String(decoding: transport.requests.first!.httpBody!, as: UTF8.self)
    #expect(body.contains("name=\"language\""))
    #expect(body.contains("en"))
    #expect(body.contains("name=\"prompt\""))
    #expect(body.contains("Vani"))
}

@Test func styleAppendsToneToCleanup() async throws {
    let transport = MockTransport([.init(status: 200, body: json(#"{"choices":[{"message":{"content":"x"}}]}"#))])
    let provider = OpenAILLMProvider(config: .openAILLM(apiKey: "k"),
                                     styleInstruction: WritingStyle.superCasual.instruction,
                                     transport: transport)
    _ = try await provider.cleanup("hello there")
    let payload = try JSONSerialization.jsonObject(with: transport.requests.first!.httpBody!) as! [String: Any]
    let messages = payload["messages"] as! [[String: String]]
    #expect(messages.first?["content"]?.contains(WritingStyle.superCasual.instruction) == true)
}

@Test func customInstructionFlowsIntoPrompt() async throws {
    let transport = MockTransport([.init(status: 200, body: json(#"{"choices":[{"message":{"content":"x"}}]}"#))])
    let provider = OpenAILLMProvider(config: .openAILLM(apiKey: "k"),
                                     styleInstruction: "Write like a pirate.",
                                     transport: transport)
    _ = try await provider.cleanup("hello")
    let payload = try JSONSerialization.jsonObject(with: transport.requests.first!.httpBody!) as! [String: Any]
    let messages = payload["messages"] as! [[String: String]]
    #expect(messages.first?["content"]?.contains("Write like a pirate.") == true)
}

@Test func textReplacementsAreCaseInsensitiveAndOrdered() {
    let out = TextTransforms.applyReplacements(
        "email me at my email and visit my site",
        [(from: "my email", to: "a@b.com"), (from: "my site", to: "b.com")])
    #expect(out == "email me at a@b.com and visit b.com")

    let ci = TextTransforms.applyReplacements("Call LDN office", [(from: "ldn", to: "London")])
    #expect(ci == "Call London office")
}

// MARK: - OpenAI LLM

@Test func llmCleansUpAndSendsFrozenSystemPrompt() async throws {
    let body = #"{"choices":[{"message":{"content":"This is a test message."}}]}"#
    let transport = MockTransport([.init(status: 200, body: json(body))])
    let provider = OpenAILLMProvider(config: .openAILLM(apiKey: "sk-test"), transport: transport)

    let result = try await provider.cleanup("um so like this is a test message")
    #expect(result == "This is a test message.")

    let sent = transport.requests.first!.httpBody!
    let payload = try JSONSerialization.jsonObject(with: sent) as! [String: Any]
    let messages = payload["messages"] as! [[String: String]]
    #expect(messages.first?["role"] == "system")
    #expect(messages.first?["content"]?.contains(FlowPrompt.systemCleanup) == true)
    #expect(messages.last?["content"] == "um so like this is a test message")
    #expect(payload["model"] as? String == "gpt-4o-mini")
}

@Test func llmEmptyInputShortCircuits() async throws {
    let transport = MockTransport([])
    let provider = OpenAILLMProvider(config: .openAILLM(apiKey: "sk-test"), transport: transport)
    let result = try await provider.cleanup("   ")
    #expect(result == "")
    #expect(transport.requests.isEmpty, "should not hit the network for empty input")
}

@Test func llmRewriteUsesCommandPromptAndPacksSelection() async throws {
    let body = #"{"choices":[{"message":{"content":"Concise version."}}]}"#
    let transport = MockTransport([.init(status: 200, body: json(body))])
    let provider = OpenAILLMProvider(config: .openAILLM(apiKey: "sk-test"), transport: transport)

    let result = try await provider.rewrite(instruction: "make this concise",
                                            selection: "this is a very long winded sentence")
    #expect(result == "Concise version.")

    let payload = try JSONSerialization.jsonObject(with: transport.requests.first!.httpBody!) as! [String: Any]
    let messages = payload["messages"] as! [[String: String]]
    #expect(messages.first?["content"] == FlowPrompt.systemCommand)
    #expect(messages.last?["content"]?.contains("make this concise") == true)
    #expect(messages.last?["content"]?.contains("very long winded") == true)
}

@Test func processWithSelectionUsesUnifiedPrompt() async throws {
    let body = #"{"choices":[{"message":{"content":"Edited."}}]}"#
    let transport = MockTransport([.init(status: 200, body: json(body))])
    let provider = OpenAILLMProvider(config: .openAILLM(apiKey: "sk-test"), transport: transport)

    _ = try await provider.process(transcript: "make this concise", selection: "a long sentence")
    let payload = try JSONSerialization.jsonObject(with: transport.requests.first!.httpBody!) as! [String: Any]
    let messages = payload["messages"] as! [[String: String]]
    #expect(messages.first?["content"]?.contains(FlowPrompt.systemUnified) == true)
    #expect(messages.last?["content"]?.contains("a long sentence") == true)
}

@Test func answerUsesAssistantPromptAndIncludesContext() async throws {
    let transport = MockTransport([.init(status: 200, body: json(#"{"choices":[{"message":{"content":"Paris."}}]}"#))])
    let provider = OpenAILLMProvider(config: .openAILLM(apiKey: "k"), transport: transport)
    let reply = try await provider.answer(question: "what's the capital of france", context: "travel notes")
    #expect(reply == "Paris.")
    let payload = try JSONSerialization.jsonObject(with: transport.requests.first!.httpBody!) as! [String: Any]
    let messages = payload["messages"] as! [[String: String]]
    #expect(messages.first?["content"]?.contains(FlowPrompt.systemAnswer) == true)
    #expect(messages.last?["content"]?.contains("travel notes") == true)
}

@Test func processWithoutSelectionUsesCleanupPrompt() async throws {
    let body = #"{"choices":[{"message":{"content":"Clean."}}]}"#
    let transport = MockTransport([.init(status: 200, body: json(body))])
    let provider = OpenAILLMProvider(config: .openAILLM(apiKey: "sk-test"), transport: transport)

    _ = try await provider.process(transcript: "um hello there", selection: "")
    let payload = try JSONSerialization.jsonObject(with: transport.requests.first!.httpBody!) as! [String: Any]
    let messages = payload["messages"] as! [[String: String]]
    #expect(messages.first?["content"]?.contains(FlowPrompt.systemCleanup) == true)
}

// MARK: - Anthropic LLM

@Test func anthropicParsesTextBlocksAndSetsHeaders() async throws {
    let body = #"{"content":[{"type":"text","text":"Cleaned text."}]}"#
    let transport = MockTransport([.init(status: 200, body: json(body))])
    let provider = AnthropicLLMProvider(apiKey: "sk-ant-test", transport: transport)

    let result = try await provider.cleanup("um cleaned text")
    #expect(result == "Cleaned text.")

    let req = transport.requests.first
    #expect(req?.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
    #expect(req?.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")

    let payload = try JSONSerialization.jsonObject(with: req!.httpBody!) as! [String: Any]
    #expect(payload["model"] as? String == "claude-haiku-4-5")
    #expect((payload["system"] as? String)?.contains(FlowPrompt.systemCleanup) == true)
    #expect(payload["thinking"] == nil, "cleanup is latency-sensitive — no thinking")
}

// MARK: - Pipeline

@Test func pipelineRunsStagesAndReturnsCleanedText() async throws {
    let sttResp = json(#"{"text":"um hello there"}"#)
    let llmResp = json(#"{"choices":[{"message":{"content":"Hello there."}}]}"#)
    let stt = OpenAISTTProvider(config: .openAISTT(apiKey: "k"),
                                transport: MockTransport([.init(status: 200, body: sttResp)]))
    let llm = OpenAILLMProvider(config: .openAILLM(apiKey: "k"),
                                transport: MockTransport([.init(status: 200, body: llmResp)]))
    let pipeline = DictationPipeline(stt: stt, llm: llm)

    let stages = StageRecorder()
    let result = try await pipeline.process(audioFileURL: dummyAudio) { stages.record($0) }
    #expect(result == "Hello there.")
    #expect(stages.values == [.transcribing, .cleaning])
}

/// Thread-safe collector for pipeline stage callbacks.
final class StageRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [DictationPipeline.Stage] = []
    func record(_ s: DictationPipeline.Stage) { lock.lock(); _values.append(s); lock.unlock() }
    var values: [DictationPipeline.Stage] { lock.lock(); defer { lock.unlock() }; return _values }
}
