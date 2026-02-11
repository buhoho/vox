import XCTest
@testable import VoxLib

final class ConfigTests: XCTestCase {

    // MARK: - Default Config

    func testDefaultConfig() {
        let config = VoxConfig.default
        XCTAssertEqual(config.language, "ja-JP")
        XCTAssertTrue(config.onDeviceOnly)
        XCTAssertEqual(config.rewriter.backend, "gemini")
        XCTAssertEqual(config.output.clipboard, true)
        XCTAssertEqual(config.output.stdout, false)
        XCTAssertNil(config.output.file)
        XCTAssertEqual(config.recognition.silenceTimeout, 60)  // 60秒で自動キャンセル
        XCTAssertEqual(config.recognition.partialResults, true)
        XCTAssertEqual(config.recognition.durationLimit, 60)
        XCTAssertTrue(config.vocabulary.customTerms.isEmpty)
    }

    // MARK: - JSON Parsing

    func testLoadFromJSON() throws {
        let json = """
        {
            "language": "en-US",
            "on_device_only": false,
            "rewriter": {
                "backend": "claude",
                "gemini": null,
                "claude": {
                    "api_key_env": "CLAUDE_KEY",
                    "model": "claude-3"
                },
                "ollama": null,
                "system_prompt_path": null,
                "max_tokens": 1024
            },
            "output": {
                "clipboard": false,
                "stdout": true,
                "file": "/tmp/vox.txt"
            },
            "recognition": {
                "partial_results": true,
                "duration_limit": 30,
                "silence_timeout": 3.0
            },
            "vocabulary": {
                "custom_terms": {
                    "swift": "Swift",
                    "xcode": "Xcode"
                }
            }
        }
        """

        let tempFile = NSTemporaryDirectory() + "vox_test_config.json"
        try json.write(toFile: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let config = try VoxConfig.load(from: tempFile)
        XCTAssertEqual(config.language, "en-US")
        XCTAssertFalse(config.onDeviceOnly)
        XCTAssertEqual(config.rewriter.backend, "claude")
        XCTAssertEqual(config.rewriter.maxTokens, 1024)
        XCTAssertEqual(config.output.clipboard, false)
        XCTAssertEqual(config.output.stdout, true)
        XCTAssertEqual(config.output.file, "/tmp/vox.txt")
        XCTAssertEqual(config.recognition.silenceTimeout, 3.0)
        XCTAssertEqual(config.recognition.durationLimit, 30)
        XCTAssertEqual(config.vocabulary.customTerms["swift"], "Swift")
        XCTAssertEqual(config.vocabulary.customTerms["xcode"], "Xcode")
    }

    // MARK: - Missing File Returns Default

    func testLoadFromNilReturnsDefault() throws {
        let config = try VoxConfig.load(from: nil)
        XCTAssertEqual(config.language, "ja-JP")
    }

    func testLoadFromNonexistentFileReturnsDefault() throws {
        let config = try VoxConfig.load(from: "/tmp/nonexistent_vox_config_12345.json")
        XCTAssertEqual(config.language, "ja-JP")
    }

    // MARK: - Invalid JSON Throws

    func testLoadFromInvalidJSONThrows() throws {
        let tempFile = NSTemporaryDirectory() + "vox_test_invalid.json"
        try "{ invalid json }".write(toFile: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        XCTAssertThrowsError(try VoxConfig.load(from: tempFile)) { error in
            guard case VoxError.configLoadFailed = error else {
                XCTFail("Expected VoxError.configLoadFailed, got \(error)")
                return
            }
        }
    }

    // MARK: - Gemini Default Config

    func testGeminiDefaultConfig() {
        let gemini = GeminiConfig.default
        XCTAssertEqual(gemini.apiKeyEnv, "GEMINI_API_KEY")
        XCTAssertEqual(gemini.model, "gemini-2.5-flash-lite")
        XCTAssertTrue(gemini.endpoint.contains("googleapis.com"))
    }

    // MARK: - Config Backward Compatibility

    func testRecognitionConfigBackwardCompatibility() throws {
        // engine / whisper キーがない JSON でもデコードできること
        let json = """
        {
            "language": "ja-JP",
            "on_device_only": true,
            "rewriter": {
                "backend": "gemini",
                "gemini": { "api_key_env": "GEMINI_API_KEY", "model": "gemini-2.5-flash-lite", "endpoint": "https://generativelanguage.googleapis.com/v1beta" },
                "claude": null,
                "ollama": null,
                "system_prompt_path": null,
                "max_tokens": 2048
            },
            "output": { "clipboard": true, "stdout": false, "file": null },
            "recognition": {
                "partial_results": true,
                "duration_limit": 60,
                "silence_timeout": 60
            },
            "vocabulary": { "custom_terms": {} }
        }
        """

        let tempFile = NSTemporaryDirectory() + "vox_test_compat.json"
        try json.write(toFile: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let config = try VoxConfig.load(from: tempFile)
        XCTAssertNil(config.recognition.engine)
        XCTAssertNil(config.recognition.whisper)
    }

    func testRecognitionConfigWithWhisper() throws {
        let json = """
        {
            "language": "ja-JP",
            "on_device_only": true,
            "rewriter": {
                "backend": "gemini",
                "gemini": { "api_key_env": "GEMINI_API_KEY", "model": "gemini-2.5-flash-lite", "endpoint": "https://generativelanguage.googleapis.com/v1beta" },
                "claude": null,
                "ollama": null,
                "system_prompt_path": null,
                "max_tokens": 2048
            },
            "output": { "clipboard": true, "stdout": false, "file": null },
            "recognition": {
                "engine": "whisper",
                "partial_results": true,
                "duration_limit": 60,
                "silence_timeout": 60,
                "whisper": { "model": "small", "language": "en" }
            },
            "vocabulary": { "custom_terms": {} }
        }
        """

        let tempFile = NSTemporaryDirectory() + "vox_test_whisper.json"
        try json.write(toFile: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let config = try VoxConfig.load(from: tempFile)
        XCTAssertEqual(config.recognition.engine, "whisper")
        XCTAssertEqual(config.recognition.whisper?.model, "small")
        XCTAssertEqual(config.recognition.whisper?.language, "en")
    }

    // MARK: - OutputConfig Init

    func testOutputConfigInit() {
        let config = OutputConfig(clipboard: false, stdout: true, file: "/tmp/out.txt")
        XCTAssertFalse(config.clipboard)
        XCTAssertTrue(config.stdout)
        XCTAssertEqual(config.file, "/tmp/out.txt")
    }
}
