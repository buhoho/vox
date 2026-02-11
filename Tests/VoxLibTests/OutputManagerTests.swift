import XCTest
@testable import VoxLib

final class OutputManagerTests: XCTestCase {

    // MARK: - Init from Config

    func testInitFromConfig() {
        let config = OutputConfig(clipboard: true, stdout: false, file: "/tmp/test.txt")
        let manager = OutputManager(config: config)
        XCTAssertTrue(manager.clipboardEnabled)
        XCTAssertFalse(manager.stdoutEnabled)
        XCTAssertEqual(manager.filePath, "/tmp/test.txt")
    }

    func testInitDirect() {
        let manager = OutputManager(clipboardEnabled: false, stdoutEnabled: true, filePath: nil)
        XCTAssertFalse(manager.clipboardEnabled)
        XCTAssertTrue(manager.stdoutEnabled)
        XCTAssertNil(manager.filePath)
    }

    // MARK: - File Output

    func testFileOutput() throws {
        let tempFile = NSTemporaryDirectory() + "vox_output_test_\(UUID().uuidString).txt"
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        let manager = OutputManager(clipboardEnabled: false, stdoutEnabled: false, filePath: tempFile)

        manager.output("一行目")
        manager.output("二行目")

        let content = try String(contentsOfFile: tempFile, encoding: .utf8)
        XCTAssertEqual(content, "一行目\n二行目\n")
    }

    func testFileOutputCreatesNewFile() throws {
        let tempFile = NSTemporaryDirectory() + "vox_output_new_\(UUID().uuidString).txt"
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile))

        let manager = OutputManager(clipboardEnabled: false, stdoutEnabled: false, filePath: tempFile)
        manager.output("新規ファイル")

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile))
        let content = try String(contentsOfFile: tempFile, encoding: .utf8)
        XCTAssertEqual(content, "新規ファイル\n")
    }

    // MARK: - Clipboard Output

    #if canImport(AppKit)
    func testClipboardOutput() {
        let manager = OutputManager(clipboardEnabled: true, stdoutEnabled: false, filePath: nil)
        manager.output("クリップボードテスト")

        // NSPasteboard から読み取り
        let pasteboard = NSPasteboard.general
        let text = pasteboard.string(forType: .string)
        XCTAssertEqual(text, "クリップボードテスト")
    }
    #endif

    // MARK: - No Output

    func testNoOutputDoesNotCrash() {
        let manager = OutputManager(clipboardEnabled: false, stdoutEnabled: false, filePath: nil)
        // 全出力先が無効でもクラッシュしない
        manager.output("何も出力されない")
    }
}
