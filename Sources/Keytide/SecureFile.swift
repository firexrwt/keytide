import Foundation
import Darwin
import KeytideCore

enum SecureFile {
    static func read(_ url: URL) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw failure() }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw failure() }
        guard info.st_mode & S_IFMT == S_IFREG else { throw ProfileError.unsupported }
        guard info.st_size >= 0, info.st_size <= Profile.maximumBytes else { throw ProfileError.tooLarge }
        let data = try handle.read(upToCount: Profile.maximumBytes + 1) ?? Data()
        guard data.count <= Profile.maximumBytes else { throw ProfileError.tooLarge }
        return data
    }

    static func write(_ data: Data, to url: URL) throws {
        guard data.count <= Profile.maximumBytes else { throw ProfileError.tooLarge }
        var path = Array(url.deletingLastPathComponent().appendingPathComponent(".keytide-XXXXXX").path.utf8CString)
        let fd = mkstemp(&path)
        guard fd >= 0 else { throw failure() }
        let temporary = String(cString: path)
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close(); unlink(temporary) }
        guard fchmod(fd, 0o600) == 0 else { throw failure() }
        try handle.write(contentsOf: data)
        try handle.close()
        guard rename(temporary, url.path) == 0 else { throw failure() }
    }

    private static func failure() -> Error { POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
}
