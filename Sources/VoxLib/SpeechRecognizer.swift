import Foundation
import Speech

public protocol SpeechRecognizerProtocol {
    var isStreaming: Bool { get }
    var supportsPromptContext: Bool { get }
    func setPromptContext(_ texts: [String])
    func startRecognition(
        locale: Locale,
        onDeviceOnly: Bool,
        onPartialResult: @escaping (String) -> Void,
        onFinalResult: @escaping (String, Bool) -> Void,
        onError: @escaping (Error) -> Void
    )
    func stopRecognition()
    func cancelRecognition()
    func feedAudioBuffer(_ buffer: AVAudioPCMBuffer)
}

// デフォルト実装（ストリーミングモードでは不要なので no-op）
extension SpeechRecognizerProtocol {
    public var supportsPromptContext: Bool { false }
    public func setPromptContext(_ texts: [String]) { }
}

public final class SpeechRecognizer: SpeechRecognizerProtocol {
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isStoppingByUser = false

    /// タスク世代番号。startRecognition() のたびにインクリメントし、
    /// 旧タスクからの遅延コールバックを無視するために使う。
    private var taskGeneration: UInt64 = 0

    private var onPartialResult: ((String) -> Void)?
    private var onFinalResult: ((String, Bool) -> Void)?
    private var onError: ((Error) -> Void)?

    public var isStreaming: Bool { true }

    public init() {}

    public func startRecognition(
        locale: Locale,
        onDeviceOnly: Bool,
        onPartialResult: @escaping (String) -> Void,
        onFinalResult: @escaping (String, Bool) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.onPartialResult = onPartialResult
        self.onFinalResult = onFinalResult
        self.onError = onError

        self.isStoppingByUser = false
        taskGeneration += 1
        let expectedGeneration = taskGeneration

        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            DispatchQueue.main.async {
                onError(VoxError.speechRecognizerUnavailable)
            }
            return
        }
        self.recognizer = recognizer

        if onDeviceOnly && !recognizer.supportsOnDeviceRecognition {
            DispatchQueue.main.async {
                onError(VoxError.onDeviceModelNotAvailable)
            }
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if onDeviceOnly {
            request.requiresOnDeviceRecognition = true
        }
        self.recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }

            // 旧タスクからの遅延コールバックを無視
            guard self.taskGeneration == expectedGeneration else { return }

            if let error = error {
                DispatchQueue.main.async {
                    // DispatchQueue.main.async 内でも世代チェック
                    guard self.taskGeneration == expectedGeneration else { return }
                    self.onError?(error)
                }
                return
            }

            guard let result = result else { return }

            let text = result.bestTranscription.formattedString

            if result.isFinal {
                DispatchQueue.main.async {
                    guard self.taskGeneration == expectedGeneration else { return }
                    let isUser = self.isStoppingByUser
                    self.onFinalResult?(text, isUser)
                }
            } else {
                DispatchQueue.main.async {
                    guard self.taskGeneration == expectedGeneration else { return }
                    self.onPartialResult?(text)
                }
            }
        }
    }

    public func stopRecognition() {
        isStoppingByUser = true
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionRequest = nil
        recognitionTask = nil
    }

    public func cancelRecognition() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    public func feedAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }
}
