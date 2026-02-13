import Foundation
import AVFoundation

/// 効果音を再生するクラス。
///
/// AVAudioPlayer を使用し、再生のたびに新規インスタンスを生成する。
/// AVAudioEngine はマイクキャプチャの開始・停止でオーディオルーティングが変わり、
/// 再生状態が壊れるため使用しない。
///
/// Bluetooth ヘッドセット環境では、マイクキャプチャ中は HFP モードで音質が劣化するため、
/// SE はマイク起動前・停止後にのみ再生する（VoxSession 側で制御）。
///
/// - 開始: Ping.aiff（高めの短い音）
/// - 終了: Pop.aiff（ポップ音）
/// - 処理中: Frog.aiff（カエルの鳴き声、ループ再生）
/// - 書き込み完了: Funk.aiff（ファンキーな完了音）
/// - エラー: Basso.aiff（低い音）
public class SoundPlayer {
    private let startSoundPath = "/System/Library/Sounds/Ping.aiff"
    private let stopSoundPath = "/System/Library/Sounds/Pop.aiff"
    private let processingSoundPath = "/System/Library/Sounds/Frog.aiff"
    private let completionSoundPath = "/System/Library/Sounds/Funk.aiff"
    private let errorSoundPath = "/System/Library/Sounds/Basso.aiff"

    /// 再生中の AVAudioPlayer への強参照を保持（再生完了前に解放されないように）
    private var activePlayer: AVAudioPlayer?

    /// 処理中ループ用タイマー
    private var loopTimer: DispatchSourceTimer?
    private let loopInterval: TimeInterval = 1.5

    /// start/end 以外の SE 音量（start/end は Bluetooth HFP の制約で元々小さめに聞こえるため、
    /// 他の SE との落差を緩和する）
    private let effectVolume: Float = 0.7

    public init() {}

    // MARK: - Public API

    /// 録音開始 SE を再生（非同期、即座に返る）
    public func playStart() {
        playSound(startSoundPath)
    }

    /// 録音終了 SE を再生（非同期、即座に返る）
    public func playStop() {
        playSound(stopSoundPath)
    }

    /// エラー SE を再生（非同期、即座に返る）
    public func playError() {
        playSound(errorSoundPath, volume: effectVolume)
    }

    /// 処理中ループ SE を開始（Tink.aiff を一定間隔で繰り返し再生）
    public func startProcessingLoop() {
        stopProcessingLoop()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + loopInterval, repeating: loopInterval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.playSound(self.processingSoundPath, volume: self.effectVolume)
        }
        loopTimer = timer
        timer.resume()
    }

    /// 処理中ループ SE を停止（冪等: タイマーがなければ no-op）
    public func stopProcessingLoop() {
        loopTimer?.cancel()
        loopTimer = nil
    }

    /// 書き込み完了 SE を再生（非同期、即座に返る）
    public func playCompletion() {
        playSound(completionSoundPath, volume: effectVolume)
    }

    /// 録音開始 SE を再生し、音のアタック部分が鳴り終わるまで待つ。
    ///
    /// Ping.aiff のファイル長は 1.5 秒だが、アタック音（ピン）は最初の約 0.1 秒に集中している。
    /// 0.3 秒待てばアタック部分は十分に再生される。残りのリバーブ/減衰部分は
    /// マイク起動（HFP 切り替え）で途切れる可能性があるが、主要な音は聞こえた後。
    public func playStartAndWait(completion: @escaping () -> Void) {
        playSound(startSoundPath)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            completion()
        }
    }

    /// エラー SE を再生し、鳴り終わるまで待つ。
    ///
    /// プロセスが即座に終了すると音が鳴り終わる前に死ぬため、
    /// エラー終了時はこのメソッドを使い、completion 内で exit() を呼ぶ。
    public func playErrorAndWait(completion: @escaping () -> Void) {
        do {
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: errorSoundPath))
            player.volume = effectVolume
            activePlayer = player
            player.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + player.duration + 0.1) {
                completion()
            }
        } catch {
            completion()
        }
    }

    // MARK: - Private

    private func playSound(_ path: String, volume: Float = 1.0) {
        do {
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            player.volume = volume
            activePlayer = player
            player.play()
        } catch {
            // SE 再生失敗は致命的ではないので、静かに無視
        }
    }
}
