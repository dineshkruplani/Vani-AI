# Vani

A macOS menu-bar **voice-dictation** app — hold a hotkey, speak, and your words appear (cleaned up) at
the cursor in any app. In the spirit of [Wispr Flow](https://wisprflow.ai) and
[VoiceInk](https://github.com/Beingpax/VoiceInk), but **bring-your-own-API-key or fully local** —
no subscription, and your audio/text go **directly to the provider you choose** (or never leave the device).

> Full spec: [`PRD.md`](PRD.md) · Deferred work: [`BACKLOG.md`](BACKLOG.md)

## Highlights
- **Dictation** — hold the key (or double-tap for hands-free), speak, get clean text inserted at the cursor.
- **Command mode** (separate key) — with text selected, speak an instruction ("make this concise",
  "translate to French") to edit it in place; with nothing selected, ask a question and get the answer in a
  floating popover near the cursor.
- **Providers, your choice** — cloud (OpenAI / OpenRouter / Groq / Anthropic) or local
  (**Parakeet** on the Neural Engine, **whisper.cpp**, **Ollama**). One OpenRouter key can power both STT + cleanup.
- **Offline** — with Parakeet (local STT), it works with no internet; cleanup auto-falls-back to the raw
  transcription when offline.
- **Personalization without training** — surrounding-cursor context priming, custom vocabulary, learned
  corrections ("Teach a Word" / "Correct Last"), auto language detection, auto-seeded name.
- **Writing modes** — Formal / Casual / Super casual, plus your own custom modes.
- **Power Mode** — per-app profiles auto-switch mode + language by the frontmost app.
- **Snippets** — `trigger = replacement` text expansions applied to inserted text.
- **Custom hotkeys** — presets (Fn / Right ⌥ / ⌘ / ⌃) or your own modifier combo.
- Liquid-Glass HUD + sound cues; first-run onboarding wizard.

## Requirements
- **macOS 14+** (Apple Silicon) — Parakeet/FluidAudio needs 14+
- Swift 6 toolchain (Xcode or Command Line Tools — `swift --version`)
- An API key for your chosen cloud provider, *or* use a local engine (no key)

## Build & test
```bash
swift build          # compiles FlowCore + Vani (fetches FluidAudio on first build)
swift test           # FlowCore unit suite (Swift Testing) — 17 tests
```

## Run
A menu-bar app should run from a `.app` bundle so macOS remembers Microphone/Accessibility grants. One-time,
set up a stable signing identity so those grants persist across rebuilds, then launch:
```bash
./scripts/setup-signing.sh   # once: creates a self-signed "Vani Dev" identity
./scripts/run.sh             # builds, signs, and launches Vani.app
```
Look for the **mic icon in the menu bar** (no Dock icon). On first launch an **onboarding wizard** walks you
through: writing style + language → optional API key → a live "try it" test → hotkeys.

Grant **Microphone** and **Accessibility** when prompted (Accessibility is required for the global hotkey,
reading the selection, and pasting into other apps). Reopen the wizard anytime from the menu → **Setup Guide…**.

## Providers
| Role | Cloud (BYO key) | Local (offline) |
|---|---|---|
| **Speech-to-text** | OpenAI `whisper-1`, **OpenRouter** `openai/gpt-4o-mini-transcribe` (default), Groq `whisper-large-v3-turbo` | **Parakeet** (FluidAudio / ANE), **whisper.cpp** |
| **Cleanup / commands / answers** | OpenAI `gpt-4o-mini`, **OpenRouter** (any model), Groq `llama-3.3-70b`, Anthropic `claude-haiku-4-5` | **Ollama** |

Pick them in **Settings**. For an offline-capable setup, choose **Parakeet** (Settings → Speech-to-text →
*Local (Parakeet)* → "Download model for offline use", ~600 MB one-time).

## Architecture
```
[Hotkey]→[GestureController]→[AudioRecorder]→[STTProvider]→[LLMProvider]→[TextInserter / AnswerHUD]
 CGEventTap  hold/double-tap   AVAudioRecorder  cloud OR        cloud OR       clipboard+⌘V / popover
                                                Parakeet/whisper Ollama (or raw fallback offline)
   SelectionAccess (AX): selection + text-before-caret  → routing, STT priming, answer context
```
- **`FlowCore`** — UI-free, tested library: provider protocols + adapters, `DictationPipeline`, prompts,
  `TextTransforms`, `WritingStyle`.
- **`Vani`** — the macOS app: audio, hotkeys + gestures, selection/context, HUDs, onboarding, settings.
- Dependency: [`FluidInference/FluidAudio`](https://github.com/FluidInference/FluidAudio) (Parakeet on Core ML / ANE).
- Built with Swift Package Manager (no Xcode project). `scripts/bundle.sh` assembles the `.app`.

## Privacy
- API calls go **directly to the chosen provider** — there is no Vani server, and nothing proxies your audio or text.
- Keys + preferences are stored in local app preferences (UserDefaults).
- Fully offline operation is possible with Parakeet/whisper.cpp + raw insert (or Ollama for local cleanup).

## Status & roadmap
Working MVP+ (v0.2). See [`PRD.md`](PRD.md) for the full feature spec and [`BACKLOG.md`](BACKLOG.md) for
deferred work (real auth, `.dmg` + notarization, streaming insertion, Contacts import, performance, …).

> Note: not yet notarized — distributed as a self-signed `.app`. On another Mac, Gatekeeper will require a
> right-click → Open until Developer ID signing + notarization are set up.
