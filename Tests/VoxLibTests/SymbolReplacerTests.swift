import XCTest
@testable import VoxLib

final class SymbolReplacerTests: XCTestCase {

    func testEmptyDictionaryReturnsOriginal() {
        let result = SymbolReplacer.apply(dictionary: [:], to: "テスト")
        XCTAssertEqual(result, "テスト")
    }

    func testBasicReplacement() {
        let dict = ["記号ハート": "❤️"]
        let result = SymbolReplacer.apply(dictionary: dict, to: "ありがとう記号ハート")
        XCTAssertEqual(result, "ありがとう❤️")
    }

    func testNoMatchLeavesTextUnchanged() {
        let dict = ["記号ハート": "❤️"]
        let result = SymbolReplacer.apply(dictionary: dict, to: "ハートビート")
        XCTAssertEqual(result, "ハートビート")
    }

    func testMultipleDifferentSymbols() {
        let dict = ["記号ハート": "❤️", "記号笑顔": "😊"]
        let result = SymbolReplacer.apply(dictionary: dict, to: "ありがとう記号ハートよろしく記号笑顔")
        XCTAssertEqual(result, "ありがとう❤️よろしく😊")
    }

    func testLongerKeyMatchesFirst() {
        let dict = ["記号ハート": "❤️", "記号ハートマーク": "💖"]
        let result = SymbolReplacer.apply(dictionary: dict, to: "記号ハートマーク")
        XCTAssertEqual(result, "💖")
    }

    func testNewlineReplacement() {
        let dict = ["記号改行": "\n"]
        let result = SymbolReplacer.apply(dictionary: dict, to: "テスト記号改行テスト")
        XCTAssertEqual(result, "テスト\nテスト")
    }

    func testMultipleOccurrencesOfSameKey() {
        let dict = ["記号ハート": "❤️"]
        let result = SymbolReplacer.apply(dictionary: dict, to: "記号ハート記号ハート記号ハート")
        XCTAssertEqual(result, "❤️❤️❤️")
    }

    func testFallbackVariants() {
        // Whisper が「改行」を「開業」と誤認識するケースの対応
        let dict = ["記号改行": "\n", "記号開業": "\n"]
        let result = SymbolReplacer.apply(dictionary: dict, to: "テスト記号開業テスト")
        XCTAssertEqual(result, "テスト\nテスト")
    }

    func testEmptyTextReturnsEmpty() {
        let dict = ["記号ハート": "❤️"]
        let result = SymbolReplacer.apply(dictionary: dict, to: "")
        XCTAssertEqual(result, "")
    }

    func testEntireTextIsSymbol() {
        let dict = ["記号ハート": "❤️"]
        let result = SymbolReplacer.apply(dictionary: dict, to: "記号ハート")
        XCTAssertEqual(result, "❤️")
    }
}
