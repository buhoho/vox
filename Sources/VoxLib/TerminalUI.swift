import Foundation

/// ANSI エスケープコードによるターミナル表示
/// ステートレス。ターミナル幅は呼び出し時に毎回 ioctl で取得する（リサイズに即追従）
public struct TerminalUI {
    public init() {}

    // MARK: - Public API

    /// "Press Enter to start listening. Ctrl+C to quit."
    public func showReady() {
        print("\nPress Enter to start listening. Ctrl+C to quit.")
    }

    /// "🎤 Listening..."
    public func showListening() {
        print("🎤 Listening...")
    }

    /// 認識中のテキストを上書き表示（行クリア + ターミナル幅に収める）
    public func showPartialResult(_ text: String) {
        let width = terminalWidth()
        let prefix = "🎤 "
        let maxTextLen = width - prefix.count - 1
        let displayText: String
        if text.count > maxTextLen && maxTextLen > 3 {
            displayText = "…" + String(text.suffix(maxTextLen - 1))
        } else {
            displayText = text
        }
        print("\r\u{1B}[2K\(prefix)\(displayText)", terminator: "")
        fflush(stdout)
    }

    /// "⏳ Rewriting..."（showPartialResult の行をクリアして表示）
    public func showRewriting() {
        print("\r\u{1B}[2K⏳ Rewriting...")
    }

    /// "✅ {text}"
    public func showFinalResult(_ text: String) {
        print("✅ \(text)")
    }

    /// "📋 Copied to clipboard."
    public func showCopied() {
        print("📋 Copied to clipboard.")
    }

    /// "⚠️  {message}"
    public func showError(_ message: String) {
        print("⚠️  \(message)")
    }

    /// "No speech detected."（showPartialResult の行をクリアして表示）
    public func showNoSpeech() {
        print("\r\u{1B}[2KNo speech detected.")
    }

    // MARK: - Private

    /// ターミナル幅を取得（デフォルト: 80）
    private func terminalWidth() -> Int {
        var w = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &w) == 0, w.ws_col > 0 {
            return Int(w.ws_col)
        }
        return 80
    }
}
