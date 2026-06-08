# Vani — Backlog / Later

Running list of things intentionally deferred. Newest context at top of each section.
(See `PRD.md` for current shipped state.)

---

## Liquid-Glass design system (epic — in progress)
Implementing the Vani visual handoff in SwiftUI, phased.
- [x] **Phase 1 — Foundation**: design tokens (Iris accent, adaptive light/dark colors, radii), glass
      material modifier (`glassPanel`), animated aurora background, Light/Dark/Auto theme, **bundled fonts**
      (Hanken Grotesk / Newsreader / Spline Sans Mono), **Launch-at-login**, **Show-in-Dock**, **History (store/clear)**.
- [x] **Phase 2 — Controls**: glass component kit (GroupLabel, GlassCard, SettingRow, VaniTabBar, ChipField, AccentSwatches).
- [x] **Phase 3 — Dynamic-island HUD**: voice-dot pulse, live waveform, mono timer, dark-glass gradient.
- [x] **Phase 4 — Onboarding**: 7-step glass flow (welcome / permissions / push-to-talk / connect /
      voice&style / try-it / all-set) with typewriter snippet + logo mark.
- [x] **Phase 5 — Settings**: 6-tab glass window (General / Voice / Providers[Simple·Advanced] / Shortcuts / Privacy / About).
- [x] **Phase 6 — Brand assets**: Vani `.icns` app icon (Iris squircle + "va" glyph) generated via CoreGraphics, bundled.
- [x] **Visual fidelity pass (HUD)**: top-center Dynamic-Island placement; removed the Iris glow; fixed the
      resize-ghost (OS window shadow → SwiftUI shadow); inline detail (`Cleaning up · gpt-4o-mini`,
      `Inserted · 24 words`); waveform-left listening layout with 20-bar silhouette; **idle "Hold ⌥ to talk"
      prompt** shown when a text field is focused in any app (FocusWatcher via Accessibility; toggle in General).
- [ ] **Visual fidelity pass (Settings/Onboarding)**: boards match closely; tune further if on-device render drifts.
- [ ] **History viewer** (list of past dictations) — counter + clear done; full list view pending.
- [ ] Edit-in-place HUD two-row state (header + spoken command) from the design.
- [ ] When on **macOS 26 (Tahoe)**: swap the material approximation for the real `.glassEffect()` APIs.
- Notes: keys stay in **UserDefaults** (not Keychain — update design copy); **both hold + double-tap** stay
  always-on (no Hold/Toggle setting); cleanup-toggle granularity (filler/punctuation/caps) intentionally dropped.

## Tech debt / cleanup
- [ ] **Rename internal `Flow*` symbols → `Vani*`.** App name "FlowKey" is fully gone, but the internal
      core library/types still carry the old brand: `FlowCore` (module, ~12 refs), `FlowError` (~45),
      `FlowPrompt` (~23). Rename to `VaniCore` / `VaniError` / `VaniPrompt`, rename `Sources/FlowCore` →
      `Sources/VaniCore` and `Tests/FlowCoreTests` → `Tests/VaniCoreTests`, update `Package.swift`. ~80
      references; mechanical but rebuild + retest after. Internal only (not user-visible).
- [ ] **Refresh `README.md`.** Its content is stale (still describes the pre-Power-Mode / pre-Parakeet
      single-key, model-routed design; says macOS 13; mentions Keychain). `PRD.md` is the current source of truth.
- [ ] **Delete old `FlowKey Dev` cert** from the login Keychain (user-machine cleanup, not a repo task):
      `security delete-identity -c "FlowKey Dev" ~/Library/Keychains/login.keychain-db`
- [ ] Optional: add a `CHANGELOG.md` (v0.1 → v0.2 …).

## Features (deferred)
- [ ] **Real Apple / Google sign-in** — currently placeholders. Needs an Apple Developer account + a
      backend/OAuth. Pairs with optional settings sync across devices.
- [ ] **One-tap Contacts import** — seed proper-noun vocabulary from the address book (names are what
      STT botches most). Highest-value remaining personalization idea.
