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
/// - エラー: Basso.aiff（低い音）
public class SoundPlayer {
    private let startSoundPath = "/System/Library/Sounds/Ping.aiff"
    private let stopSoundPath = "/System/Library/Sounds/Pop.aiff"
    private let errorSoundPath = "/System/Library/Sounds/Basso.aiff"

    /// 再生中の AVAudioPlayer への強参照を保持（再生完了前に解放されないように）
    private var activePlayer: AVAudioPlayer?

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
        playSound(errorSoundPath)
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

    private func playSound(_ path: String) {
        do {
            let player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            activePlayer = player
            player.play()
        } catch {
            // SE 再生失敗は致命的ではないので、静かに無視
        }
    }
}
