import Foundation

public enum SymbolReplacer {
    /// 辞書のキーに一致する文字列を値で置換する。
    /// 長いキーから先にマッチさせ、短いキーによる部分一致の誤爆を防ぐ。
    public static func apply(dictionary: [String: String], to text: String) -> String {
        guard !dictionary.isEmpty else { return text }

        let sortedKeys = dictionary.keys.sorted { $0.count > $1.count }
        var result = text
        for key in sortedKeys {
            if let value = dictionary[key] {
                result = result.replacingOccurrences(of: key, with: value)
            }
        }
        return result
    }
}
