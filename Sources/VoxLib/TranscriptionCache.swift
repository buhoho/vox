import Foundation

/// 直近のリライト済みテキストをタイムスタンプ付きでキャッシュする。
/// WhisperKit の promptTokens 構築に使用し、連続入力時の認識精度を向上させる。
///
/// メインスレッドでのみアクセスされるため、同期処理不要。
public final class TranscriptionCache {
    private var entries: [(text: String, timestamp: Date)] = []
    private let dateProvider: () -> Date

    public init(dateProvider: @escaping () -> Date = { Date() }) {
        self.dateProvider = dateProvider
    }

    /// キャッシュにテキストを追加
    func add(_ text: String) {
        entries.append((text: text, timestamp: dateProvider()))
    }

    /// 指定秒数以内のエントリを新しい順に返す。
    /// 呼び出し時に古いエントリを自動除去する（lazy cleanup）。
    func recentTexts(within seconds: TimeInterval) -> [String] {
        let cutoff = dateProvider().addingTimeInterval(-seconds)
        entries.removeAll { $0.timestamp < cutoff }
        return entries.reversed().map { $0.text }
    }

    /// キャッシュをクリア
    func clear() {
        entries.removeAll()
    }
}
