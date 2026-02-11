import Foundation

// MARK: - VoxConfig

public struct VoxConfig: Codable {
    public let language: String
    public let onDeviceOnly: Bool
    public let rewriter: RewriterConfig
    public let output: OutputConfig
    public let recognition: RecognitionConfig
    public let vocabulary: VocabularyConfig

    public init(
        language: String,
        onDeviceOnly: Bool,
        rewriter: RewriterConfig,
        output: OutputConfig,
        recognition: RecognitionConfig,
        vocabulary: VocabularyConfig
    ) {
        self.language = language
        self.onDeviceOnly = onDeviceOnly
        self.rewriter = rewriter
        self.output = output
        self.recognition = recognition
        self.vocabulary = vocabulary
    }

    public static func load(from path: String?) throws -> VoxConfig {
        guard let path = path else {
            return VoxConfig.default
        }

        let expandedPath = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)

        guard FileManager.default.fileExists(atPath: expandedPath) else {
            return VoxConfig.default
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(VoxConfig.self, from: data)
        } catch {
            throw VoxError.configLoadFailed(error)
        }
    }

    public static let `default` = VoxConfig(
        language: "ja-JP",
        onDeviceOnly: true,
        rewriter: .default,
        output: .default,
        recognition: .default,
        vocabulary: .default
    )
}

// MARK: - RewriterConfig

public struct RewriterConfig: Codable {
    public let backend: String
    public let gemini: GeminiConfig?
    public let claude: ClaudeConfig?
    public let ollama: OllamaConfig?
    public let systemPromptPath: String?
    public let maxTokens: Int

    public static let `default` = RewriterConfig(
        backend: "gemini",
        gemini: .default,
        claude: nil,
        ollama: nil,
        systemPromptPath: nil,
        maxTokens: 2048
    )
}

public struct GeminiConfig: Codable {
    public let apiKeyEnv: String
    public let model: String
    public let endpoint: String

    public static let `default` = GeminiConfig(
        apiKeyEnv: "GEMINI_API_KEY",
        model: "gemini-2.5-flash-lite",
        endpoint: "https://generativelanguage.googleapis.com/v1beta"
    )
}

public struct ClaudeConfig: Codable {
    public let apiKeyEnv: String
    public let model: String
}

public struct OllamaConfig: Codable {
    public let endpoint: String
    public let model: String
}

// MARK: - OutputConfig

public struct OutputConfig: Codable {
    public let clipboard: Bool
    public let autoPaste: Bool
    public let stdout: Bool
    public let file: String?

    public init(clipboard: Bool, autoPaste: Bool = true, stdout: Bool, file: String?) {
        self.clipboard = clipboard
        self.autoPaste = autoPaste
        self.stdout = stdout
        self.file = file
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clipboard = try container.decode(Bool.self, forKey: .clipboard)
        autoPaste = try container.decodeIfPresent(Bool.self, forKey: .autoPaste) ?? true
        stdout = try container.decode(Bool.self, forKey: .stdout)
        file = try container.decodeIfPresent(String.self, forKey: .file)
    }

    public static let `default` = OutputConfig(
        clipboard: true,
        autoPaste: true,
        stdout: false,
        file: nil
    )
}

// MARK: - RecognitionConfig

public struct RecognitionConfig: Codable {
    public let engine: String?          // "system" or "whisper"（nil = "system"）
    public let partialResults: Bool
    public let durationLimit: Int
    public let silenceTimeout: Double
    public let whisper: WhisperConfig?

    public static let `default` = RecognitionConfig(
        engine: nil,
        partialResults: true,
        durationLimit: 60,
        silenceTimeout: 60,  // 60秒間無音で自動キャンセル（破棄）
        whisper: nil
    )
}

public struct WhisperConfig: Codable {
    public let model: String       // "tiny", "base", "small", "medium", "large-v3"
    public let language: String?   // Whisper 言語コード: "ja", "en" 等（nil = 自動検出）

    public static let `default` = WhisperConfig(
        model: "base",
        language: "ja"
    )
}

// MARK: - VocabularyConfig

public struct VocabularyConfig: Codable {
    public let customTerms: [String: String]

    public static let `default` = VocabularyConfig(
        customTerms: [:]
    )
}
