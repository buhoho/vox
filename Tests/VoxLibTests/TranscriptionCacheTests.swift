import XCTest
@testable import VoxLib

final class TranscriptionCacheTests: XCTestCase {

    func testAddAndRetrieveReturnsNewestFirst() {
        let cache = TranscriptionCache()
        cache.add("first")
        cache.add("second")
        cache.add("third")

        let texts = cache.recentTexts(within: 120)
        XCTAssertEqual(texts, ["third", "second", "first"])
    }

    func testTimeoutFilterExcludesOldEntries() {
        var currentTime = Date()
        let cache = TranscriptionCache(dateProvider: { currentTime })

        // t=0: 1件追加
        cache.add("old entry")

        // t=130秒: 2分超え
        currentTime = currentTime.addingTimeInterval(130)
        cache.add("new entry")

        let texts = cache.recentTexts(within: 120)
        // "old entry" は 130秒前なので除外、"new entry" のみ残る
        XCTAssertEqual(texts, ["new entry"])
    }

    func testClearRemovesAllEntries() {
        let cache = TranscriptionCache()
        cache.add("one")
        cache.add("two")

        cache.clear()

        let texts = cache.recentTexts(within: 120)
        XCTAssertTrue(texts.isEmpty)
    }

    func testLazyCleanupOnRecentTexts() {
        var currentTime = Date()
        let cache = TranscriptionCache(dateProvider: { currentTime })

        cache.add("will expire")

        // 3分経過
        currentTime = currentTime.addingTimeInterval(180)

        // recentTexts 呼び出しで古いエントリが除去される
        let texts = cache.recentTexts(within: 120)
        XCTAssertTrue(texts.isEmpty)

        // 新しいエントリを追加しても、古いものは戻ってこない
        cache.add("fresh")
        let texts2 = cache.recentTexts(within: 120)
        XCTAssertEqual(texts2, ["fresh"])
    }

    func testEntriesWithinTimeoutArePreserved() {
        var currentTime = Date()
        let cache = TranscriptionCache(dateProvider: { currentTime })

        cache.add("entry1")

        // 60秒経過（まだ2分以内）
        currentTime = currentTime.addingTimeInterval(60)
        cache.add("entry2")

        let texts = cache.recentTexts(within: 120)
        XCTAssertEqual(texts, ["entry2", "entry1"])
    }
}
