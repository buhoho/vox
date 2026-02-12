import Foundation
import AVFoundation
import WhisperKit

public final class WhisperRecognizer: SpeechRecognizerProtocol {
    public var isStreaming: Bool { false }

    // MARK: - モデル状態

    public enum ModelState {
        case notLoaded
        case loading
        case ready
        case failed(Error)
    }

    public private(set) var modelState: ModelState = .notLoaded

    public var isReady: Bool {
        if case .ready = modelState { return true }
        return false
    }

    public var statusMessage: String? {
        switch modelState {
        case .notLoaded:
            return "Whisper model not loaded."
        case .loading:
            return "Whisper model loading... Please wait."
        case .ready:
            return nil
        case .failed(let error):
            return "Whisper model load failed: \(error.localizedDescription)"
        }
    }

    // large 系モデルは promptTokens で推論が壊れるため、コンテキストキャッシュ非対応
    public var supportsPromptContext: Bool {
        let lower = modelVariant.lowercased()
        return lower == "base" || lower == "small" || lower == "tiny"
    }

    // WhisperKit インスタンス（prepare で初期化）
    private var whisperKit: WhisperKit?
    private let modelVariant: String
    private let whisperLanguage: String?

    // オーディオバッファ蓄積（serial queue で保護）
    private let bufferQueue = DispatchQueue(label: "com.vox.whisper.buffer")
    private var audioSamples: [Float] = []

