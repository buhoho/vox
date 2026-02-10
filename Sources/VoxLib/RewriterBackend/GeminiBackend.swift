import Foundation

public struct GeminiBackend: RewriterBackend {
    public init() {}

    public func rewrite(_ text: String) async throws -> String {
        text
    }
}
