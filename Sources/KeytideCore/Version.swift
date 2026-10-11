import Foundation

// A release version "X.Y.Z", ordered numerically ("0.1.10" > "0.1.9"). It is parsed from external text, so strictly.
public struct Version: Comparable, CustomStringConvertible {
    private let parts: [Int]

    public init?(_ text: String) {
        guard text.utf8.count <= 32 else { return nil }
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3 else { return nil }
        var parts: [Int] = []
        for piece in pieces {
            guard (1...6).contains(piece.utf8.count), piece.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int(piece) else { return nil }
            parts.append(number)
        }
        self.parts = parts
    }

    public static func < (lhs: Version, rhs: Version) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }
    public var description: String { parts.map(String.init).joined(separator: ".") }
}
