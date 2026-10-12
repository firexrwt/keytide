import Foundation
import KeytideCore

final class ProfileStore {
    private(set) var profile = Profile()
    private(set) var immune: Set<String> = []
    private(set) var writes = 0
    var onChange: (() -> Void)?
    var onError: ((String) -> Void)?
    private let url: URL
    private var pending: DispatchWorkItem?
    private var originalDamaged: Data?
    private var saveError: Error?
    private(set) var warning: String?

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Keytide/profile.json")
        if FileManager.default.fileExists(atPath: self.url.path) {
            do {
                let data = try Self.read(self.url)
                let decoded = try Profile.decode(data)
                profile = decoded.0
                if !decoded.1.isEmpty {
                    profile.enabled = false
                    originalDamaged = data
                    warning = tr("profile.restoredFields", decoded.1.joined(separator: ", "))
                }
            } catch {
                profile.enabled = false
                originalDamaged = try? Self.read(self.url)
                warning = error.localizedDescription
            }
        }
        immune = profile.immuneWords
    }

    func update(_ change: (inout Profile) -> Void) {
        let old = profile
        change(&profile)
        guard old != profile else { return }
        immune = profile.immuneWords
        onChange?()
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    @discardableResult func flush() -> Bool {
        guard pending != nil else { return saveError == nil }
        pending?.cancel(); pending = nil
        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            if let originalDamaged {
                let backup = directory.appendingPathComponent("profile-recovered-\(UUID().uuidString).json")
                try SecureFile.write(originalDamaged, to: backup)
                self.originalDamaged = nil
            }
            try SecureFile.write(encoded(), to: url)
            writes += 1
            saveError = nil
            return true
        } catch {
            saveError = error
            onError?(tr("profile.saveFailed", error.localizedDescription))
            return false
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(profile)
    }

    func importProfile(_ source: URL) throws {
        let (candidate, warnings) = try Profile.decode(Self.read(source), complete: true)
        guard warnings.isEmpty else { throw ProfileError.unsupported }
        update { $0 = candidate }
        guard flush() else { throw saveError ?? ProfileError.unsupported }
    }

    static func read(_ url: URL) throws -> Data {
        try SecureFile.read(url)
    }
}
