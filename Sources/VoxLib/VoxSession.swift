import Foundation
#if canImport(AppKit)
import AppKit
#endif
import AVFoundation

public final class VoxSession {
    public enum State { case idle, listening, processing }
    public private(set) var state: State = .idle

    // protocol 経由の依存（テストでモック差し替え）
    private let audioCapture: AudioCaptureProtocol
    private let speechRecognizer: SpeechRecognizerProtocol
    private let rewriter: RewriterBackend

    // class の直接利用
    private let silenceDetector: SilenceDetector
    private let soundPlayer: SoundPlayer
    private var durationTimer: Timer?
    private let outputManager: OutputManager
    private let terminalUI: TerminalUI

    // 設定
    private let config: VoxConfig

    // 認識テキスト蓄積
    private var accumulatedText: String = ""
    private var currentSegmentText: String = ""

    // コンテキストキャッシュ（WhisperKit の promptTokens 構築に使用）
    private let transcriptionCache: TranscriptionCache

    public init(
        config: VoxConfig,
        audioCapture: AudioCaptureProtocol,
        speechRecognizer: SpeechRecognizerProtocol,
        rewriter: RewriterBackend,
        silenceDetector: SilenceDetector = SilenceDetector(),
        soundPlayer: SoundPlayer = SoundPlayer(),
        outputManager: OutputManager? = nil,
        terminalUI: TerminalUI = TerminalUI(),
        transcriptionCache: TranscriptionCache = TranscriptionCache()
    ) {
        self.config = config
        self.audioCapture = audioCapture
        self.speechRecognizer = speechRecognizer
        self.rewriter = rewriter
        self.silenceDetector = silenceDetector
        self.soundPlayer = soundPlayer
        self.outputManager = outputManager ?? OutputManager(config: config.output)
        self.terminalUI = terminalUI
        self.transcriptionCache = transcriptionCache
    }

    // MARK: - Public API

    public func toggle() {
        switch state {
        case .idle:
            startListening()
        case .listening:
            stopListening()
        case .processing:
            break  // processing 中は無視
        }
    }

    public func cancelListening() {
        guard state == .listening else { return }
        durationTimer?.invalidate()
        durationTimer = nil
        silenceDetector.stop()
        speechRecognizer.cancelRecognition()
        audioCapture.stop()
        accumulatedText = ""
        currentSegmentText = ""
        state = .idle
    }

    // MARK: - startListening

