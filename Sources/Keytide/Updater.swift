import AppKit
import KeytideCore

// Finds a newer GitHub release: once a day through the system scheduler, or on demand. Nothing is installed without
// a click. The only network traffic Keytide makes; it carries no text, profile or statistics.
final class Updater {
    static let endpoint = URL(string: "https://api.github.com/repos/firexrwt/keytide/releases/latest")!
    private static let automaticKey = "CheckForUpdates", lastCheckKey = "LastUpdateCheck"
    private static let due: TimeInterval = 72_000
    let current = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(Version.init)
    // An automatic check only changes the menu; status text is for checks the user asked for.
    private(set) var latest = ReleaseCheck.current
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

    func check(manual: Bool) {
        guard !busy else { if manual { onStatus?("Keytide уже обращается к GitHub, подождите") }; return }
        guard let current else { if manual { onStatus?("Версия сборки неизвестна, обновления не проверяются") }; return }
        busy = true
        var request = URLRequest(url: Self.endpoint)
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async { self?.finish(data, response as? HTTPURLResponse, error, manual: manual, current: current) }
        }.resume()
    }

    private func finish(_ data: Data?, _ response: HTTPURLResponse?, _ error: Error?, manual: Bool, current: Version) {
        busy = false
        guard error == nil, let response, response.statusCode == 200 || response.statusCode == 304 else {
            let reason = response.map { "GitHub ответил \($0.statusCode)" } ?? "Нет связи с GitHub"
            UpdateInstaller.log.error("check failed: \(reason, privacy: .public)")
            if manual { onStatus?("\(reason), обновления не проверены") }
            return
        }
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
        if response.statusCode == 200, let data {
            etag = response.value(forHTTPHeaderField: "ETag")
            latest = ReleaseInfo.check(data, current: current)
        }
        guard manual else { return }
        switch latest {
        case .current: onStatus?("Установлена последняя версия \(current)")
        case .update(let release): onStatus?("Доступна версия \(release.version), обновление - в меню")
        case .manual(let version, _): onStatus?("Вышла версия \(version), но её нельзя установить из меню")
        }
    }

    func install() {
        guard case .update(let release) = latest else { return }
        guard !busy else { onStatus?("Keytide уже обращается к GitHub, подождите"); return }
        busy = true
        onStatus?("Загрузка Keytide \(release.version)...")
        installer.install(release) { [weak self] failure in
            guard let self else { return }
            busy = false
            guard let failure else {
                latest = .current
                if UpdateInstaller.relaunch(Bundle.main.bundleURL) { NSApp.terminate(nil) }
                else { onStatus?("Keytide \(release.version) установлен, перезапустите приложение") }
                return
            }
            // A file that fails the signature check is not something to install by hand either.
            if failure == .signature || failure == .image {
                onStatus?("Обновление отклонено: \(failure.rawValue). Не устанавливайте эту версию вручную.")
            } else {
                onStatus?("Обновление не установлено: \(failure.rawValue). Открыта страница релиза.")
                NSWorkspace.shared.open(release.page)
            }
        }
    }
}
