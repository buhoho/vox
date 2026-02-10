import Foundation

public protocol RewriterBackend {
    func rewrite(_ text: String) async throws -> String
}
