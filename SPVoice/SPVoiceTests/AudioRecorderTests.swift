import XCTest
@testable import SPVoice

@MainActor
final class AudioRecorderTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState() {
        let recorder = AudioRecorder()
        XCTAssertEqual(recorder.state, .idle)
        XCTAssertEqual(recorder.audioLevel, 0.0)
        XCTAssertNil(recorder.lastRecordingURL)
    }

    // MARK: - State Transitions

    func testCancelFromIdle() {
        let recorder = AudioRecorder()
        recorder.cancelRecording()
        XCTAssertEqual(recorder.state, .idle, "Cancel from idle should remain idle")
    }

    func testStopWithoutRecordingThrows() async {
        let recorder = AudioRecorder()
        do {
            _ = try await recorder.stopRecording()
            XCTFail("Expected notRecording error")
        } catch {
            XCTAssertTrue(error is AudioRecorderError)
            if let err = error as? AudioRecorderError {
                XCTAssertEqual(err, .notRecording)
            }
        }
    }

    // MARK: - Orphaned File Cleanup

    func testCleanupOrphanedFiles() {
        // Create a fake orphaned file
        let tempDir = FileManager.default.temporaryDirectory
        let fakeFile = tempDir.appendingPathComponent("spvoice_recording_test_orphan.m4a")
        FileManager.default.createFile(atPath: fakeFile.path, contents: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fakeFile.path))

        AudioRecorder.cleanupOrphanedFiles()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fakeFile.path))
    }

    func testCleanupDoesNotRemoveOtherFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        let otherFile = tempDir.appendingPathComponent("some_other_file.m4a")
        FileManager.default.createFile(atPath: otherFile.path, contents: nil)

        AudioRecorder.cleanupOrphanedFiles()
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherFile.path))

        // Cleanup
        try? FileManager.default.removeItem(at: otherFile)
    }
}
