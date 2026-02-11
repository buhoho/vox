import XCTest
@testable import VoxLib

final class RewriterTests: XCTestCase {

    func testNoopBackendReturnsInputUnchanged() {
        let backend = NoopBackend()
        let exp = expectation(description: "noop completion")

        backend.rewrite("テストテキスト") { result in
            switch result {
            case .success(let text):
                XCTAssertEqual(text, "テストテキスト")
            case .failure(let error):
                XCTFail("NoopBackend should not fail: \(error)")
            }
            exp.fulfill()
        }

        wait(for: [exp], timeout: 1.0)
    }

    func testGeminiBackendThrowsWithoutAPIKey() {
        // GEMINI_API_KEY が未設定なら apiKeyMissing エラー
        // テスト環境では通常設定されていないのでこれでテスト可能
        let envKey = "GEMINI_API_KEY_TEST_NONEXISTENT_12345"
        let config = GeminiConfig(
            apiKeyEnv: envKey,
            model: "gemini-2.5-flash-lite",
            endpoint: "https://example.com"
        )

        XCTAssertThrowsError(try GeminiBackend(config: config)) { error in
            guard case VoxError.apiKeyMissing(let name) = error else {
                XCTFail("Expected VoxError.apiKeyMissing, got \(error)")
                return
            }
            XCTAssertEqual(name, envKey)
        }
    }
}
