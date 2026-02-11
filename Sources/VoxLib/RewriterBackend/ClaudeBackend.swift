import Foundation

public struct ClaudeBackend: RewriterBackend {
    public init() {}

    public func rewrite(_ text: String, completion: @escaping (Result<String, Error>) -> Void) {
        completion(.success(text))
    }
}