    // フォーマット変換（オーディオスレッド上でのみ使用）
    private var converter: AVAudioConverter?
    private let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false
    )!

    // コンテキストキャッシュ（VoxSession から setPromptContext 経由でセット）
    private var promptContextTexts: [String] = []
    // 111 = maxTokenContext(224) / 2 - 1
    // WhisperKit の TextDecoder.swift も同じ計算で suffix を取る。
    // この値は Whisper アーキテクチャに依存しており、
    // WhisperKit の Constants.maxTokenContext が変わった場合は更新が必要。
    private static let maxPromptTokens = 111

    // コールバック
    private var onFinalResult: ((String, Bool) -> Void)?
    private var onError: ((Error) -> Void)?

    // 推論タスク（キャンセル用）
    private var transcriptionTask: Task<Void, Never>?

    public init(model: String = "base", language: String? = "ja") {
        self.modelVariant = model
        self.whisperLanguage = language
    }

    // MARK: - モデル初期化

    /// WhisperKit モデルの非同期ロード。RunLoop 開始後に呼ぶ。
    /// 状態遷移: notLoaded → loading → ready / failed
    /// ロード失敗時はキャッシュを削除してリトライする（不完全ダウンロードからの自動復旧）。
    public func prepare(completion: @escaping (Error?) -> Void) {
        modelState = .loading
        Task.detached { [weak self] in
            guard let self = self else { return }
            let config = WhisperKitConfig(model: self.modelVariant)

            // 1回目: 通常ロード
            do {
                let kit = try await WhisperKit(config)
                self.whisperKit = kit
                DispatchQueue.main.async {
                    self.modelState = .ready
                    completion(nil)
                }
                return
            } catch {
                print("[Whisper] Model load failed: \(error.localizedDescription)")
                print("[Whisper] Cleaning model cache and retrying...")
            }

            // キャッシュ削除 → 2回目: 再ダウンロード
            Self.cleanModelCache()
            do {
                let kit = try await WhisperKit(config)
                self.whisperKit = kit
                DispatchQueue.main.async {
                    self.modelState = .ready
                    completion(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    self.modelState = .failed(error)
                    completion(error)
                }
            }
        }
    }

    /// WhisperKit のモデルキャッシュディレクトリを削除する。
    /// 不完全なダウンロードや破損したモデルファイルをクリーンアップする。
    private static func cleanModelCache() {
        let basePath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
        if FileManager.default.fileExists(atPath: basePath.path) {
            try? FileManager.default.removeItem(at: basePath)
            print("[Whisper] Cleaned model cache: \(basePath.path)")
        }
    }

    // MARK: - SpeechRecognizerProtocol

    public func setPromptContext(_ texts: [String]) {
        promptContextTexts = texts
    }

    public func startRecognition(
        locale: Locale,
        onDeviceOnly: Bool,
        onPartialResult: @escaping (String) -> Void,
        onFinalResult: @escaping (String, Bool) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        bufferQueue.async { self.audioSamples.removeAll(keepingCapacity: true) }
        converter = nil
        self.onFinalResult = onFinalResult
        self.onError = onError

        // モデル未ロード時は即エラー（録音を無駄に続けさせない）
        if whisperKit == nil {
            DispatchQueue.main.async {
                onError(VoxError.speechRecognizerUnavailable)
            }
        }
    }

    public func feedAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // AVAudioConverter の lazy 初期化（オーディオスレッド上、初回のみ）
        if converter == nil {
            converter = AVAudioConverter(from: buffer.format, to: outputFormat)
        }
        guard let converter = converter else { return }

        // リサンプリング: 入力フォーマット → 16kHz mono Float32
        let ratio = 16000.0 / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat, frameCapacity: outputFrameCount
        ) else { return }

        var consumed = false
        converter.convert(to: outputBuffer, error: nil) { _, outStatus in
            if consumed { outStatus.pointee = .noDataNow; return nil }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        // serial queue でスレッドセーフに追加
        if let channelData = outputBuffer.floatChannelData {
            let samples = Array(UnsafeBufferPointer(
                start: channelData[0], count: Int(outputBuffer.frameLength)
            ))
            bufferQueue.async { self.audioSamples.append(contentsOf: samples) }
        }
    }

    public func stopRecognition() {
        guard let whisperKit = whisperKit else {
            DispatchQueue.main.async { self.onError?(VoxError.speechRecognizerUnavailable) }
            return
        }

        // メインスレッドで値をキャプチャ（bufferQueue との data race を防止）
        let contextTexts = self.promptContextTexts

        // serial queue からバッファを取得してから推論
        bufferQueue.async { [weak self] in
            guard let self = self else { return }
            let samples = self.audioSamples
            self.audioSamples.removeAll(keepingCapacity: true)

            guard !samples.isEmpty else {
                DispatchQueue.main.async { self.onFinalResult?("", true) }
                return
            }

            let duration = Double(samples.count) / 16000.0
            print("[Whisper] Audio: \(String(format: "%.1f", duration))s (\(samples.count) samples)")

            let language = self.whisperLanguage

            // Task.detached: アクターコンテキスト継承を回避
            self.transcriptionTask = Task.detached {
                do {
                    let promptTokens = Self.buildPromptTokens(
                        contextTexts: contextTexts, whisperKit: whisperKit
                    )
                    let options = DecodingOptions(
                        language: language,
                        skipSpecialTokens: true,
                        promptTokens: promptTokens
                    )
                    let results = try await whisperKit.transcribe(
                        audioArray: samples, decodeOptions: options
                    )

                    // セグメントレベルフィルタ
                    // 全セグメントを平坦化して、最後のセグメントを特定
                    let allSegments = results.flatMap { $0.segments }
                    var filteredSegments: [String] = []
                    for (idx, seg) in allSegments.enumerated() {
                        let isLast = idx == allSegments.count - 1
                        let noSpeechDiscard = seg.noSpeechProb > 0.6
                        let hallucinationDiscard = Self.isHallucinationPhrase(seg.text)
                        let suspiciousDiscard = isLast && Self.isSuspiciousPhrase(seg.text)
                            && (seg.noSpeechProb > 0.3 || seg.avgLogprob < -0.7)
                        let discarded = noSpeechDiscard || hallucinationDiscard || suspiciousDiscard
                        let reason = noSpeechDiscard ? "noSpeech"
                            : hallucinationDiscard ? "hallucination"
                            : suspiciousDiscard ? "suspicious" : ""
                        print("[Whisper] Seg\(idx): noSpeech=\(String(format: "%.3f", seg.noSpeechProb)), avgLogprob=\(String(format: "%.3f", seg.avgLogprob)), text=\"\(seg.text.prefix(50))\"\(discarded ? " [DISCARDED:\(reason)]" : "")")
                        if !discarded {
                            filteredSegments.append(Self.stripSpecialTokens(seg.text))
                        }
                    }

                    let text = filteredSegments.joined(separator: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    print("[Whisper] Result: \"\(text.isEmpty ? "(empty)" : String(text.prefix(80)))\"")

                    guard !Task.isCancelled else { return }
                    DispatchQueue.main.async { self.onFinalResult?(text, true) }
                } catch {
                    guard !Task.isCancelled else { return }
                    DispatchQueue.main.async { self.onError?(error) }
                }
            }
        }
    }

    // MARK: - Prompt Context

    /// コンテキストテキストから promptTokens を構築する。
    ///
    /// 1. 新しい順にテキスト単位で選択（上限内に収まるものだけ）
    /// 2. 選択したテキストを古い→新しい順に並べ替え
    /// 3. 先頭スペース付与 + 特殊トークンフィルタ
    ///
    /// NOTE: startOfPreviousToken は含めない。
    /// WhisperKit の prefillDecoderInputs が自動的に
    /// [startOfPreviousToken] + promptTokens + prefillTokens として付加する。
    private static func buildPromptTokens(
        contextTexts: [String],
        whisperKit: WhisperKit
    ) -> [Int]? {
        guard !contextTexts.isEmpty,
              let tokenizer = whisperKit.tokenizer else { return nil }

        let specialTokenBegin = tokenizer.specialTokens.specialTokenBegin

        // Phase 1: 新しい順にトークナイズし、上限内に収まるテキストを選択
        var tokenGroups: [[Int]] = []
        var totalTokens = 0
        for text in contextTexts {  // 新しい順
            let encoded = tokenizer.encode(
                text: " " + text.trimmingCharacters(in: .whitespaces)
            ).filter { $0 < specialTokenBegin }
            if totalTokens + encoded.count > maxPromptTokens {
                // 意図的にテキスト単位で切り捨て。最初のテキストが上限超えの場合も
                // コンテキストなしにフォールバックする（途中切りによるハルシネーション防止）
                break
            }
            tokenGroups.append(encoded)
            totalTokens += encoded.count
        }

        guard !tokenGroups.isEmpty else { return nil }

        // Phase 2: 古い→新しいの時系列順にフラット化
        return tokenGroups.reversed().flatMap { $0 }
    }

    // MARK: - Special Token Cleanup

    /// WhisperKit が出力テキストに含める特殊トークン（`<|...|>` 形式）を除去する。
    /// `skipSpecialTokens: true` が正しく動作していれば不要だが、
    /// 万一漏れた場合にも出力を汚さない安全策。
    private static let specialTokenPattern = try! NSRegularExpression(
        pattern: "<\\|[^|]*\\|>", options: []
    )

    static func stripSpecialTokens(_ text: String) -> String {
        specialTokenPattern.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: ""
        )
    }

    // MARK: - Hallucination Filter

    /// Whisper が無音・雑音時に生成する既知のハルシネーションフレーズ（原文）。
    /// YouTube 等の動画字幕データで学習されたため、動画の定型フレーズが出力される。
    private static let hallucinationPhrasesRaw: [String] = [
        // 日本語
        "ご視聴ありがとうございました",
        "ご視聴ありがとうございます",
        "見てくれてありがとう",
        "最後までご覧いただきありがとうございました",
        "最後までご覧いただきありがとうございます",
        "ご覧いただきありがとうございました",
        "ご覧いただきありがとうございます",
        "チャンネル登録お願いします",
        "チャンネル登録よろしくお願いします",
        "チャンネル登録よろしくお願いいたします",
        "高評価チャンネル登録よろしくお願いします",
        // 英語（多言語モデル用）
        "thank you for watching",
        "thanks for watching",
        "please subscribe",
        "don't forget to subscribe",
        "like and subscribe",
        "subtitles by the amara.org community",
        "transcription by castingwords",
    ]

    /// 句読点末尾バリエーション（空文字 = 句読点なし も含む）
    private static let trailingPunctuation = ["", "。", "、", "！", "!", "？", "?", ".", "…"]

    /// フレーズ × 句読点バリエーションを生成
    private static func makeVariants(_ phrases: [String]) -> [String] {
        phrases.flatMap { phrase in
            trailingPunctuation.map { punct in phrase + punct }
        }
    }

    private static let hallucinationVariants = makeVariants(hallucinationPhrasesRaw)

    /// 疑わしいフレーズ（原文）。
    /// 実際に使われることもあるが、最後のセグメントで確信度が低い場合のみ除去する。
    private static let suspiciousPhrasesRaw: [String] = [
        "ありがとうございました",
        "ありがとうございます",
        "お疲れ様でした",
        "お疲れ様です",
        "おやすみなさい",
        "さようなら",
        "bye",
        "goodbye",
        "thank you",
        "thanks",
    ]

    private static let suspiciousVariants = makeVariants(suspiciousPhrasesRaw)

    /// セグメントテキストがハルシネーション確定フレーズに一致するか
    static func isHallucinationPhrase(_ text: String) -> Bool {
        let cleaned = stripSpecialTokens(text)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !cleaned.isEmpty && hallucinationVariants.contains { cleaned == $0 }
    }

    /// セグメントテキストが疑わしいフレーズに一致するか（メトリクスとの複合条件で使用）
    static func isSuspiciousPhrase(_ text: String) -> Bool {
        let cleaned = stripSpecialTokens(text)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !cleaned.isEmpty && suspiciousVariants.contains { cleaned == $0 }
    }

    public func cancelRecognition() {
        // 進行中の推論をキャンセル
        transcriptionTask?.cancel()
        transcriptionTask = nil
        // バッファをクリア
        bufferQueue.async { self.audioSamples.removeAll(keepingCapacity: true) }
        converter = nil
        onFinalResult = nil
        onError = nil
    }
}
