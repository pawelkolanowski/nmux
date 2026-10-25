import CryptoKit
import Foundation

struct LockError: Error, CustomStringConvertible {
    let description: String
}

struct Lock {
    static let keys = ["commit", "date", "url", "sha256", "size", "signature", "minisign-key"]

    let values: [String: String]
    var sha256: String { values["sha256"]! } // init refuses a lock without it

    /// Blank lines and `#` comments are skipped; a value may hold `=`.
    init(_ text: String) throws {
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let equals = line.firstIndex(of: "=") else {
                throw LockError(description: "not `key = value`: \(line)")
            }
            values[line[..<equals].trimmingCharacters(in: .whitespaces)] =
                line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        }
        if let missing = Self.keys.first(where: { values[$0] == nil }) {
            throw LockError(description: "no \(missing) in the lock")
        }
        self.values = values
    }

    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Nil when the zip is the one the lock names; otherwise why not, with both sums.
    func mismatch(zip: Data) -> String? {
        let sum = Self.sha256(of: zip)
        return sum == sha256
            ? nil
            : "libghostty-vt zip differs from its lock\n  lock sha256 \(sha256)\n  zip  sha256 \(sum)"
    }
}
