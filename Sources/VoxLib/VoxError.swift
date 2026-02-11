import Foundation

public enum VoxError: Error, LocalizedError {
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied
    case speechRecognizerUnavailable
    case onDeviceModelNotAvailable
    case audioEngineStartFailed(Error)
    case configLoadFailed(Error)
    case rewriteFailed(Error)
    case apiKeyMissing(String)

    public var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access denied. Grant permission in System Settings > Privacy & Security > Microphone."
        case .speechRecognitionPermissionDenied:
            return "Speech recognition permission denied. Grant permission in System Settings > Privacy & Security > Speech Recognition."
        case .speechRecognizerUnavailable:
            return "Speech recognizer is not available for the specified locale."
        case .onDeviceModelNotAvailable:
            return "On-device speech recognition model is not downloaded. Go to System Settings > Keyboard > Dictation > Languages to add it."
        case .audioEngineStartFailed(let error):
            return "Failed to start audio engine: \(error.localizedDescription)"
        case .configLoadFailed(let error):
            return "Failed to load config: \(error.localizedDescription)"
        case .rewriteFailed(let error):
            return "Rewrite failed: \(error.localizedDescription)"
        case .apiKeyMissing(let name):
            return "API key not found in environment variable: \(name)"
        }
    }
}