    public func startListening() {
        guard state == .idle else { return }

        // 音声認識エンジンの準備状態を確認
        if !speechRecognizer.isReady {
            if let message = speechRecognizer.statusMessage {
                terminalUI.showError(message)
            }
            return
        }

        state = .listening
        accumulatedText = ""
        currentSegmentText = ""

        terminalUI.showListening()

        // SE を鳴らし終えてからマイクを起動する。
        // Bluetooth 環境では、マイク起動時に A2DP → HFP に切り替わり音質が劣化するため、
        // SE は A2DP モード（マイク起動前）に再生する。
        // ビープ音は 150ms + 50ms マージン = 約 200ms で完了し、その後マイクが起動する。
        soundPlayer.playStartAndWait { [weak self] in
            guard let self = self, self.state == .listening else { return }

            // AudioCapture 開始
            do {
                try self.audioCapture.start { [weak self] buffer in
                    // オーディオスレッドから呼ばれる。append() はスレッドセーフ
                    self?.speechRecognizer.feedAudioBuffer(buffer)
                }
            } catch {
                self.terminalUI.showError(error.localizedDescription)
                self.state = .idle
                self.terminalUI.showReady()
                return
            }

            // SilenceDetector 開始（ストリーミング && timeout > 0 の場合のみ有効）
            // バッチモードでは部分結果が発生しないため、テキスト変化ベースの検出は機能しない
            if self.speechRecognizer.isStreaming && self.config.recognition.silenceTimeout > 0 {
                self.silenceDetector.start(timeout: self.config.recognition.silenceTimeout) { [weak self] in
                    guard let self = self, self.state == .listening else { return }
                    self.terminalUI.showError("No input for \(Int(self.config.recognition.silenceTimeout))s, cancelled.")
                    self.cancelListening()
                }
            }

            // 録音時間制限（ストリーミング・バッチ両対応、durationLimit > 0 の場合のみ有効）
            // 停止したつもりのユーザーが別の作業にフォーカスしている状態で
            // 録音が走り続ける事故を防止する。cancelListening で破棄し、
            // リライト→クリップボード→auto-paste の連鎖を起こさない。
            let durationLimit = self.config.recognition.durationLimit
            if durationLimit > 0 {
                self.durationTimer = Timer.scheduledTimer(
                    withTimeInterval: TimeInterval(durationLimit),
                    repeats: false
                ) { [weak self] _ in
                    guard let self = self, self.state == .listening else { return }
                    self.terminalUI.showError(
                        "Recording limit reached (\(durationLimit)s), cancelled."
                    )
                    self.cancelListening()
                    // マイク停止後、HFP → A2DP 復帰を待ってから警告音を鳴らす
                    // stopListening() の終了 SE と同じパターン
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        guard let self = self else { return }
                        self.soundPlayer.playError()
                        self.terminalUI.showReady()
                    }
                }
            }

            // SpeechRecognizer 開始
            self.beginRecognition()
        }
    }

    // MARK: - stopListening

    public func stopListening() {
        guard state == .listening else { return }

        durationTimer?.invalidate()
        durationTimer = nil
        silenceDetector.stop()

        // ストリーミング: 部分結果が蓄積済み → 即座にリライトへ
        // バッチ: テキストなし → stopRecognition() が推論を発火 → onFinalResult で受け取る
        let rawText: String?
        if speechRecognizer.isStreaming {
            accumulatedText += currentSegmentText
            currentSegmentText = ""
            rawText = accumulatedText
        } else {
            rawText = nil
        }

        // バッチモード（WhisperKit）かつコンテキスト対応モデルのみ:
        // 直近のテキストをコンテキストとしてセット
        // NOTE: large-v3_turbo 等の大型モデルは promptTokens で推論が壊れるため非対応
        if !speechRecognizer.isStreaming && speechRecognizer.supportsPromptContext {
            speechRecognizer.setPromptContext(
                transcriptionCache.recentTexts(within: 120)
            )
        }

        // マイクを先に停止する。
        // Bluetooth 環境では、マイク停止後に HFP → A2DP のプロファイル切り替えが起きる。
        // A2DP に戻ってから SE を再生することで、高音質で鳴らせる。
        speechRecognizer.stopRecognition()
        audioCapture.stop()

        state = .processing
        if !(rewriter is NoopBackend) {
            terminalUI.showRewriting()
        }

        // マイク停止後、Bluetooth の HFP → A2DP 切り替えを余裕を持って待ってから SE を再生する。
        // 切り替えに約 100-300ms かかるため、500ms 待つ。
        // 終了 SE はマイクと無関係なので、余裕を持って鳴らして問題ない。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            // 新しいセッションが listening を開始している場合はスキップ
            guard self.state != .listening else { return }
            self.soundPlayer.playStop()
            if self.state == .processing && !self.speechRecognizer.isStreaming {
                self.soundPlayer.startProcessingLoop()
            }
        }

        if let rawText = rawText {
            processRawText(rawText)
        }
        // バッチ: onFinalResult(text, isUserInitiated: true) 経由で processRawText が呼ばれる
    }

    // MARK: - processRawText

    /// リライト処理の共通メソッド（ストリーミング: stopListening から直接、バッチ: onFinalResult 経由）
    private func processRawText(_ rawText: String) {
        // シンボル辞書置換（リライト前に適用）
        let text = SymbolReplacer.apply(
            dictionary: config.vocabulary.symbolDictionary,
            to: rawText
        )

        // 空認識結果チェック
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            soundPlayer.stopProcessingLoop()
            terminalUI.showNoSpeech()
            state = .idle
            terminalUI.showReady()
            return
        }

        // リライトを非同期で発火（SE の再生とは独立して並行実行）
        rewriter.rewrite(text) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let finalText: String
                switch result {
                case .success(let rewritten):
                    finalText = rewritten
                case .failure:
                    finalText = text
                    self.terminalUI.showError("Rewrite failed, using raw text.")
                }

                self.soundPlayer.stopProcessingLoop()
                if !self.speechRecognizer.isStreaming {
                    self.soundPlayer.playCompletion()
                }

                self.terminalUI.showFinalResult(finalText)
                self.outputManager.output(finalText)
                self.transcriptionCache.add(finalText)

                if self.outputManager.clipboardEnabled && !self.outputManager.autoPasteEnabled {
                    self.terminalUI.showCopied()
                }

                self.accumulatedText = ""
                self.state = .idle
                self.terminalUI.showReady()
            }
        }
    }

    // MARK: - Private

    private func beginRecognition() {
        speechRecognizer.startRecognition(
            locale: Locale(identifier: config.language),
            onDeviceOnly: config.onDeviceOnly,
            onPartialResult: { [weak self] text in
                guard let self = self, self.state == .listening else { return }

                // 認識エンジンが内部的にセグメントをリセットした場合を検出
                if !self.currentSegmentText.isEmpty
                    && self.currentSegmentText.count >= 4
                    && text.count < self.currentSegmentText.count / 2 {
                    self.accumulatedText += self.currentSegmentText + " "
                }

                self.currentSegmentText = text
                let displayText = self.accumulatedText + text
                self.terminalUI.showPartialResult(displayText)

                // SilenceDetector にテキスト変化を通知
                self.silenceDetector.onTextChanged(displayText)
            },
            onFinalResult: { [weak self] text, isUserInitiated in
                guard let self = self else { return }

                if !isUserInitiated && self.state == .listening {
                    // エンジン自発終了 → テキストを蓄積してシームレスリスタート
                    self.accumulatedText += text
                    self.currentSegmentText = ""
                    self.beginRecognition()
                } else if isUserInitiated
                          && !self.speechRecognizer.isStreaming
                          && self.state == .processing {
                    // バッチ専用: Whisper 推論完了 → リライトへ
                    // ストリーミングでは stopListening() 内で processRawText を直接呼ぶため、
                    // !isStreaming ガードで二重呼び出しを防止する
                    self.processRawText(text)
                }
            },
            onError: { [weak self] error in
                guard let self = self else { return }
                guard self.state == .listening || self.state == .processing else { return }
                self.durationTimer?.invalidate()
                self.durationTimer = nil
                self.silenceDetector.stop()
                self.soundPlayer.stopProcessingLoop()
                let nsError = error as NSError
                self.terminalUI.showError("\(error.localizedDescription) [domain=\(nsError.domain) code=\(nsError.code)]")
                self.audioCapture.stop()
                self.accumulatedText = ""
                self.currentSegmentText = ""
                self.state = .idle
                self.terminalUI.showReady()
            }
        )
    }
}
