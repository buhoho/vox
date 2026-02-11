import Foundation

public struct GeminiBackend: RewriterBackend {
    private let apiKey: String
    private let model: String
    private let endpoint: String
    private let systemPrompt: String

    public static let defaultPrompt = """
        あなたは音声入力のテキスト修正アシスタントです。
        以下のルールに従って入力テキストを修正してください：
        1. 句読点（。、）を適切に挿入する
        2. フィラー（えーと、あのー、うーん等）を除去する
        3. 口語表現を自然な書き言葉に変換する
        4. 明らかな誤認識を文脈から推定して修正する
        5. 技術用語は正式な表記にする
        6. 原文の意味を変えない
        7. 修正後のテキストのみを出力する（説明不要）
        """

    public init(config: GeminiConfig, systemPrompt: String? = nil) throws {
        guard let key = ProcessInfo.processInfo.environment[config.apiKeyEnv], !key.isEmpty else {
            throw VoxError.apiKeyMissing(config.apiKeyEnv)
        }
        self.apiKey = key
        self.model = config.model
        self.endpoint = config.endpoint
        self.systemPrompt = systemPrompt ?? GeminiBackend.defaultPrompt
    }

    public func rewrite(_ text: String, completion: @escaping (Result<String, Error>) -> Void) {
        let urlString = "\(endpoint)/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            completion(.failure(VoxError.rewriteFailed(
                NSError(domain: "GeminiBackend", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": systemPrompt]]],
            "contents": [["parts": [["text": text]]]],
            "generationConfig": ["maxOutputTokens": 2048]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(VoxError.rewriteFailed(error)))
            return
        }

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(VoxError.rewriteFailed(error)))
                return
            }
            guard let data = data else {
                completion(.failure(VoxError.rewriteFailed(
                    NSError(domain: "GeminiBackend", code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "No data"]))))
                return
            }
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let candidates = json["candidates"] as? [[String: Any]],
                      let first = candidates.first,
                      let content = first["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]],
                      let textPart = parts.first?["text"] as? String else {
                    completion(.failure(VoxError.rewriteFailed(
                        NSError(domain: "GeminiBackend", code: -3,
                                userInfo: [NSLocalizedDescriptionKey: "Unexpected response format"]))))
                    return
                }
                completion(.success(textPart.trimmingCharacters(in: .whitespacesAndNewlines)))
            } catch {
                completion(.failure(VoxError.rewriteFailed(error)))
            }
        }.resume()
    }
}
