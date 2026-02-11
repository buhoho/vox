import XCTest
@testable import VoxLib

final class VoxSessionTests: XCTestCase {

    private var session: VoxSession!
    private var mockAudio: MockAudioCapture!
    private var mockSpeech: MockSpeechRecognizer!
    private var mockRewriter: MockRewriterBackend!

    override func setUp() {
        super.setUp()
        mockAudio = MockAudioCapture()
        mockSpeech = MockSpeechRecognizer()
        mockRewriter = MockRewriterBackend()

        session = VoxSession(
            config: .default,
            audioCapture: mockAudio,
            speechRecognizer: mockSpeech,
            rewriter: mockRewriter,
            soundPlayer: MockSoundPlayer()
        )
    }

    override func tearDown() {
        session = nil
        mockAudio = nil
        mockSpeech = nil
        mockRewriter = nil
        super.tearDown()
    }

    // MARK: - State Transition Tests

    func testInitialStateIsIdle() {
        XCTAssertEqual(session.state, .idle)
    }

    func testToggleFromIdleStartsListening() {
        session.toggle()
        XCTAssertEqual(session.state, .listening)
        XCTAssertEqual(mockAudio.startCallCount, 1)
        XCTAssertEqual(mockSpeech.startCallCount, 1)
    }

    func testToggleFromListeningStopsAndProcesses() {
        session.toggle()  // idle -> listening
        XCTAssertEqual(session.state, .listening)

        // 部分結果を入れてからstop
        mockSpeech.simulatePartialResult("テスト")
        mockRewriter.result = .success("テスト修正版")
        session.toggle()  // listening -> processing

        XCTAssertEqual(session.state, .processing)
        XCTAssertEqual(mockSpeech.stopCallCount, 1)
        XCTAssertEqual(mockAudio.stopCallCount, 1)
        XCTAssertEqual(mockRewriter.rewriteCallCount, 1)

        // リライト完了を待つ（DispatchQueue.main.async）
        let exp = expectation(description: "rewrite completion")
        DispatchQueue.main.async {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(session.state, .idle)
    }

    func testToggleDuringProcessingIsIgnored() {
        session.toggle()  // idle -> listening
        mockSpeech.simulatePartialResult("テスト")
        mockRewriter.result = .success("テスト")
        session.toggle()  // listening -> processing

        XCTAssertEqual(session.state, .processing)

        session.toggle()  // processing 中は無視
        XCTAssertEqual(session.state, .processing)
        // startCallCount は最初の1回のみ
        XCTAssertEqual(mockAudio.startCallCount, 1)
    }

    // MARK: - Empty Recognition

    func testEmptyRecognitionSkipsRewrite() {
        session.toggle()  // idle -> listening
        // 部分結果なしで停止
        session.toggle()  // listening -> idle (空テキスト)

        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(mockRewriter.rewriteCallCount, 0)  // リライト不要
    }

    // MARK: - Rewrite Failure Fallback

    func testRewriteFailureFallsBackToRawText() {
        session.toggle()  // idle -> listening
        mockSpeech.simulatePartialResult("生テキスト")

        mockRewriter.result = .failure(VoxError.rewriteFailed(
            NSError(domain: "test", code: -1, userInfo: nil)))
        session.toggle()  // listening -> processing

        XCTAssertEqual(mockRewriter.lastInput, "生テキスト")

        // リライト失敗後も idle に戻る
        let exp = expectation(description: "rewrite failure")
        DispatchQueue.main.async {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(session.state, .idle)
    }

    // MARK: - Cancel

    func testCancelListening() {
        session.toggle()  // idle -> listening
        mockSpeech.simulatePartialResult("途中テキスト")
        session.cancelListening()

        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(mockSpeech.cancelCallCount, 1)  // cancelRecognition が呼ばれる
        XCTAssertEqual(mockAudio.stopCallCount, 1)
        XCTAssertEqual(mockRewriter.rewriteCallCount, 0)  // リライトはスキップ
    }

    func testCancelFromIdleIsNoop() {
        session.cancelListening()
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(mockSpeech.stopCallCount, 0)
    }

    // MARK: - Engine Auto-Stop (Seamless Restart)

    func testEngineAutoStopTriggersRestart() {
        session.toggle()  // idle -> listening
        mockSpeech.simulatePartialResult("最初のセグメント")

        // エンジン自発終了: isUserInitiated = false
        mockSpeech.simulateFinalResult("最初のセグメント", isUserInitiated: false)

        // listening のまま、SpeechRecognizer が再開される
        XCTAssertEqual(session.state, .listening)
        XCTAssertEqual(mockSpeech.startCallCount, 2)  // 初回 + リスタート
    }

    // MARK: - Segment Accumulation

    func testSegmentAccumulationOnRestart() {
        session.toggle()  // idle -> listening

        // 第1セグメント
        mockSpeech.simulatePartialResult("最初のセグメント")
        mockSpeech.simulateFinalResult("最初のセグメント", isUserInitiated: false)

        // 第2セグメント
        mockSpeech.simulatePartialResult("二番目のセグメント")

        // ユーザー停止
        mockRewriter.result = .success("修正テキスト")
        session.toggle()  // listening -> processing

        // リライトに渡されるテキストに両セグメントが含まれる
        XCTAssertTrue(mockRewriter.lastInput?.contains("最初のセグメント") ?? false,
                      "第1セグメントが蓄積されていること")
        XCTAssertTrue(mockRewriter.lastInput?.contains("二番目のセグメント") ?? false,
                      "第2セグメントが蓄積されていること")
    }

    // MARK: - Audio Capture Error

    func testAudioCaptureErrorReturnsToIdle() {
        mockAudio.shouldThrow = VoxError.audioEngineStartFailed(
            NSError(domain: "test", code: -1, userInfo: nil))

        session.toggle()  // idle -> should fail and return to idle

        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(mockSpeech.startCallCount, 0)
    }

    // MARK: - Batch Mode (isStreaming = false)

    func testBatchModeBasicFlow() {
        // バッチモードの Mock 設定
        mockSpeech.isStreaming = false
        session.toggle()  // idle -> listening
        XCTAssertEqual(session.state, .listening)

        session.toggle()  // listening -> processing（バッチモードは推論発火を待つ）
        XCTAssertEqual(session.state, .processing)

        // Whisper 推論完了シミュレーション
        mockRewriter.result = .success("修正テキスト")
        mockSpeech.simulateFinalResult("バッチ認識結果", isUserInitiated: true)

        XCTAssertEqual(mockRewriter.lastInput, "バッチ認識結果")

        // リライト完了を待つ
        let exp = expectation(description: "batch rewrite")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(session.state, .idle)
    }

    func testBatchModeEmptyResult() {
        mockSpeech.isStreaming = false
        session.toggle()  // idle -> listening
        session.toggle()  // listening -> processing

        // 空結果
        mockSpeech.simulateFinalResult("", isUserInitiated: true)

        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(mockRewriter.rewriteCallCount, 0)
    }

    func testBatchModeCancelListening() {
        mockSpeech.isStreaming = false
        session.toggle()  // idle -> listening
        session.cancelListening()

        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(mockSpeech.cancelCallCount, 1)
        XCTAssertEqual(mockSpeech.stopCallCount, 0)  // stopRecognition は呼ばれない
    }

    func testBatchModeErrorDuringStartRecognitionReturnsToIdle() {
        // モデル未ロード時: startRecognition で即エラー → idle に戻る
        mockSpeech.isStreaming = false
        session.toggle()  // idle -> listening

        // startRecognition のエラーを DispatchQueue.main.async で遅延発火
        mockSpeech.simulateError(VoxError.speechRecognizerUnavailable)

        let exp = expectation(description: "error handling")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(mockRewriter.rewriteCallCount, 0)
    }

    func testBatchModeErrorDuringProcessingReturnsToIdle() {
        // processing 中にエラーが来ても idle に復帰すること
        mockSpeech.isStreaming = false
        session.toggle()  // idle -> listening
        session.toggle()  // listening -> processing

        XCTAssertEqual(session.state, .processing)

        // stopRecognition 内で whisperKit == nil → onError 発火
        mockSpeech.simulateError(VoxError.speechRecognizerUnavailable)

        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(mockRewriter.rewriteCallCount, 0)
    }

    func testStreamingModeDoesNotDoubleProcessRawText() {
        // ストリーミングモードで stopListening 後に isUserInitiated=true の
        // onFinalResult が来ても processRawText が二重に走らないこと
        mockSpeech.isStreaming = true
        session.toggle()  // idle -> listening
        mockSpeech.simulatePartialResult("テスト")
        mockRewriter.result = .success("修正版")
        session.toggle()  // listening -> processing

        XCTAssertEqual(mockRewriter.rewriteCallCount, 1)

        // SFSpeechRecognizer の finish() による遅延 onFinalResult
        mockSpeech.simulateFinalResult("テスト", isUserInitiated: true)

        // rewrite は最初の1回のみ（二重呼び出し防止）
        XCTAssertEqual(mockRewriter.rewriteCallCount, 1)
    }

    // MARK: - Segment Reset Detection

    // MARK: - Context Cache (Batch Mode)

    func testBatchModePromptContextSetOnSecondInput() {
        mockSpeech.isStreaming = false

        // 1回目の入力
        session.toggle()  // idle -> listening
        session.toggle()  // listening -> processing
        mockRewriter.result = .success("リライト済みテキスト")
        mockSpeech.simulateFinalResult("認識結果", isUserInitiated: true)

        // リライト完了を待つ
        let exp1 = expectation(description: "first rewrite")
        DispatchQueue.main.async { exp1.fulfill() }
        wait(for: [exp1], timeout: 1.0)

        XCTAssertEqual(session.state, .idle)

        // 2回目の入力
        session.toggle()  // idle -> listening
        session.toggle()  // listening -> processing

        // setPromptContext が呼ばれ、1回目のリライト結果が含まれている
        XCTAssertTrue(mockSpeech.lastPromptContext.contains("リライト済みテキスト"),
                      "2回目の入力で1回目のテキストが promptContext に含まれること: \(mockSpeech.lastPromptContext)")
    }

    func testBatchModePromptContextAccumulatesAcrossInputs() {
        mockSpeech.isStreaming = false

        // 1回目
        session.toggle()
        session.toggle()
        mockRewriter.result = .success("テキスト1")
        mockSpeech.simulateFinalResult("raw1", isUserInitiated: true)
        let exp1 = expectation(description: "rewrite1")
        DispatchQueue.main.async { exp1.fulfill() }
        wait(for: [exp1], timeout: 1.0)

        // 2回目
        session.toggle()
        session.toggle()
        mockRewriter.result = .success("テキスト2")
        mockSpeech.simulateFinalResult("raw2", isUserInitiated: true)
        let exp2 = expectation(description: "rewrite2")
        DispatchQueue.main.async { exp2.fulfill() }
        wait(for: [exp2], timeout: 1.0)

        // 3回目
        session.toggle()
        session.toggle()

        // 1回目と2回目のテキストが両方 promptContext に含まれる
        XCTAssertTrue(mockSpeech.lastPromptContext.contains("テキスト1"),
                      "3回目で1回目のテキストが含まれること")
        XCTAssertTrue(mockSpeech.lastPromptContext.contains("テキスト2"),
                      "3回目で2回目のテキストが含まれること")
    }

    func testStreamingModePromptContextNotSet() {
        mockSpeech.isStreaming = true  // ストリーミングモード

        // 1回目の入力
        session.toggle()  // idle -> listening
        mockSpeech.simulatePartialResult("テスト")
        mockRewriter.result = .success("リライト済み")
        session.toggle()  // listening -> processing

        let exp = expectation(description: "rewrite")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        // 2回目の入力
        session.toggle()  // idle -> listening
        mockSpeech.simulatePartialResult("テスト2")
        session.toggle()  // listening -> processing

        // ストリーミングモードでは setPromptContext が呼ばれない
        XCTAssertTrue(mockSpeech.lastPromptContext.isEmpty,
                      "ストリーミングモードでは promptContext が空のまま")
    }

    func testRewriteFailureFallbackTextIsCached() {
        mockSpeech.isStreaming = false

        // 1回目: リライト失敗
        session.toggle()
        session.toggle()
        mockRewriter.result = .failure(VoxError.rewriteFailed(
            NSError(domain: "test", code: -1, userInfo: nil)))
        mockSpeech.simulateFinalResult("生テキスト", isUserInitiated: true)

        let exp = expectation(description: "rewrite failure")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        // 2回目
        session.toggle()
        session.toggle()

        // リライト失敗時も生テキストが promptContext に入っている
        XCTAssertTrue(mockSpeech.lastPromptContext.contains("生テキスト"),
                      "リライト失敗時も生テキストがキャッシュされること: \(mockSpeech.lastPromptContext)")
    }

    func testCancelListeningPreservesCache() {
        mockSpeech.isStreaming = false

        // 1回目: 正常完了
        session.toggle()
        session.toggle()
        mockRewriter.result = .success("キャッシュされるテキスト")
        mockSpeech.simulateFinalResult("raw", isUserInitiated: true)

        let exp = expectation(description: "rewrite")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        // 2回目: キャンセル
        session.toggle()  // idle -> listening
        session.cancelListening()

        // 3回目: 正常に停止
        session.toggle()  // idle -> listening
        session.toggle()  // listening -> processing

        // キャンセル後も以前のキャッシュが保持されている
        XCTAssertTrue(mockSpeech.lastPromptContext.contains("キャッシュされるテキスト"),
                      "キャンセル後も以前のキャッシュが保持されること")
    }

    // MARK: - Segment Reset Detection

    func testSegmentResetDetectsTextDrop() {
        session.toggle()  // idle -> listening

        // テキストが徐々に増えていく
        mockSpeech.simulatePartialResult("あいう")
        mockSpeech.simulatePartialResult("あいうえお")  // 5文字
        // 急にテキストが短くなる（認識エンジンの内部リセット）
        mockSpeech.simulatePartialResult("か")  // 1文字 < 5/2 → セグメントリセット検出

        // ここで停止して最終テキストを確認
        mockRewriter.result = .success("dummy")
        session.toggle()

        // accumulatedText に "あいうえお" が蓄積されているはず
        let input = mockRewriter.lastInput ?? ""
        XCTAssertTrue(input.contains("あいうえお"), "リセット前のテキストが蓄積されること: \(input)")
        XCTAssertTrue(input.contains("か"), "リセット後のテキストも含まれること: \(input)")
    }
}