- [ ] **URL-based Power Mode rules** — per-site profiles (e.g. gmail.com → Email mode). Needs Automation
      permission (AppleScript) to read the browser's active tab URL. Today Power Mode is app-based only.
- [ ] **Per-app provider/model override in Power Mode** — today profiles override mode + language only;
      add optional STT/LLM provider+model per app.
- [ ] **Streaming insertion** — insert text as it's transcribed for lower perceived latency.
- [ ] **Multi-turn AI assistant** — extend the answer-mode popover into a short back-and-forth.
- [x] **Context awareness (screen content)** — `ScreenContextService` reads the active window (app name +
      title + visible text via the AX tree) at recording start and injects it into the cleanup/command LLM
      system prompt (`<SCREEN_CONTEXT>` block) so it spells on-screen names right and matches context.
      Opt-in **Screen-OCR fallback** (ScreenCaptureKit + Vision) for apps AX can't read (needs Screen
      Recording). Toggles in Voice → Context awareness; default on (AX), OCR off. (VoiceInk parity.)
- [ ] **In-app local-model manager** — download/select whisper.cpp models from within the app (today the
      user curls a model + pastes a path). VoiceInk-style.
- [ ] **Deeper "Correct Last" learning** — diff old→corrected to auto-build wrong→right replacements,
      not just learn the corrected spellings.

## Performance / latency ("make it feel instant")
The two sequential network round-trips (STT → cleanup) dominate latency. Levers, biggest first:
- [ ] **Fastest preset (one click)** — configure Groq turbo STT + Groq cleanup (or Parakeet local STT) +
      connection pre-warm. (Note: switching to Groq or Parakeet in Settings today is already the biggest
      zero-code speedup — both calls go sub-second / STT goes local.)
- [ ] **One-call audio→clean** — send audio to a multimodal model (`openai/gpt-4o-audio`,
      `google/gemini-2.0-flash` via OpenRouter) that transcribes AND cleans in a **single request**,
      eliminating the separate STT round-trip (~halves network latency). Tradeoff: less control than
      dedicated Whisper; not all models accept audio input.
- [ ] **Streaming live insertion** — stream the cleanup and insert tokens as they arrive (simulated
      Unicode key events, not clipboard) so text appears as you finish speaking. The Wispr-style
      "instant" feel even when total time is similar.
- [ ] **Edge shaves** — keep the provider HTTP connection warm at launch; cap cleanup `max_tokens`.
      (Prompt caching won't help — the cleanup system prompt is below the cacheable minimum.)

## Packaging / distribution
- [ ] **`.dmg`** with drag-to-Applications layout.
- [ ] **Developer ID signing + notarization** so it installs cleanly on any Mac (no Gatekeeper friction).
- [ ] **Sparkle auto-update** + **Homebrew cask** (`brew install --cask vani`).

## Verification (needs a real device / GUI — couldn't be tested in the dev sandbox)
- [ ] **Parakeet** first-run model download (~600 MB) + ANE transcription actually works.
- [ ] **Offline auto-fallback** (cleanup skipped → raw insert) end-to-end with Wi-Fi off.
- [ ] **Gesture timing** — hold vs double-tap feel; tune `GestureController.holdThreshold` (0.22s) /
      `doubleTapWindow` (0.40s) if needed.
- [ ] **Answer popover hover-persist** — confirm it stays while hovered (else switch to explicit `NSTrackingArea`).
- [ ] **Custom-combo hotkey on external keyboards** — confirm the Fn-strip fix holds across keyboards.

## Platform (long-term)
- [ ] Windows / iOS ports.
- [ ] Usage / cost dashboard (tokens + $ per provider).

---

### Decided against (so we don't relitigate)
- **Style-based vocabulary dictionaries** — style is tone (cleanup LLM handles it), not spelling. Vocabulary
  is auto-sourced + learned instead.
- **An "accent" setting** — STT APIs expose no accent parameter; handled via model + language + learned corrections.
- **Bundling the local model in the app** — would bloat the `.dmg` by ~600 MB–2 GB; download-on-demand instead.
- **A manual "cleanup on/off" toggle** — cleanup is automatic with offline fallback to raw, no toggle.
