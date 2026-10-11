import Foundation

// Immutable memory-mapped word graph. Shared suffixes are stored once, with no hash collisions.
public struct WordLexicon {
    private let data: Data
    private let root: Int
    public let wordCount: Int
    public var byteCount: Int { data.count }

    public static func bundled() throws -> WordLexicon {
        // SwiftPM's generated Bundle.module traps when absent; a missing dictionary must leave typing alive.
        let own = Bundle(for: LexiconBundleMarker.self)
        var locations = [Bundle.main.resourceURL, own.resourceURL, Bundle.main.bundleURL]
        // Tests load Core inside an .xctest bundle and SwiftPM's classic layout puts the resource bundle next to it.
        // Only then: the app links Core statically, so it never looks outside its own bundle.
        if own != Bundle.main { locations.append(own.bundleURL.deletingLastPathComponent()) }
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_PATH"] {
            locations.insert(URL(fileURLWithPath: path), at: 0)
        }
        #endif
        let url = locations.lazy.compactMap { $0?.appendingPathComponent("Keytide_KeytideCore.bundle") }
            .compactMap { Bundle(url: $0)?.url(forResource: "words", withExtension: "lex", subdirectory: "Resources") }.first
        guard let url else {
            throw LexiconError.invalid
        }
        return try WordLexicon(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    public init(data: Data) throws {
        guard data.count > 16, data.count <= 8_388_608,
              data.prefix(8) == Data("KTLEX001".utf8) else { throw LexiconError.invalid }
        let metadata = data.withUnsafeBytes { bytes -> (Int, Int)? in
            let root = Self.integer(bytes, 8), count = Self.integer(bytes, 12)
            guard count > 0, count <= 5_000_000 else { return nil }
            // One bit per byte validates backward edges without allocating a Set of nodes.
            var starts = [UInt8](repeating: 0, count: (bytes.count + 7) / 8)
            var offset = 16, last = offset
            while offset < bytes.count {
                last = offset
                let flags = bytes[offset], degree = Int(flags & 63), end = offset + 1 + degree * 5
                guard flags & 64 == 0, degree <= 59, end <= bytes.count,
                      degree > 0 || flags & 128 != 0 else { return nil }
                var previous = -1
                for i in 0..<degree {
                    let edge = offset + 1 + i * 5, label = Int(bytes[edge]), child = Self.integer(bytes, edge + 1)
                    guard Self.validLabel(label), label > previous, child >= 16, child < offset,
                          starts[child / 8] & (1 << (child % 8)) != 0 else { return nil }
                    previous = label
                }
                starts[offset / 8] |= 1 << (offset % 8)
                offset = end
            }
            guard offset == bytes.count, root == last, bytes[root] & 128 == 0 else { return nil }
            return (root, count)
        }
        guard let metadata else { throw LexiconError.invalid }
        self.data = data; root = metadata.0; wordCount = metadata.1
    }

    public func contains(_ word: String) -> Bool {
        guard !word.isEmpty, word.utf16.prefix(Words.maximumLength + 1).count <= Words.maximumLength else { return false }
        let word = Words.normalized(word)
        guard Words.isPlain(word) else { return false }
        return data.withUnsafeBytes { bytes in
            var node = root
            for scalar in word.unicodeScalars {
                let label = scalar.value == 0x451 ? 160 :
                    scalar.value >= 0x430 ? Int(scalar.value - 0x430) + 128 : Int(scalar.value)
                var low = 0, high = Int(bytes[node] & 63)
                while low < high {
                    let middle = (low + high) / 2, edge = node + 1 + middle * 5
                    if Int(bytes[edge]) < label { low = middle + 1 } else { high = middle }
                }
                let edge = node + 1 + low * 5
                guard low < Int(bytes[node] & 63), Int(bytes[edge]) == label else { return false }
                node = Self.integer(bytes, edge + 1)
            }
            return bytes[node] & 128 != 0
        }
    }

    private static func validLabel(_ label: Int) -> Bool { (97...122).contains(label) || (128...160).contains(label) }
    private static func integer(_ bytes: UnsafeRawBufferPointer, _ offset: Int) -> Int {
        Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
    }
}

public enum LexiconError: Error { case invalid }
private final class LexiconBundleMarker: NSObject {}
