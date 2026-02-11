import Foundation

/// テキスト変化を監視し、一定時間変化がなければ「無音」と判定するクラス。
///
/// SpeechRecognizer の partialResult テキストを `onTextChanged()` で受け取り、
/// `timeout` 秒間テキストに変化がなければ `onSilence` コールバックを呼ぶ。
///
/// class にした理由: Timer は参照型であり、Timer.scheduledTimer の target は
/// self を参照する。struct だと値コピーが発生し、Timer の invalidate が
/// 元のインスタンスに届かない。class にすることで参照が安定する。
public final class SilenceDetector {
    private var timer: Timer?
    private var lastText: String = ""
    private var timeout: TimeInterval = 5.0
    private var onSilence: (() -> Void)?

    public init() {}

    /// 監視を開始する。
    ///
    /// - Parameters:
    ///   - timeout: テキストが変化しない最大秒数。これを超えると onSilence が呼ばれる。
    ///   - onSilence: 無音タイムアウト時に呼ばれるコールバック（メインスレッドで呼ばれる）。
    public func start(timeout: TimeInterval, onSilence: @escaping () -> Void) {
        self.timeout = timeout
        self.onSilence = onSilence
        self.lastText = ""
        resetTimer()
    }

    /// テキストが変化したことを通知する。
    ///
    /// タイマーがリセットされ、timeout 秒のカウントダウンが再開される。
    /// テキストが前回と同じ場合はリセットしない（無意味なリセットを防ぐ）。
    public func onTextChanged(_ text: String) {
        guard text != lastText else { return }
        lastText = text
        resetTimer()
    }

    /// 監視を停止する。タイマーを無効化し、onSilence は呼ばれなくなる。
    public func stop() {
        timer?.invalidate()
        timer = nil
        onSilence = nil
        lastText = ""
    }

    // MARK: - Private

    private func resetTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            self.onSilence?()
        }
    }
}
