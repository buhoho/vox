import Foundation
import CoreGraphics
#if canImport(AppKit)
import AppKit
#endif

public struct OutputManager {
    public let clipboardEnabled: Bool
    public let autoPasteEnabled: Bool
    public let stdoutEnabled: Bool
    public let filePath: String?

    public init(clipboardEnabled: Bool, autoPasteEnabled: Bool = true, stdoutEnabled: Bool, filePath: String?) {
        self.clipboardEnabled = clipboardEnabled
        self.autoPasteEnabled = autoPasteEnabled
        self.stdoutEnabled = stdoutEnabled
        self.filePath = filePath
    }

    public init(config: OutputConfig) {
        self.clipboardEnabled = config.clipboard
        self.autoPasteEnabled = config.autoPaste
        self.stdoutEnabled = config.stdout
        self.filePath = config.file
    }

    public func output(_ text: String) {
        #if canImport(AppKit)
        if clipboardEnabled && autoPasteEnabled {
            pasteToFocusedApp(text)
        } else if clipboardEnabled {
            copyToClipboard(text)
        }
        #endif
        if stdoutEnabled {
            print(text)
        }
        if let path = filePath {
            appendToFile(text, path: path)
        }
    }

    // MARK: - Auto-Paste

    #if canImport(AppKit)
    private func pasteToFocusedApp(_ text: String) {
        let pasteboard = NSPasteboard.general

        // 1. 元のクリップボード内容を退避
        let savedItems = Self.saveClipboard()

        // 2. テキストをクリップボードにコピー
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. Cmd+V をシミュレートしてフォーカス中のアプリに貼り付け
        Self.simulatePaste()

        // 4. 150ms 後にクリップボードを復元（貼り付け処理の完了を待つ）
        let items = savedItems
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Self.restoreClipboard(items)
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// クリップボードの全アイテム（全タイプ）を退避
    private static func saveClipboard() -> [[NSPasteboard.PasteboardType: Data]] {
        let pasteboard = NSPasteboard.general
        return pasteboard.pasteboardItems?.map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let d = item.data(forType: type) {
                    data[type] = d
                }
            }
            return data
        } ?? []
    }

    /// 退避したクリップボード内容を復元
    private static func restoreClipboard(_ items: [[NSPasteboard.PasteboardType: Data]]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        for itemData in items {
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }

    /// Cmd+V キーイベントをシミュレート（アクセシビリティ権限が必要）
    private static func simulatePaste() {
        let source = CGEventSource(stateID: CGEventSourceStateID.hidSystemState)
        // 0x09 = kVK_ANSI_V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) else {
            return
        }
        keyDown.flags = CGEventFlags.maskCommand
        keyUp.flags = CGEventFlags.maskCommand
        keyDown.post(tap: CGEventTapLocation.cghidEventTap)
        keyUp.post(tap: CGEventTapLocation.cghidEventTap)
    }
    #endif

    // MARK: - File

    private func appendToFile(_ text: String, path: String) {
        let expandedPath = NSString(string: path).expandingTildeInPath
        let line = text + "\n"
        if FileManager.default.fileExists(atPath: expandedPath) {
            if let handle = FileHandle(forWritingAtPath: expandedPath) {
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            }
        } else {
            try? line.write(toFile: expandedPath, atomically: true, encoding: .utf8)
        }
    }
}
