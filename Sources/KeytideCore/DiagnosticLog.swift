import Foundation

// The diagnostic trail for bug reports, built to say what Keytide decided and nothing about the person:
// lines are numbered, never timed; apps are "app1", "app2" in the order they appear, never their IDs; each line is
// one bounded line. Memory only, cleared with the run. Thread-safe: update failures arrive from background queues.
public final class DiagnosticLog {
    public static let lineLimit = 200
    private let capacity: Int
    private let lock = NSLock()
    private var stored: [String] = []
    private var counter = 0
    private var apps: [String: String] = [:]

    public init(capacity: Int) { self.capacity = capacity }

    public func record(_ line: String) {
        let flat = line.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        lock.lock(); defer { lock.unlock() }
        counter += 1
        if stored.count >= capacity { stored.removeFirst(stored.count - capacity + 1) }
        stored.append(String("#\(counter) \(flat)".prefix(Self.lineLimit)))
    }

    // A number instead of the app's ID: enough to see that the app changed, nothing about which app it was.
    public func app(_ bundleID: String) -> String {
        lock.lock(); defer { lock.unlock() }
        if let known = apps[bundleID] { return known }
        let token = "app\(apps.count + 1)"
        apps[bundleID] = token
        return token
    }

    public var lines: [String] { lock.lock(); defer { lock.unlock() }; return stored }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        stored.removeAll(); counter = 0; apps.removeAll()
    }
}
