import AppKit
import Security
import os
import KeytideCore

// Downloads, verifies and swaps in a release. Trust rests on the signing key: the image and the app inside it must
// satisfy the running app's designated requirement. Every failure before the swap leaves the installed app untouched.
final class UpdateInstaller: NSObject, URLSessionTaskDelegate {
    enum Failure: String, Error {
        case unsigned = "автообновление работает только у сборки, подписанной сертификатом"
        case download = "не удалось скачать обновление"
        case image = "образ обновления повреждён или в нём нет Keytide.app"
        case signature = "подпись обновления не совпадает с установленной версией"
        case copy = "не удалось скопировать обновление рядом с приложением"
        case replace = "не удалось заменить приложение (нет прав на его папку)"
    }
    static let log = Logger(subsystem: "dev.firexrwt.keytide", category: "update")
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    private let work = DispatchQueue(label: "dev.firexrwt.keytide.update", qos: .utility)

    // Completion on main: nil after a successful swap (the caller relaunches), otherwise the reason.
    func install(_ release: ReleaseInfo, completion: @escaping (Failure?) -> Void) {
        let done: (Failure?) -> Void = { failure in DispatchQueue.main.async { completion(failure) } }
        let app = Bundle.main.bundleURL
        guard let requirement = Self.ownRequirement() else { done(Self.fail(.unsigned, "ad-hoc build")); return }
        guard FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
            done(Self.fail(.replace, "app folder not writable")); return
        }
        session.downloadTask(with: release.dmg) { [work] file, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard error == nil, let file, status == 200, let folder = try? Self.privateFolder() else {
                done(Self.fail(.download, "download status \(status) \(error?.localizedDescription ?? "")")); return
            }
            // The system deletes `file` when this handler returns.
            let dmg = folder.appendingPathComponent("update.dmg")
            guard (try? FileManager.default.moveItem(at: file, to: dmg)) != nil else {
                try? FileManager.default.removeItem(at: folder); done(Self.fail(.download, "move")); return
            }
            work.async {
                let failure = Self.stage(dmg, in: folder, replacing: app, release: release, requirement: requirement)
                try? FileManager.default.removeItem(at: folder)
                done(failure)
            }
        }.resume()
    }

    // Release downloads redirect to GitHub's asset storage; nothing else is followed.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let host = request.url?.host ?? ""
        let allowed = request.url?.scheme == "https" && (host == "github.com" || host.hasSuffix(".githubusercontent.com"))
        completionHandler(allowed ? request : nil)
    }

    // ponytail: size is checked after the download (bounded by the 10 min resource timeout); abort mid-stream if a
    // release asset could ever exceed 50 MB.
    private static func stage(_ dmg: URL, in folder: URL, replacing app: URL, release: ReleaseInfo,
                              requirement: SecRequirement) -> Failure? {
        guard let size = try? dmg.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= ReleaseInfo.maximumBytes else {
            return fail(.download, "size")
        }
        // The image is signed with the release key too: nothing unsigned is even handed to the disk image driver.
        guard valid(dmg, requirement) else { return fail(.signature, "image signature") }
        let mount = folder.appendingPathComponent("mount")
        defer { _ = run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        guard run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen",
                                       "-mountpoint", mount.path, dmg.path]) != nil else { return fail(.image, "attach") }
        // A link could aim the copy at any app on disk, the installed one included.
        let source = mount.appendingPathComponent("Keytide.app")
        guard let kind = try? source.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]),
              kind.isSymbolicLink == false, kind.isDirectory == true else { return fail(.image, "no app") }
        let staged = app.deletingLastPathComponent().appendingPathComponent(".Keytide-update.app")
        try? FileManager.default.removeItem(at: staged)
        // No ACLs from the image, and nothing other users could rewrite between this check and the launch.
        guard run("/usr/bin/ditto", ["--noacl", source.path, staged.path]) != nil,
              run("/bin/chmod", ["-R", "go-w", staged.path]) != nil else {
            try? FileManager.default.removeItem(at: staged); return fail(.copy, "ditto")
        }
        guard verify(staged, requirement: requirement, version: release.version) else {
            try? FileManager.default.removeItem(at: staged); return fail(.signature, "app signature")
        }
        // One atomic swap: the installed path always holds a whole app, the old one or the new one.
        // ponytail: needs APFS (RENAME_SWAP); a two-step rename if Keytide must run from an HFS+ volume.
        guard renamex_np(staged.path, app.path, UInt32(RENAME_SWAP)) == 0 else {
            let code = errno
            try? FileManager.default.removeItem(at: staged); return fail(.replace, "swap errno \(code)")
        }
        try? FileManager.default.removeItem(at: staged)
        return nil
    }

    private static func fail(_ failure: Failure, _ step: String) -> Failure {
        log.error("update failed at \(step, privacy: .public)")
        return failure
    }

    // The running app's designated requirement. An ad-hoc build's requirement is its own hash, which nothing newer
    // can satisfy, so such a build refuses up front instead of downloading for nothing.
    static func ownRequirement() -> SecRequirement? {
        var code: SecCode?, staticCode: SecStaticCode?, requirement: SecRequirement?, text: CFString?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text,
              !(text as String).contains("cdhash") else { return nil }
        return requirement
    }

    static func valid(_ url: URL, _ requirement: SecRequirement) -> Bool {
        var code: SecStaticCode?
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess && code != nil
            && SecStaticCodeCheckValidity(code!, flags, requirement) == errSecSuccess
    }

    static func verify(_ url: URL, requirement: SecRequirement, version: Version) -> Bool {
        guard valid(url, requirement),
              let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "dev.firexrwt.keytide",
              (info["CFBundleShortVersionString"] as? String).flatMap(Version.init) == version else { return false }
        return true
    }

    // The new copy starts only after this process exits, so two event taps never run at once. Paths go as argv.
    static func relaunch(_ app: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; "
                             + "for n in 1 2 3; do /usr/bin/open \"$2\" && exit 0; /bin/sleep 1; done; exit 1",
                             "sh", String(getpid()), app.path]
        return (try? process.run()) != nil
    }

    // What an interrupted update may leave: the staged bundle next to the app and the private download folders.
    static func removeLeftovers() {
        let manager = FileManager.default
        try? manager.removeItem(at: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(".Keytide-update.app"))
        let temp = manager.temporaryDirectory
        for name in (try? manager.contentsOfDirectory(atPath: temp.path)) ?? [] where name.hasPrefix("keytide-update-") {
            try? manager.removeItem(at: temp.appendingPathComponent(name))
        }
    }

    private static func privateFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("keytide-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        return url
    }

    // argv only, never a shell. stdout on exit status 0, otherwise nil.
    private static func run(_ tool: String, _ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? data : nil
    }
}
