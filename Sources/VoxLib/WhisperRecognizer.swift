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
    public func prepare(completion: @escaping (Error?) -> Void) {
        modelState = .loading
        Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let config = WhisperKitConfig(model: self.modelVariant)
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
                        promptTokens: promptTokens
                    )
                    let results = try await whisperKit.transcribe(
                        audioArray: samples, decodeOptions: options
                    )

                    // Phase 1: セグメントレベルフィルタ
                    var filteredSegments: [String] = []
                    for (i, result) in results.enumerated() {
                        for seg in result.segments {
                            let noSpeechDiscard = seg.noSpeechProb > 0.6
                            let hallucinationDiscard = Self.isHallucinationPhrase(seg.text)
                            let discarded = noSpeechDiscard || hallucinationDiscard
                            let reason = noSpeechDiscard ? "noSpeech" : hallucinationDiscard ? "hallucination" : ""
                            print("[Whisper] Seg\(i): noSpeech=\(String(format: "%.3f", seg.noSpeechProb)), avgLogprob=\(String(format: "%.3f", seg.avgLogprob)), text=\"\(seg.text.prefix(50))\"\(discarded ? " [DISCARDED:\(reason)]" : "")")
                            if !discarded {
                                filteredSegments.append(seg.text)
                            }
                        }
                    }

                    let rawText = filteredSegments.joined(separator: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    // Phase 2: テキストレベルフィルタ（結合後テキストの末尾除去）
                    let text = Self.filterHallucinations(rawText)

                    if text != rawText {
                        print("[Whisper] Hallucination filtered: \"\(rawText)\" → \"\(text.isEmpty ? "(empty)" : text)\"")
                    }
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

    /// ハルシネーションフレーズの全バリエーション（原文 × 句読点末尾）を事前生成
    /// 検索時にバリエーション生成のコストを避ける
    private static let hallucinationVariants: [String] = {
        hallucinationPhrasesRaw.flatMap { phrase in
            trailingPunctuation.map { punct in phrase + punct }
        }
    }()

    /// セグメントのテキスト全体がハルシネーションフレーズに一致するか判定する。
    /// 前後の空白・句読点を除去してから比較する。大文字小文字も無視。
    static func isHallucinationPhrase(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return false }
        return hallucinationVariants.contains { cleaned == $0 }
    }

    /// テキストから既知のハルシネーションフレーズを除去する。
    /// - テキスト全体がハルシネーション → 空文字
    /// - テキスト末尾にハルシネーションが付加 → その部分を除去
    static func filterHallucinations(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // 全体一致チェック
        if isHallucinationPhrase(trimmed) {
            return ""
        }

        // 末尾除去: 各フレーズバリエーションで直接 hasSuffix チェック
        var result = trimmed
        for variant in hallucinationVariants {
            if result.hasSuffix(variant) && result.count > variant.count {
                result = String(result.dropLast(variant.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        return result
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
