import Foundation

// What the latest release means for this build. A newer version without a trustworthy download is "manual":
// the user is told it exists instead of hearing "up to date".
public enum ReleaseCheck: Equatable {
    case current
    case update(ReleaseInfo)
    case manual(Version, URL)
}

// GitHub's latest-release JSON is external input: anything unexpected means "no update", never a crash.
// Only the tag and the asset are read from it; every URL that is opened or downloaded is rebuilt from the tag.
public struct ReleaseInfo: Equatable {
    public static let maximumBytes = 52_428_800
    public let version: Version
    public let dmg: URL
    public let page: URL

    // The newest published version, whatever this build is: shown by a manual check ("on GitHub: Y").
    public static func latest(_ data: Data) -> Version? {
        guard data.count <= 1_048_576,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              object["draft"] as? Bool != true, object["prerelease"] as? Bool != true,
              let tag = object["tag_name"] as? String, tag.first == "v" else { return nil }
        return Version(String(tag.dropFirst()))
    }

    public static func check(_ data: Data, current: Version, repository: String = "firexrwt/keytide") -> ReleaseCheck {
        guard data.count <= 1_048_576,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              object["draft"] as? Bool != true, object["prerelease"] as? Bool != true,
              let tag = object["tag_name"] as? String, tag.first == "v",
              let version = Version(String(tag.dropFirst())), current < version,
              let page = URL(string: "https://github.com/\(repository)/releases/tag/v\(version)") else { return .current }
        let name = "Keytide-\(version).dmg"
        let link = "https://github.com/\(repository)/releases/download/v\(version)/\(name)"
        guard let assets = object["assets"] as? [[String: Any]],
              let asset = assets.first(where: { $0["name"] as? String == name }),
              let size = asset["size"] as? Int, (1...maximumBytes).contains(size),
              asset["browser_download_url"] as? String == link,
              let dmg = URL(string: link) else { return .manual(version, page) }
        return .update(ReleaseInfo(version: version, dmg: dmg, page: page))
    }
}
