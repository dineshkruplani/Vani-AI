# Vani

A macOS voice-dictation app in the spirit of [Wispr Flow](https://wisprflow.ai), but
**bring-your-own-API-key** instead of a $15/mo subscription. Hold a hotkey, speak, and Vani
transcribes → AI-cleans (removes filler, fixes grammar, formats) → pastes polished text at your
cursor in any app. You pay providers (OpenAI / Groq / Anthropic) directly at cost, or run models
locally. Your audio and text never pass through anyone's server but the provider you choose.

See the full PRD/build plan in `~/.claude/plans/let-s-understand-https-wisprflow-ai-s-glowing-lemon.md`.

## Status

| Phase | What | State |
|---|---|---|
| 0 | Swift package scaffold (`FlowCore` lib + `Vani` app) | ✅ builds |
| 1 | Core loop: record → STT → LLM cleanup → paste | ✅ implemented, unit-tested |
| 2 | Global Fn hotkey (`CGEventTap`) + menu-bar UI + permission prompts | ✅ implemented |
| 3 | Provider abstraction + Settings (OpenAI / OpenRouter / Groq / Anthropic) | ✅ implemented |
| 4 | Custom hotkey, model-routed dictation/commands, Liquid-Glass HUD + sound cues, local whisper.cpp | ✅ implemented |
| 5 | Onboarding wizard, writing styles, language + custom vocabulary, accuracy upgrades | ✅ implemented |
| — | Real Apple/Google auth (needs backend), streaming insertion, .dmg + notarization | ⏳ todo |

**MVP default pipeline:** OpenAI `whisper-1` (STT) + OpenAI `gpt-4o-mini` (cleanup), driven by a single
OpenAI key. Switch to Groq or Anthropic (`claude-haiku-4-5`) in Settings.

## Requirements

- macOS 13+
- Swift 6.1 toolchain (Xcode or Command Line Tools — `swift --version`)
- An API key for your chosen provider

## Build & test

```bash
swift build          # compile everything
swift test           # run the FlowCore unit suite (uses Swift Testing)
```

## Run

A menu-bar app needs to run from a `.app` bundle so macOS will remember Microphone/Accessibility
grants. Use the script:

```bash
./scripts/run.sh           # bundles Vani.app and launches it
# or: ./scripts/bundle.sh release && open Vani.app
```

Then:
1. Click the **mic icon** in the menu bar → **Settings…** → paste your OpenAI key → **Save**.
2. Grant **Microphone** and **Accessibility** when prompted (Accessibility is needed for the global
   hotkey and to paste into other apps: System Settings → Privacy & Security → Accessibility).
3. Focus any text field, **hold Fn**, speak, **release**. Cleaned text appears at your cursor.
   (Or use the menu's **Test Dictation** button — no hotkey required.)

## Onboarding

On first launch a wizard opens: welcome/sign-in (Apple/Google are placeholders — accounts come later)
→ writing style + language → optional API key → a live "try it" test → hotkey → done.
Re-open any time from the menu bar → **Setup Guide…**.

## Writing styles & accuracy

- **Writing style** (Settings → Writing): **Formal / Casual / Super casual** — each adjusts the cleanup tone.
- **Language**: pass an explicit language so transcription doesn't mis-detect (or Auto).
- **Custom vocabulary**: names/jargon you add are used to **prime Whisper** (its `prompt` field) so it spells
  them correctly — this is the main lever for the "it just understands me" feel.
- Default OpenRouter STT model is **`openai/gpt-4o-mini-transcribe`** (more accurate than whisper-1 and
  better at honoring the vocabulary prompt). Valid OpenRouter STT slugs: `openai/gpt-4o-mini-transcribe`,
  `openai/gpt-4o-transcribe`, `openai/whisper-1`. (Note: `openai/whisper-large-v3` is **not** valid — OpenAI's
  API only serves `whisper-1`.)

## Features

### One hotkey, dictation + commands (model-routed)
Pick a single push-to-talk key in Settings (Fn / Right Option / Right Command / Right Control;
Right Option recommended). Hold it and speak, then release:
- **Nothing selected** → your speech is cleaned up and inserted at the cursor (dictation).
- **Text selected** → Vani reads the selection (non-destructively, via Accessibility) and the
  LLM decides: if you spoke an instruction ("make this concise", "translate to French", "fix grammar")
  it edits the selection in place; otherwise it treats your speech as dictation. One key does both —
  the model figures out which you meant.

### Liquid-Glass HUD + sound cues
A floating translucent overlay shows Listening / Transcribing / Cleaning / Inserted state, with
start/stop/error sounds. (Uses `NSVisualEffectView` vibrancy — the Liquid-Glass approximation
available on macOS 13–15.)

### Local whisper.cpp (offline STT, no key)
Run transcription entirely on-device:
```bash
brew install whisper-cpp
mkdir -p ~/.vani
curl -L -o ~/.vani/ggml-base.en.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
```
Then Settings → Speech-to-text → **Local (whisper.cpp)**, set the model path to
`~/.vani/ggml-base.en.bin` (the `whisper-cli` path defaults to the Homebrew location).
Vani converts mic audio to 16 kHz WAV via `afconvert` and runs `whisper-cli`.

## Architecture

```
[Fn hotkey] → [AudioRecorder] → [STTProvider] → [LLMProvider] → [TextInserter]
 CGEventTap     AVAudioRecorder    OpenAI/Groq      OpenAI/Groq     clipboard+⌘V
                  (.m4a)           /whisper.cpp     /Anthropic      (restores clipboard)
```

- **`FlowCore`** (library, UI-free, tested): `STTProvider`/`LLMProvider` protocols,
  `OpenAISTTProvider`, `OpenAILLMProvider`, `AnthropicLLMProvider`, `DictationPipeline`, frozen
  cleanup prompt. One OpenAI-compatible adapter covers OpenAI, Groq, and local Ollama.
- **`Vani`** (app): `AudioRecorder`, `HotkeyManager`, `TextInserter`, `KeychainStore`,
  `SettingsStore`, SwiftUI `MenuBarExtra` + Settings window.

API keys are stored in the **macOS Keychain** — never in UserDefaults or plaintext.

## Not yet built (see plan's Future Features)

Command Mode (voice-edit selected text), personal dictionary, snippets, app-aware tone, multi-language
UX, Whisper Mode, local whisper.cpp STT, streaming partial transcripts, Windows/iOS ports, cost dashboard.
