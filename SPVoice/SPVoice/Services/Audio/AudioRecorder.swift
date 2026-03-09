@preconcurrency import AVFoundation
import Combine
import os

/// Records microphone audio to a temporary WAV file via AVAudioEngine.
@MainActor
final class AudioRecorder: ObservableObject {

    enum State: Equatable {
        case idle
        case recording
        case exporting
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    /// Current audio input level (0.0–1.0) for UI metering.
    @Published private(set) var audioLevel: Float = 0.0

    /// URL of the last successfully exported recording.
    private(set) var lastRecordingURL: URL?

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingStartTime: Date?
    private var maxDurationTask: Task<Void, Never>?

    /// 16 kHz mono PCM format for the output WAV.
    private static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: SPVoiceConstants.Defaults.audioSampleRate,
        channels: 1,
        interleaved: false
    )!

    // MARK: - Recording Lifecycle

    func startRecording() throws {
        guard state == .idle else {
            Logger.audio.warning("Cannot start recording — state is \(String(describing: self.state))")
            return
        }

        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            state = .failed("Microphone permission not granted")
            throw AudioRecorderError.microphoneNotAuthorized
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)

        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            throw AudioRecorderError.engineSetupFailed("No audio input available")
        }

        // Create temp WAV file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("spvoice_recording_\(UUID().uuidString).wav")

        let outFormat = Self.outputFormat
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: tempURL, settings: outFormat.settings)
        } catch {
            throw AudioRecorderError.engineSetupFailed("Cannot create audio file: \(error.localizedDescription)")
        }

        guard let converter = AVAudioConverter(from: hwFormat, to: outFormat) else {
            throw AudioRecorderError.engineSetupFailed(
                "Cannot create audio converter: \(hwFormat.sampleRate)Hz/\(hwFormat.channelCount)ch -> \(outFormat.sampleRate)Hz/\(outFormat.channelCount)ch"
            )
        }

        // The input node tap must be installed using the hardware format. We resample
        // inside the callback to avoid AVAudioEngine format-mismatch faults.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let convertedBuffer = Self.convertBuffer(buffer, using: converter, to: outFormat) else {
                return
            }

            do {
                try file.write(from: convertedBuffer)
            } catch {
                Logger.audio.error("Write error: \(error.localizedDescription)")
            }

            let level = Self.audioLevel(from: convertedBuffer)
            Task { @MainActor [weak self] in
                self?.audioLevel = level
            }
        }

        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AudioRecorderError.engineSetupFailed(error.localizedDescription)
        }

        self.audioEngine = engine
        self.audioFile = file
        self.lastRecordingURL = tempURL
        self.recordingStartTime = Date()
        self.state = .recording

        // Max duration guard
        maxDurationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(SPVoiceConstants.Defaults.maxRecordingDuration))
            guard let self, self.state == .recording else { return }
            Logger.audio.warning("Max recording duration reached")
            self.cancelRecording()
        }

        Logger.audio.info("Recording started (hw: \(hwFormat.sampleRate)Hz \(hwFormat.channelCount)ch → 16kHz mono)")
    }

    func stopRecording() async throws -> URL {
        guard state == .recording else {
            throw AudioRecorderError.notRecording
        }

        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        guard duration >= SPVoiceConstants.Defaults.minRecordingDuration else {
            teardownEngine()
            state = .idle
            throw AudioRecorderError.recordingTooShort
        }

        state = .exporting
        teardownEngine()

        guard let url = lastRecordingURL else {
            state = .idle
            throw AudioRecorderError.engineSetupFailed("No recording file")
        }

        state = .idle
        Logger.audio.info("Recording stopped, duration: \(String(format: "%.1f", duration))s, file: \(url.lastPathComponent)")
        return url
    }

    func cancelRecording() {
        guard state == .recording else { return }
        teardownEngine()
        // Remove partial file
        if let url = lastRecordingURL {
            try? FileManager.default.removeItem(at: url)
            lastRecordingURL = nil
        }
        state = .idle
        audioLevel = 0
        Logger.audio.info("Recording cancelled")
    }

    // MARK: - Engine Teardown

    private func teardownEngine() {
        maxDurationTask?.cancel()
        maxDurationTask = nil

        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
        audioFile = nil
        audioLevel = 0
    }

    // MARK: - Cleanup

    func cleanupTempFiles() {
        guard let url = lastRecordingURL else { return }
        try? FileManager.default.removeItem(at: url)
        lastRecordingURL = nil
        Logger.audio.debug("Cleaned up temp audio file")
    }

    static func cleanupOrphanedFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil
        ) else { return }

        let orphans = contents.filter { $0.lastPathComponent.hasPrefix("spvoice_recording_") }
        for file in orphans {
            try? FileManager.default.removeItem(at: file)
        }
        if !orphans.isEmpty {
            Logger.audio.info("Cleaned up \(orphans.count) orphaned temp files")
        }
    }
}

// MARK: - Buffer Conversion

extension AudioRecorder {

    private static func convertBuffer(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to outputFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let sampleRateRatio = outputFormat.sampleRate / buffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(
            max(1, ceil(Double(buffer.frameLength) * sampleRateRatio) + 32)
        )

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputCapacity
        ) else {
            Logger.audio.error("Failed to allocate converted audio buffer")
            return nil
        }

        var error: NSError?
        var hasProvidedInput = false
        let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            if hasProvidedInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            hasProvidedInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            Logger.audio.error("Audio conversion failed: \(error.localizedDescription)")
            return nil
        }

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            return convertedBuffer.frameLength > 0 ? convertedBuffer : nil
        case .error:
            Logger.audio.error("Audio conversion returned error status")
            return nil
        @unknown default:
            Logger.audio.error("Audio conversion returned unknown status")
            return nil
        }
    }

    private static func audioLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        var sum: Float = 0
        for index in 0..<frameCount {
            let sample = channelData[index]
            sum += sample * sample
        }

        let rms = sqrtf(sum / Float(frameCount))
        let boosted = powf(min(rms * 14.0, 1.0), 0.6)
        return min(max(boosted, 0), 1)
    }
}

// MARK: - Errors

enum AudioRecorderError: Error, LocalizedError, Equatable {
    case microphoneNotAuthorized
    case notRecording
    case recordingTooShort
    case recordingTooLong
    case engineSetupFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphoneNotAuthorized: return "Microphone permission not granted"
        case .notRecording: return "Not currently recording"
        case .recordingTooShort: return "Recording too short"
        case .recordingTooLong: return "Recording exceeded maximum duration"
        case .engineSetupFailed(let msg): return "Audio engine setup failed: \(msg)"
        }
    }
}
