import XCTest
@testable import VoxLib

final class WhisperHallucinationTests: XCTestCase {

    // MARK: - 完全一致（テキスト全体がハルシネーション）

    func testFullMatchJapanese() {
        XCTAssertEqual(WhisperRecognizer.filterHallucinations("ご視聴ありがとうございました"), "")
        XCTAssertEqual(WhisperRecognizer.filterHallucinations("ご視聴ありがとうございます"), "")
        XCTAssertEqual(WhisperRecognizer.filterHallucinations("見てくれてありがとう"), "")
        XCTAssertEqual(WhisperRecognizer.filterHallucinations("チャンネル登録お願いします"), "")
        XCTAssertEqual(WhisperRecognizer.filterHallucinations("チャンネル登録よろしくお願いします"), "")
    }

    func testFullMatchEnglish() {
        XCTAssertEqual(WhisperRecognizer.filterHallucinations("Thank you for watching"), "")
        XCTAssertEqual(WhisperRecognizer.filterHallucinations("Thanks for watching"), "")
        XCTAssertEqual(WhisperRecognizer.filterHallucinations("Please subscribe"), "")
    }

    // MARK: - 句読点バリエーション

    func testFullMatchWithPunctuation() {
        XCTAssertEqual(WhisperRecognizer.filterHallucinations("ご視聴ありがとうございました。"), "")
        XCTAssertEqual(WhisperRecognizer.filterHallucinations("ご視聴ありがとうございました！"), "")
        XCTAssertEqual(WhisperRecognizer.filterHallucinations("ご視聴ありがとうございました!"), "")
        XCTAssertEqual(WhisperRecognizer.filterHallucinations("Thank you for watching."), "")
        XCTAssertEqual(WhisperRecognizer.filterHallucinations("Thank you for watching!"), "")
    }

    // MARK: - 大文字小文字の正規化

    func testCaseInsensitive() {
        XCTAssertEqual(WhisperRecognizer.filterHallucinations("THANK YOU FOR WATCHING"), "")
        XCTAssertEqual(WhisperRecognizer.filterHallucinations("Thank You For Watching"), "")
    }

    // MARK: - 正常テキストは変更しない

    func testNormalTextUnchanged() {
        XCTAssertEqual(WhisperRecognizer.filterHallucinations("今日はいい天気ですね"), "今日はいい天気ですね")
        XCTAssertEqual(WhisperRecognizer.filterHallucinations("明日の会議について確認します"), "明日の会議について確認します")
        XCTAssertEqual(WhisperRecognizer.filterHallucinations("Hello world"), "Hello world")
    }

    // MARK: - 空文字・ホワイトスペース

    func testEmptyAndWhitespace() {
        XCTAssertEqual(WhisperRecognizer.filterHallucinations(""), "")
        XCTAssertEqual(WhisperRecognizer.filterHallucinations("   "), "")
        XCTAssertEqual(WhisperRecognizer.filterHallucinations("\n"), "")
    }

    // MARK: - 末尾にハルシネーションが付加されているケース

    func testSuffixRemoval() {
        let result = WhisperRecognizer.filterHallucinations("今日の天気は晴れですご視聴ありがとうございました")
        XCTAssertEqual(result, "今日の天気は晴れです")
    }

    func testSuffixRemovalWithPunctuation() {
        let result = WhisperRecognizer.filterHallucinations("今日の天気は晴れです。ご視聴ありがとうございました。")
        // 元テキストの句読点「。」は正当なものなので残る
        XCTAssertEqual(result, "今日の天気は晴れです。")
    }

    // MARK: - Whisper 実出力パターン（セグメント結合後のテキスト）

    func testSuffixRemovalWithSpace() {
        // セグメント結合時にスペース区切りで結合されるケース
        let result = WhisperRecognizer.filterHallucinations("今日の天気は晴れです ご視聴ありがとうございました")
        XCTAssertEqual(result, "今日の天気は晴れです")
    }

    func testSuffixRemovalWithSpaceAndPunctuation() {
        let result = WhisperRecognizer.filterHallucinations("明日の会議について確認します。 ご視聴ありがとうございました。")
        XCTAssertEqual(result, "明日の会議について確認します。")
    }

    // MARK: - isHallucinationPhrase（セグメント単位）

    func testIsHallucinationPhrase() {
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase("ご視聴ありがとうございました"))
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase("ご視聴ありがとうございました。"))
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase(" ご視聴ありがとうございました"))
        XCTAssertTrue(WhisperRecognizer.isHallucinationPhrase(" ご視聴ありがとうございました。"))
        XCTAssertFalse(WhisperRecognizer.isHallucinationPhrase("今日はいい天気ですね"))
        XCTAssertFalse(WhisperRecognizer.isHallucinationPhrase(""))
    }
}
