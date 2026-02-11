import ArgumentParser
import Foundation
import VoxLib

// MARK: - Terminal Restoration

/// atexit に渡す関数はキャプチャコンテキストを持てないため、グローバル変数を使用
private var savedTermios = termios()

/// ターミナルを元の状態に復元する
private func restoreTerminal() {
    tcsetattr(STDIN_FILENO, TCSANOW, &savedTermios)
}

// MARK: - PID File

/// デーモンモード用 PID ファイルのパス
private var pidFilePath: String?

/// PID ファイルを削除する（atexit 用）
private func cleanupPIDFile() {
    if let path = pidFilePath {
        try? FileManager.default.removeItem(atPath: path)
    }
}

// MARK: - CLI

@main
struct VoxCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vox",
        abstract: "macOS ローカル音声入力ツール",
        version: "0.1.0"
    )

    @Flag(name: .long, help: "リライトなし（生テキスト出力）")
    var noRewrite = false

    @Option(name: .long, help: "言語指定（デフォルト: ja-JP）")
    var lang: String?

    @Option(name: .long, help: "設定ファイルパス")
    var config: String?

    @Flag(name: .long, help: "標準出力に出力（クリップボードにコピーしない）")
    var stdout = false

    @Flag(name: .long, help: "デーモンモード（SIGUSR1 でトグル）")
    var daemon = false

    @Option(name: .long, help: "音声認識エンジン（system/whisper）")
    var engine: String?

    func run() throws {
        // 0. 権限要求（マイク + 音声認識）
        PermissionChecker.requestAll()

        // 1. Config ロード
        var voxConfig = try VoxConfig.load(from: config)
        if let langOverride = lang {
            voxConfig = VoxConfig(
                language: langOverride,
                onDeviceOnly: voxConfig.onDeviceOnly,
                rewriter: voxConfig.rewriter,
                output: voxConfig.output,
                recognition: voxConfig.recognition,
                vocabulary: voxConfig.vocabulary
            )
        }

        // 2. RewriterBackend 選択
        let rewriter: RewriterBackend
        if noRewrite {
            rewriter = NoopBackend()
        } else {
            do {
                rewriter = try GeminiBackend(config: voxConfig.rewriter.gemini ?? .default)
            } catch {
                print("⚠️  Rewriter unavailable (\(error.localizedDescription)), using raw text mode.")
                rewriter = NoopBackend()
            }
        }

        // 3. OutputManager（--stdout フラグで上書き）
        let outputManager: OutputManager
        if self.stdout {
            outputManager = OutputManager(config: OutputConfig(clipboard: false, autoPaste: false, stdout: true, file: nil))
        } else {
            outputManager = OutputManager(config: voxConfig.output)
        }

        // 4. 自動ペーストが有効ならアクセシビリティ権限を確認
        if outputManager.autoPasteEnabled && outputManager.clipboardEnabled {
            if !PermissionChecker.checkAccessibility(prompt: true) {
                print("⚠️  Accessibility permission not granted. Auto-paste disabled, using clipboard-only mode.")
                print("   Grant permission in System Settings > Privacy & Security > Accessibility.")
            }
        }

        // 5. 音声認識エンジン選択
        let engineName = engine ?? voxConfig.recognition.engine ?? "system"
        let speechRecognizer: SpeechRecognizerProtocol

        switch engineName {
        case "whisper":
            let whisperConfig = voxConfig.recognition.whisper ?? .default
            speechRecognizer = WhisperRecognizer(model: whisperConfig.model, language: whisperConfig.language)
        default:
            speechRecognizer = SpeechRecognizer()
        }

        // 6. VoxSession 生成
        let session = VoxSession(
            config: voxConfig,
            audioCapture: AudioCapture(),
            speechRecognizer: speechRecognizer,
            rewriter: rewriter,
            outputManager: outputManager
        )

        // 7. Whisper モデルの非同期ロード
        if let whisperRecognizer = speechRecognizer as? WhisperRecognizer {
            let modelName = voxConfig.recognition.whisper?.model ?? "base"
            print("Loading Whisper model (\(modelName))...")
            whisperRecognizer.prepare { error in
                if let error = error {
                    print("⚠️  Whisper model load failed: \(error.localizedDescription)")
                    print("   Please check your network connection and try again.")
                } else {
                    print("Whisper model loaded. Ready.")
                }
            }
        }

        // 8. SIGINT ハンドラ（Ctrl+C → graceful shutdown）
        signal(SIGINT, SIG_IGN)
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource.setEventHandler {
            switch session.state {
            case .idle:
                break
            case .listening:
                session.cancelListening()
            case .processing:
                break
            }
            if !self.daemon {
                restoreTerminal()
            }
            cleanupPIDFile()
            print("")
            Darwin.exit(0)
        }
        sigintSource.resume()

        // 9. SIGTERM ハンドラ
        signal(SIGTERM, SIG_IGN)
        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigtermSource.setEventHandler {
            if !self.daemon {
                restoreTerminal()
            }
            cleanupPIDFile()
            Darwin.exit(0)
        }
        sigtermSource.resume()

        // 10. モード別セットアップ
        // DispatchSource はローカル変数のスコープを抜けると解放されるため、
        // run() のスコープで保持し、RunLoop.main.run() が終了しない限り生き続けるようにする
        var stdinSource: DispatchSourceRead?
        var sigusr1Source: DispatchSourceSignal?

        if daemon {
            // PID ファイルを書き出し
            let pidDir = NSString(string: "~/.config/vox").expandingTildeInPath
            try? FileManager.default.createDirectory(atPath: pidDir, withIntermediateDirectories: true)
            let path = pidDir + "/vox.pid"
            pidFilePath = path
            try? "\(ProcessInfo.processInfo.processIdentifier)".write(
                toFile: path, atomically: true, encoding: .utf8)
            atexit(cleanupPIDFile)

            // SIGUSR1 ハンドラ（トグル）
            signal(SIGUSR1, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
            source.setEventHandler {
                session.toggle()
            }
            source.resume()
            sigusr1Source = source

            print("Vox daemon started (PID: \(ProcessInfo.processInfo.processIdentifier))")
            print("Send SIGUSR1 to toggle: kill -USR1 \(ProcessInfo.processInfo.processIdentifier)")
            print("PID file: \(path)")
        } else {
            // ターミナル raw モード設定
            tcgetattr(STDIN_FILENO, &savedTermios)
            atexit(restoreTerminal)

            var raw = savedTermios
            raw.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN)
            raw.c_cc.16 = 1  // VMIN
            raw.c_cc.17 = 0  // VTIME
            tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)

            // stdin 監視（Enter / Escape キー検出）
            let source = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
            source.setEventHandler {
                var buf = [UInt8](repeating: 0, count: 1)
                let n = read(STDIN_FILENO, &buf, 1)
                if n <= 0 {
                    restoreTerminal()
                    Darwin.exit(0)
                }
                if buf[0] == 0x0A {  // Enter (LF)
                    session.toggle()
                } else if buf[0] == 0x1B {  // Escape
                    session.cancelListening()
                }
            }
            source.resume()
            stdinSource = source

            print("Vox v0.1.0 — Press Enter to start/stop. Escape to cancel. Ctrl+C to quit.")
        }

        // 11. RunLoop 開始（無限ループ。DispatchSource の参照はこのスコープで保持される）
        withExtendedLifetime((sigintSource, sigtermSource, stdinSource, sigusr1Source)) {
            RunLoop.main.run()
        }
    }
}
