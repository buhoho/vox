import Foundation
import AVFoundation

public protocol AudioCaptureProtocol {
    func start(bufferHandler: @escaping (AVAudioPCMBuffer) -> Void) throws
    func stop()
}

public final class AudioCapture: AudioCaptureProtocol {
    private var engine = AVAudioEngine()

    public init() {}

    public func start(bufferHandler: @escaping (AVAudioPCMBuffer) -> Void) throws {
        let inputNode = engine.inputNode

        // format に nil を渡すとハードウェアの native format が自動使用される
        // Bluetooth ヘッドセット等で sample rate が変わっても安全
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            bufferHandler(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            // engine.start() 失敗時、installTap を cleanup しないと次回 start() でクラッシュする
            inputNode.removeTap(onBus: 0)
            throw VoxError.audioEngineStartFailed(error)
        }
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // engine を新規インスタンスに置き換え、次の start() で format 不一致を防ぐ
        engine = AVAudioEngine()
    }
}
