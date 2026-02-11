import Foundation
import AVFoundation
import Speech
import ApplicationServices

public struct PermissionChecker {

    /// マイクと音声認識の権限を同期的に要求する。
    /// 権限が拒否された場合はエラーメッセージを表示して exit(1)。
    public static func requestAll() {
        requestMicrophoneAccess()
        requestSpeechRecognitionAccess()
    }

    /// アクセシビリティ権限を確認し、未許可なら許可ダイアログを表示する。
    /// 自動ペースト（Cmd+V シミュレート）に必要。
    /// - Returns: 許可済みなら true
    @discardableResult
    public static func checkAccessibility(prompt: Bool = true) -> Bool {
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        } else {
            return AXIsProcessTrusted()
        }
    }

    /// on-device 認識モデルの利用可否を確認
    public static func checkOnDeviceAvailability(locale: Locale) -> Bool {
        guard let recognizer = SFSpeechRecognizer(locale: locale) else {
            return false
        }
        return recognizer.supportsOnDeviceRecognition
    }

    // MARK: - Private

    private static func requestMicrophoneAccess() {
        var done = false
        var granted = false

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { g in
                granted = g
                done = true
            }
            while !done {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            }
        case .denied, .restricted:
            granted = false
            done = true
        @unknown default:
            return
        }

        if !granted {
            print("Error: Microphone access denied.")
            print("Grant permission in System Settings > Privacy & Security > Microphone.")
            Darwin.exit(1)
        }
    }

    private static func requestSpeechRecognitionAccess() {
        var done = false
        var granted = false

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                granted = (status == .authorized)
                done = true
            }
            while !done {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            }
        case .denied, .restricted:
            granted = false
            done = true
        @unknown default:
            return
        }

        if !granted {
            print("Error: Speech recognition permission denied.")
            print("Grant permission in System Settings > Privacy & Security > Speech Recognition.")
            Darwin.exit(1)
        }
    }
}
