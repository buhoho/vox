import Foundation

public struct NoopBackend: RewriterBackend {
    public init() {}

    public func rewrite(_ text: String) async throws -> String {
        text
    }
}
