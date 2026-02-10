import Foundation

public struct ClaudeBackend: RewriterBackend {
    public init() {}

    public func rewrite(_ text: String) async throws -> String {
        text
    }
}
