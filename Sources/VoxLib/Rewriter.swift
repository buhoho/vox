import Foundation

public protocol RewriterBackend {
    func rewrite(_ text: String, completion: @escaping (Result<String, Error>) -> Void)
}
