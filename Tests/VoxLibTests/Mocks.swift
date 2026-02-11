import Foundation
import AVFoundation
@testable import VoxLib

// MARK: - MockAudioCapture

final class MockAudioCapture: AudioCaptureProtocol {
    var isRunning = false
    var startCallCount = 0
    var stopCallCount = 0
    var shouldThrow: Error?
    var bufferHandler: ((AVAudioPCMBuffer) -> Void)?

    func start(bufferHandler: @escaping (AVAudioPCMBuffer) -> Void) throws {
        if let error = shouldThrow {
            throw error
        }
        startCallCount += 1
        isRunning = true
        self.bufferHandler = bufferHandler
    }

    func stop() {
        stopCallCount += 1
        isRunning = false
        bufferHandler = nil
    }
}

// MARK: - MockSpeechRecognizer

final class MockSpeechRecognizer: SpeechRecognizerProtocol {
    var isStreaming: Bool = true
    var startCallCount = 0
    var stopCallCount = 0
    var cancelCallCount = 0
    var lastPromptContext: [String] = []

    var onPartialResult: ((String) -> Void)?
    var onFinalResult: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?

    func setPromptContext(_ texts: [String]) {
        lastPromptContext = texts
    }

    func startRecognition(
        locale: Locale,
        onDeviceOnly: Bool,
        onPartialResult: @escaping (String) -> Void,
        onFinalResult: @escaping (String, Bool) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        startCallCount += 1
        self.onPartialResult = onPartialResult
        self.onFinalResult = onFinalResult
        self.onError = onError
    }

    func stopRecognition() {
        stopCallCount += 1
    }

    func cancelRecognition() {
        cancelCallCount += 1
    }

    func feedAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // no-op in mock
    }

    // テストヘルパー: 部分結果をシミュレート
    func simulatePartialResult(_ text: String) {
        onPartialResult?(text)
    }

    // テストヘルパー: 最終結果をシミュレート
    func simulateFinalResult(_ text: String, isUserInitiated: Bool) {
        onFinalResult?(text, isUserInitiated)
    }

    // テストヘルパー: エラーをシミュレート
    func simulateError(_ error: Error) {
        onError?(error)
    }
}

// MARK: - MockSoundPlayer

/// テスト用 SoundPlayer。playStartAndWait のコールバックを同期的に呼ぶ。
final class MockSoundPlayer: SoundPlayer {
    override func playStartAndWait(completion: @escaping () -> Void) {
        completion()
    }
}

// MARK: - MockRewriterBackend

final class MockRewriterBackend: RewriterBackend {
    var rewriteCallCount = 0
    var lastInput: String?
    var result: Result<String, Error> = .success("")
    var delay: TimeInterval = 0

    func rewrite(_ text: String, completion: @escaping (Result<String, Error>) -> Void) {
        rewriteCallCount += 1
        lastInput = text
        let result = self.result
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                completion(result)
            }
        } else {
            completion(result)
        }
    }
}
