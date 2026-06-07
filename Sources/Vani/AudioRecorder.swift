import Foundation
import AVFoundation

/// Records microphone audio to a temporary AAC `.m4a` file (accepted by OpenAI/Groq STT).
@MainActor
final class AudioRecorder: NSObject {
    private var recorder: AVAudioRecorder?
    private(set) var currentFileURL: URL?

    /// Ask for microphone permission. Calls back on the main actor.
    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static var hasPermission: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Begin recording. Returns false if the recorder couldn't start.
    @discardableResult
    func start() -> Bool {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vani-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else { return false }
            self.recorder = recorder
            self.currentFileURL = url
            return true
        } catch {
            return false
        }
    }

    /// Stop recording and return the file URL (or nil if nothing was recorded).
    func stop() -> URL? {
        recorder?.stop()
        recorder = nil
        let url = currentFileURL
        currentFileURL = nil
        return url
    }

    var isRecording: Bool { recorder?.isRecording ?? false }
}
