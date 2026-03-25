import Foundation
import AVFoundation

public protocol AudioCaptureProtocol {
    func start(bufferHandler: @escaping (AVAudioPCMBuffer) -> Void) throws
    func stop()
}

public final class AudioCapture: AudioCaptureProtocol {
    private var engine = AVAudioEngine()
    private var currentBufferHandler: ((AVAudioPCMBuffer) -> Void)?
    private var configObserver: NSObjectProtocol?

    public init() {}

    public func start(bufferHandler: @escaping (AVAudioPCMBuffer) -> Void) throws {
        currentBufferHandler = bufferHandler

        installTapAndStart()

        // Bluetooth プロファイル切り替え（A2DP ↔ HFP）時に AVAudioEngine が
        // 自動停止するため、通知を受けてタップ再設定 → エンジン再起動する。
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.currentBufferHandler != nil else { return }
            if !self.engine.isRunning {
                self.installTapAndStart()
            }
        }
    }

    public func stop() {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
        currentBufferHandler = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // engine を新規インスタンスに置き換え、次の start() で format 不一致を防ぐ
        engine = AVAudioEngine()
    }

    // MARK: - Private

    private func installTapAndStart() {
        let inputNode = engine.inputNode

        // 既存のタップがあれば除去（再設定時の二重登録を防止）
        inputNode.removeTap(onBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.currentBufferHandler?(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("[AudioCapture] Engine restart failed: \(error.localizedDescription)")
        }
    }
}
