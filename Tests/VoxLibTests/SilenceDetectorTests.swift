import XCTest
@testable import VoxLib

final class SilenceDetectorTests: XCTestCase {

    func testSilenceTimeoutFires() {
        let detector = SilenceDetector()
        let exp = expectation(description: "silence timeout")

        detector.start(timeout: 0.3) {
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    func testTextChangeResetsTimer() {
        let detector = SilenceDetector()
        let exp = expectation(description: "silence timeout after reset")

        var fireTime: Date?
        let startTime = Date()

        detector.start(timeout: 0.3) {
            fireTime = Date()
            exp.fulfill()
        }

        // 0.2 秒後にテキスト変化を通知（タイマーリセット）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            detector.onTextChanged("新しいテキスト")
        }

        wait(for: [exp], timeout: 1.0)

        // タイマーリセット後に 0.3 秒待つので、合計 0.5 秒以上かかるはず
        if let fireTime = fireTime {
            let elapsed = fireTime.timeIntervalSince(startTime)
            XCTAssertGreaterThan(elapsed, 0.4, "タイマーリセットで発火が遅延すること")
        }
    }

    func testSameTextDoesNotResetTimer() {
        let detector = SilenceDetector()
        let exp = expectation(description: "silence timeout")

        var fireTime: Date?
        let startTime = Date()

        detector.start(timeout: 0.3) {
            fireTime = Date()
            exp.fulfill()
        }

        // 同じテキストを繰り返し通知してもタイマーはリセットされない
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            detector.onTextChanged("テキスト")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            detector.onTextChanged("テキスト")  // 同じ → リセットなし
        }

        wait(for: [exp], timeout: 1.0)

        // 最初の onTextChanged でリセットされ、0.1 + 0.3 = 0.4 秒で発火
        if let fireTime = fireTime {
            let elapsed = fireTime.timeIntervalSince(startTime)
            XCTAssertLessThan(elapsed, 0.6, "同じテキストではタイマーがリセットされないこと")
        }
    }

    func testStopPreventsCallback() {
        let detector = SilenceDetector()
        let exp = expectation(description: "should NOT fire")
        exp.isInverted = true

        detector.start(timeout: 0.2) {
            exp.fulfill()  // これが呼ばれたら失敗
        }

        // 0.1 秒後に stop
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            detector.stop()
        }

        wait(for: [exp], timeout: 0.5)
    }

    func testMultipleStarts() {
        let detector = SilenceDetector()
        let exp = expectation(description: "second timeout fires")

        var callCount = 0

        // 1 回目の start
        detector.start(timeout: 0.5) {
            callCount += 1
        }

        // 0.1 秒後に 2 回目の start（1 回目のタイマーを上書き）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            detector.start(timeout: 0.2) {
                callCount += 1
                exp.fulfill()
            }
        }

        wait(for: [exp], timeout: 1.0)

        // 2 回目の start のコールバックだけが呼ばれるべき
        XCTAssertEqual(callCount, 1, "2 回目の start のコールバックのみ呼ばれること")
    }
}
