import Foundation

/// Turns raw press/release events from one hotkey into recording gestures.
/// Both gestures are always active on the same key:
///   • Hold-to-talk — press & hold, release to finish.
///   • Double-tap hands-free — double-tap to start, single tap to stop.
///
/// Audio capture starts immediately on press (so the first word isn't clipped);
/// a quick tap discards that brief capture and feeds the tap into double-tap detection.
@MainActor
final class GestureController {
    var holdThreshold: TimeInterval = 0.22   // press longer than this = a hold
    var doubleTapWindow: TimeInterval = 0.40  // two taps within this = double-tap

    private let startCapture: () -> Bool   // begin recording (silent); returns success
    private let confirmHUD: () -> Void     // show HUD + start sound (recording confirmed)
    private let stopAndProcess: () -> Void // finish recording and run the pipeline
    private let discard: () -> Void        // drop the in-progress capture (a tap)

    init(startCapture: @escaping () -> Bool,
         confirmHUD: @escaping () -> Void,
         stopAndProcess: @escaping () -> Void,
         discard: @escaping () -> Void) {
        self.startCapture = startCapture
        self.confirmHUD = confirmHUD
        self.stopAndProcess = stopAndProcess
        self.discard = discard
    }

    private var isPressed = false
    private var pressTime = Date()
    private var isHolding = false      // confirmed hold-to-talk recording
    private var isToggling = false     // hands-free (double-tap) recording
    private var captureActive = false  // recorder currently running for this press
    private var holdWork: DispatchWorkItem?
    private var lastTapTime: Date?
    private var tapExpire: DispatchWorkItem?

    func onPress() {
        isPressed = true
        pressTime = Date()

        // Already recording hands-free → this press will stop it on release.
        if isToggling { return }

        captureActive = startCapture()
        guard captureActive else { return }

        // Promote to a confirmed hold if the key is still down after the threshold.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isPressed, self.captureActive, !self.isToggling else { return }
            self.isHolding = true
            self.confirmHUD()
        }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold, execute: work)
    }

    func onRelease() {
        isPressed = false
        holdWork?.cancel(); holdWork = nil

        if isToggling {                 // tap/release during hands-free → stop
            isToggling = false
            stopAndProcess()
            lastTapTime = nil
            return
        }

        if isHolding {                  // confirmed hold → finish
            isHolding = false
            captureActive = false
            stopAndProcess()
            lastTapTime = nil
            return
        }

        // Released before the hold threshold → a tap. Drop the brief capture.
        if captureActive { discard(); captureActive = false }

        if let last = lastTapTime, Date().timeIntervalSince(last) <= doubleTapWindow {
            // Second tap → start hands-free recording.
            lastTapTime = nil
            tapExpire?.cancel()
            if startCapture() { isToggling = true; confirmHUD() }
        } else {
            lastTapTime = Date()
            scheduleTapExpire()
        }
    }

    private func scheduleTapExpire() {
        tapExpire?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.lastTapTime = nil }
        tapExpire = work
        DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow + 0.05, execute: work)
    }
}
