import Foundation

public struct OllamaBackend: RewriterBackend {
    public init() {}

    public func rewrite(_ text: String, completion: @escaping (Result<String, Error>) -> Void) {
        completion(.success(text))
    }
}
