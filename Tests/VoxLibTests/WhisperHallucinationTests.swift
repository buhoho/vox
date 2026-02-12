import XCTest
@testable import VoxLib

final class WhisperHallucinationTests: XCTestCase {

    // MARK: - isHallucinationPhrase（確定ハルシネーション）

    func testHallucinationJapanese() {
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase("ご視聴ありがとうございました"))
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase("ご視聴ありがとうございます"))
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase("見てくれてありがとう"))
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase("チャンネル登録お願いします"))
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase("チャンネル登録よろしくお願いします"))
    }

    func testHallucinationEnglish() {
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase("thank you for watching"))
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase("thanks for watching"))
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase("please subscribe"))
    }

    func testHallucinationWithPunctuation() {
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase("ご視聴ありがとうございました。"))
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase("ご視聴ありがとうございました！"))
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase("ご視聴ありがとうございました!"))
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase("thank you for watching."))
    }

    func testHallucinationCaseInsensitive() {
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase("THANK YOU FOR WATCHING"))
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase("Thank You For Watching"))
    }

    func testHallucinationWithLeadingWhitespace() {
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase(" ご視聴ありがとうございました"))
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase(" ご視聴ありがとうございました。"))
    }

    func testHallucinationWithSpecialTokens() {
        // WhisperKit が特殊トークンをテキストに含める場合でもマッチすること
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase(
            "<|startoftranscript|><|ja|><|transcribe|><|0.00|>ご視聴ありがとうございました<|3.06|><|endoftext|>"
        ))
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase(
            "<|0.00|>thank you for watching<|2.50|>"
        ))
    }

    // MARK: - stripSpecialTokens

    func testStripSpecialTokens() {
        XCTAssertEqual(
            WhisperRecognizer.stripSpecialTokens(
                "<|startoftranscript|><|ja|><|transcribe|><|0.00|>テスト<|3.06|><|endoftext|>"
            ),
            "テスト"
        )
        XCTAssertEqual(
            WhisperRecognizer.stripSpecialTokens("普通のテキスト"),
            "普通のテキスト"
        )
        XCTAssertEqual(
            WhisperRecognizer.stripSpecialTokens("<|0.00|>セグメント1<|3.00|> <|3.00|>セグメント2<|6.00|>"),
            "セグメント1 セグメント2"
        )
    }

    func testNormalTextNotHallucination() {
        XCTAssertFalse(WhisperRecognizer.isHallucinationPhrase("今日はいい天気ですね"))
        XCTAssertFalse(WhisperRecognizer.isHallucinationPhrase("明日の会議について確認します"))
        XCTAssertFalse(WhisperRecognizer.isHallucinationPhrase("Hello world"))
        XCTAssertFalse(WhisperRecognizer.isHallucinationPhrase(""))
    }

    // MARK: - isSuspiciousPhrase（疑わしいフレーズ）

    func testSuspiciousJapanese() {
        XCTAssertTrue(WhisperRecognizer.isSuspiciousPhrase("ありがとうございました"))
        XCTAssertTrue(WhisperRecognizer.isSuspiciousPhrase("ありがとうございました。"))
        XCTAssertTrue(WhisperRecognizer.isSuspiciousPhrase("お疲れ様でした"))
    }

    func testSuspiciousEnglish() {
        XCTAssertTrue(WhisperRecognizer.isSuspiciousPhrase("thank you"))
        XCTAssertTrue(WhisperRecognizer.isSuspiciousPhrase("thanks"))
        XCTAssertTrue(WhisperRecognizer.isSuspiciousPhrase("bye"))
    }

    func testNormalTextNotSuspicious() {
        XCTAssertFalse(WhisperRecognizer.isSuspiciousPhrase("今日はいい天気ですね"))
        XCTAssertFalse(WhisperRecognizer.isSuspiciousPhrase("ありがとうございました、また来ます"))
        XCTAssertFalse(WhisperRecognizer.isSuspiciousPhrase(""))
    }

    // MARK: - 確定とSuspiciousは排他

    func testHallucinationIsNotSuspicious() {
        // 「ご視聴ありがとうございました」は確定ハルシネーション、suspiciousではない
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase("ご視聴ありがとうございました"))
        XCTAssertFalse(WhisperRecognizer.isSuspiciousPhrase("ご視聴ありがとうございました"))
    }

    func testSuspiciousIsNotHallucination() {
        // 「ありがとうございました」はsuspicious、確定ハルシネーションではない
        XCTAssertFalse(WhisperRecognizer.isHallucinationPhrase("ありがとうございました"))
        XCTAssertTrue(WhisperRecognizer.isSuspiciousPhrase("ありがとうございました"))
    }
}
