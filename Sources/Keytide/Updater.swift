import AppKit
import KeytideCore

// Finds a newer GitHub release: once a day through the system scheduler, or on demand. Nothing is installed without
// a click. The only network traffic Keytide makes; it carries no text, profile or statistics.
final class Updater {
    static let endpoint = URL(string: "https://api.github.com/repos/firexrwt/keytide/releases/latest")!
    private static let automaticKey = "CheckForUpdates", lastCheckKey = "LastUpdateCheck"
    private static let due: TimeInterval = 72_000
    let current = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(Version.init)
    // An automatic check only changes the menu; a window answers checks the user asked for.
    private(set) var latest = ReleaseCheck.current
    // The newest published version from the last full answer, so a 304 can still name it.
    private var published: Version?
    var onStatus: ((String) -> Void)?
    private let session: URLSession
    private let installer = UpdateInstaller()
    private var etag: String?
    private var busy = false
    private var scheduler: NSBackgroundActivityScheduler?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = ["Accept": "application/vnd.github+json",
                                               "User-Agent": "Keytide/\(current?.description ?? "dev")"]
        session = URLSession(configuration: configuration)
    }

    var automatic: Bool { UserDefaults.standard.object(forKey: Self.automaticKey) as? Bool ?? true }

    func setAutomatic(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.automaticKey)
        start()
    }

    // The system runs the daily check when convenient; both it and the launch check skip if a check succeeded
    // recently, so they never double up. The launch check waits for the network to come up after login.
    func start() {
        scheduler?.invalidate(); scheduler = nil
        guard automatic else { return }
        let activity = NSBackgroundActivityScheduler(identifier: "dev.firexrwt.keytide.update-check")
        activity.repeats = true; activity.interval = 86_400; activity.tolerance = 3_600; activity.qualityOfService = .utility
        activity.schedule { [weak self] finished in
            DispatchQueue.main.async { self?.checkIfDue() }
            finished(.finished)
        }
        scheduler = activity
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in self?.checkIfDue() }
    }

    private func checkIfDue() {
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        if automatic, Date().timeIntervalSince(last) > Self.due { check(manual: false) }
    }

    // `answered`: called on main once the request is over (before any alert), so a caller can clear its "checking".
    func check(manual: Bool, answered: (() -> Void)? = nil) {
        guard !busy else { if manual { onStatus?(tr("update.busy")) }; answered?(); return }
        guard let current else { answered?(); if manual { UpdateAlert.failed(tr("update.unknownVersion")) }; return }
        busy = true
        var request = URLRequest(url: Self.endpoint)
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                answered?()
                self?.finish(data, response as? HTTPURLResponse, error, manual: manual, current: current)
            }
        }.resume()
    }

    private func finish(_ data: Data?, _ response: HTTPURLResponse?, _ error: Error?, manual: Bool, current: Version) {
        busy = false
        guard error == nil, let response, response.statusCode == 200 || response.statusCode == 304 else {
            let code = response.map { "HTTP \($0.statusCode)" } ?? "offline"
            UpdateInstaller.log.error("check failed: \(code, privacy: .public)")
            InputDiagnostics.note("update check failed: \(code)")
            if manual { UpdateAlert.failed(response.map { tr("update.httpStatus", String($0.statusCode)) } ?? tr("update.offline")) }
            return
        }
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
        if response.statusCode == 200, let data {
            etag = response.value(forHTTPHeaderField: "ETag")
            latest = ReleaseInfo.check(data, current: current)
            published = ReleaseInfo.latest(data)
        }
        guard manual else { return }
        // "Up to date" only when GitHub's answer named a version; otherwise say it could not be read.
        guard published != nil else { UpdateAlert.failed(tr("update.unreadable")); return }
        switch latest {
        case .current: UpdateAlert.current(current, published: published)
        case .update(let release): UpdateAlert.available(release, current: current) { install(release) }
        case .manual(let version, let page): UpdateAlert.manual(version, page: page, current: current)
        }
    }

    // `shown`: the release the alert offered; the menu item installs whatever is current.
    func install(_ shown: ReleaseInfo? = nil) {
        guard case .update(let release) = latest, shown == nil || shown == release else { return }
        guard !busy else { onStatus?(tr("update.busy")); return }
        busy = true
        onStatus?(tr("update.downloading", release.version.description))
        installer.install(release) { [weak self] failure in
            guard let self else { return }
            busy = false
            guard let failure else {
                latest = .current
                if UpdateInstaller.relaunch(Bundle.main.bundleURL) { NSApp.terminate(nil) }
                else { onStatus?(tr("update.installedRestart", release.version.description)) }
                return
            }
            // A file that fails the signature check is not something to install by hand either.
            // A window as well as the status line: the user asked for this update and must see why it did not happen.
            if failure == .signature || failure == .image {
                onStatus?(tr("update.rejected", failure.message))
                UpdateAlert.failed(tr("update.rejected", failure.message), title: tr("update.notInstalled.title"))
            } else {
                onStatus?(tr("update.notInstalled", failure.message))
                NSWorkspace.shared.open(release.page)
                UpdateAlert.failed(tr("update.notInstalled", failure.message), title: tr("update.notInstalled.title"))
            }
        }
    }
}
