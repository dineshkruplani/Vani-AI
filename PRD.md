# Vani — Product Requirements Document

**Status:** Working MVP+ (v0.2, in active development)
**Platform:** macOS 14+ (Apple Silicon)
**Last updated:** 2026-06-07

---

## 1. Overview

Vani is a macOS menu-bar voice-dictation app in the spirit of [Wispr Flow](https://wisprflow.ai)
and [VoiceInk](https://github.com/Beingpax/VoiceInk): hold a hotkey, speak, and your words appear —
cleaned up and formatted — at the cursor in any app.

**The differentiator:** instead of a monthly subscription, Vani is **bring-your-own-API-key (BYO)**
or **fully local**. The user supplies their own provider key (OpenAI / OpenRouter / Groq / Anthropic),
or runs models on-device (Parakeet on the Neural Engine, whisper.cpp, Ollama). Vani calls providers
**directly** — audio and text never pass through a Vani-operated server.

### Why
- Wispr Flow is $15/mo with usage caps and routes audio through its cloud.
- A BYO-key / local client removes the recurring fee and per-word quota, lets power users pick their own
  models/quality/cost, and enables a fully offline, private mode.

---

## 2. Goals & Non-Goals

### Goals
- Frictionless dictation anywhere in macOS via a global push-to-talk (or hands-free) hotkey.
- High transcription accuracy that personalizes itself **without explicit training**.
- One client, many swappable providers (cloud or local); no vendor lock-in.
- Privacy: direct-to-provider calls; optional 100% offline operation.
- A guided first-run experience that gets a user productive in minutes.

### Non-Goals (current release)
- No Vani backend, accounts, or subscription billing (sign-in is a placeholder).
- No Windows / iOS / Android (macOS only).
- No streaming/word-by-word insertion (text is inserted once, finalized).

---

## 3. Personas & Core Jobs
- **Knowledge worker** dictating email/docs/Slack faster than typing.
- **Developer** dictating messages/comments; issuing edit commands on selected text.
- **Privacy-conscious / offline user** running on-device with no keys, no network.

Core jobs:
1. **Dictate** → speak, get clean text at the cursor.
2. **Command on selection** → select text, speak an instruction, get it rewritten in place.
3. **Ask** → with nothing selected, speak a question, get an answer in a floating popover.

---

## 4. Functional Requirements (Implemented)

### 4.1 Core dictation loop
- Pipeline: capture mic (`AVAudioRecorder`, 16 kHz mono m4a) → **STT** → **LLM cleanup** → **insert** at cursor.
- Insertion via pasteboard + synthesized ⌘V, **restoring the previous clipboard**.
- Cleanup removes fillers, fixes grammar/punctuation/casing, applies the active writing mode.

### 4.2 Hotkeys & gestures
- **Two independent hotkeys**: Dictation and Command.
- Presets: **Fn, Right Option, Right Command, Right Control**; plus **custom modifier combos** (e.g. ⌃⌥)
  via an in-app recorder. (Fn is ignored when matching custom combos — external keyboards set it spuriously.)
- **Both gestures always active on each key:**
  - **Hold-to-talk** — press & hold, release to finish (audio captured from the instant of press).
  - **Double-tap hands-free** — double-tap to start, single tap to stop.

### 4.3 Command mode (separate key)
- **Text selected** → edits the selection in place ("make this concise", "translate to French").
- **Nothing selected** → **Answer mode**: the spoken question is sent to the LLM and the reply appears
  in a **floating glass popover near the cursor** that auto-dismisses (~4s) but **persists while hovered**
  (text selectable). Not inserted.
- Selection read non-destructively via Accessibility, with a clipboard-restoring ⌘C fallback for apps
  that don't expose it (Chrome/Electron).

### 4.4 Providers
| Role | Cloud (BYO key) | Local (offline) |
|---|---|---|
| **STT** | OpenAI (`whisper-1`), **OpenRouter** (`openai/gpt-4o-mini-transcribe`, default), Groq (`whisper-large-v3-turbo`) | **Parakeet** (FluidAudio / Core ML on the **Neural Engine**), **whisper.cpp** |
| **Cleanup / commands / answers** | OpenAI (`gpt-4o-mini`), **OpenRouter** (any model), Groq (`llama-3.3-70b`), Anthropic (`claude-haiku-4-5`) | **Ollama** |

- One OpenAI-compatible adapter covers OpenAI / Groq / OpenRouter / Ollama; Anthropic, OpenRouter-STT,
  whisper.cpp, and Parakeet have dedicated adapters.
- A single OpenRouter key can power both STT and cleanup.

### 4.5 Offline mode & auto-fallback
- **No toggle.** Cleanup runs whenever an LLM is reachable; when it **isn't** (offline / no LLM key /
  cleanup error), Vani **automatically inserts the raw transcription** (+ snippets) and shows
  "Inserted (raw — offline)". Dictation never hard-fails on cleanup.
- For a fully offline session: **Parakeet STT** (works on-device) + raw insert + snippets.
- Settings offers **"Download model for offline use"** to pre-fetch Parakeet (~600 MB, one-time) so it's
  ready before going offline.
- Command/Answer modes require an LLM (no offline fallback for edits/answers).

### 4.6 Writing modes
- Built-in **Formal / Casual / Super casual**, plus **custom modes** (`Name :: instruction` lines) that
  appear in the Mode picker. The active mode's instruction drives cleanup tone.

### 4.7 Power Mode (per-app)
- Per-app **profiles** auto-apply a **mode + language** based on the frontmost app (e.g. Gmail → Formal).
- Managed in Settings (add from running apps, toggle on/off). URL-based rules deferred (need Automation
  permission).

### 4.8 Accuracy & personalization (zero-training)
- **Surrounding-cursor context** (Accessibility) fed to the STT prompt — continues in-style, recognizes
  on-screen names/terms. *(Cloud Whisper path; Parakeet takes no prompt.)*
- **Custom vocabulary** + auto-seeded **macOS account name** primed into the STT prompt.
- **Learned corrections** — "Teach a Word" / "Correct Last Result" build a personal dictionary over time.
- **Text replacements / snippets** (`trigger = replacement`) applied to inserted text (works offline).
- **Auto language detection** (on-device `NaturalLanguage`) at the onboarding test; language passed to STT.

### 4.9 Onboarding wizard (first launch)
Welcome / sign-in (Apple + Google **placeholders**) → Profile (mode + language) → API key (optional) →
**live "try it" test** (records, shows cleaned result, auto-detects language) → Hotkeys → Done (Follow on X).
Re-openable from the menu (**Setup Guide…**).

### 4.10 UX
- Menu-bar `MenuBarExtra` (no Dock icon); status, Teach-a-Word / Correct-Last, Settings, Setup Guide.
- **Liquid-Glass HUD** (vibrancy) for recording/processing/inserted states, with start/stop/error sounds.
- **Answer popover** with hover-persist.
- Surfaces Accessibility-permission state with a one-click "Open Accessibility Settings".

### 4.11 Privacy & storage
- API calls go **directly to the chosen provider**; no Vani server.
- API keys + preferences stored in **app preferences (UserDefaults)** by explicit user choice (not Keychain).
- **Fully offline** possible with Parakeet/whisper.cpp (STT) and raw-insert or Ollama (cleanup).

---

## 5. Architecture

```
[Hotkey]→[GestureController]→[AudioRecorder]→[STTProvider]→[LLMProvider]→[TextInserter / AnswerHUD]
 CGEventTap  hold/double-tap   AVAudioRecorder  cloud OR        cloud OR       clipboard+⌘V / popover
                                                Parakeet/whisper Ollama (or raw fallback offline)
                                                     │               │
   SelectionAccess (AX): selection + text-before-caret ─────────────┘  (routing, priming, answer context)
   SettingsStore: providers, modes, snippets, Power Mode profiles, learned terms, hotkeys
```

- **`FlowCore`** (UI-free Swift library, **17 passing tests**): provider protocols; OpenAI/OpenRouter/Groq/
  Anthropic adapters; `DictationPipeline`; prompts (cleanup/unified/command/answer) with free-text mode
  instruction; `TextTransforms.applyReplacements`; `WritingStyle`.
- **`Vani`** (macOS app): `AudioRecorder`, `HotkeyManager` (+ custom combos), `GestureController`
  (hold + double-tap), `SelectionAccess`, `TextInserter`, `SettingsStore`, `AppState`, `ParakeetSTT`
  (FluidAudio), `LocalWhisperProvider`, HUD + AnswerHUD, Onboarding, Settings, ShortcutRecorder, QuickPrompt.
- **Dependency:** `FluidInference/FluidAudio` (Parakeet on Core ML / ANE) — requires macOS 14+.
- **Build:** Swift Package Manager (no Xcode project). `scripts/bundle.sh` assembles a `.app`;
  `scripts/setup-signing.sh` creates a stable self-signed identity so TCC grants persist across rebuilds.

---

## 6. Permissions
- **Microphone** — to record audio.
- **Accessibility** — global hotkeys, reading selection/context, pasting into other apps.

---

## 7. Current Status

**Done:** core dictation; cloud + local providers (Parakeet ANE, whisper.cpp, Ollama); offline auto-fallback;
separate dictation/command keys with presets + custom combos; hold + double-tap gestures; command
edit-in-place; answer-mode hover popover; built-in + custom writing modes; snippets/replacements; Power Mode;
surrounding-context + vocabulary + learned-terms personalization; language auto-detect; onboarding wizard;
Liquid-Glass HUD + sounds; permission surfacing; stable signing; `.app` bundling. **17/17 FlowCore tests pass.**

**Verified on-device:** OpenRouter STT + cleanup, command edit + answer flows, custom-combo hotkeys
(incl. external-keyboard fix). **Not yet exercised on-device:** Parakeet model download + ANE transcription,
offline fallback, gesture timing (built + compiled; await real-device confirmation).

---

## 8. Known Limitations
- **Accounts are placeholders** — Apple/Google sign-in is non-functional (needs Apple Developer account + backend).
- **Parakeet model is downloaded on first use (~600 MB)**, not bundled — needs one online fetch before offline use.
- **Parakeet can't be vocabulary-primed** — offline personalization is via snippets/replacements only.
- **Command/Answer have no offline fallback** — they need a reachable LLM (cloud or Ollama).
- **Selection/context via Accessibility** — apps without AX (some Electron/web) fall back to ⌘C / no context.
- **Not notarized** — self-signed `.app`; clean install on other Macs needs Developer ID + notarization.
- **No streaming insertion**; min OS is now **macOS 14** (FluidAudio).

---

## 9. Roadmap / Future
- **One-tap Contacts import** to seed proper-noun vocabulary.
- **Real Apple/Google auth** (needs backend) + optional settings sync.
- **Packaging**: drag-to-Applications `.dmg` + Developer ID signing + notarization + Sparkle auto-update + Homebrew cask.
- **URL-based Power Mode rules** (needs Automation permission).
- **Streaming insertion** for lower perceived latency.
- **Multi-turn AI assistant** (extend answer popover).
- Optional on-device **screen-OCR context** fallback (Vision) for apps AX can't read.
- Windows / iOS ports; usage/cost dashboard.

---

## 10. Key Decisions Made
- **BYO-key / local, no backend, no subscription** — core product stance.
- **API keys in UserDefaults, not Keychain** — by user preference (avoids prompts; plaintext tradeoff accepted).
- **Dictation and Command on separate keys.**
- **Both hold-to-talk and double-tap-hands-free always active** on each key (no mode setting).
- **Custom hotkeys are modifier-combos only, hold-to-talk**; Fn ignored in matching (external-keyboard reliability).
- **Cleanup is automatic with offline fallback to raw** — not a user toggle.
- **Writing style = cleanup tone, not a vocabulary list**; vocabulary is auto-sourced + learned.
- **No "accent" setting** — STT APIs have none; handled via model + language + learned corrections.
- **Parakeet (ANE) for fast local STT, downloaded not bundled**; Ollama for optional local cleanup.
- **OpenRouter STT default = `openai/gpt-4o-mini-transcribe`** (`openai/whisper-large-v3` is not a valid slug).
