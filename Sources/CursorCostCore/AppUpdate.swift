import Foundation

public struct AppRelease: Equatable, Sendable {
    public let version: String
    public let build: Int
    public let assetURL: URL
    public let releaseURL: URL

    public init(version: String, build: Int, assetURL: URL, releaseURL: URL) {
        self.version = version
        self.build = build
        self.assetURL = assetURL
        self.releaseURL = releaseURL
    }
}

public enum AppUpdateFeed {
    public static let latestURL = URL(string: "https://api.github.com/repos/remnov/cost-notch/releases/latest")!
    public static let bundleIdentifier = "local.cost-notch"
    public static let applicationDirectoryName = "Cost Notch.app"

    public static func release(from data: Data) -> AppRelease? {
        guard let raw = try? UsageMapper.parseJSON(data),
              let object = JSON.object(raw),
              JSON.bool(object["draft"]) != true,
              JSON.bool(object["prerelease"]) != true,
              let tag = JSON.string(object["tag_name"]),
              let assets = JSON.array(object["assets"]) else {
            return nil
        }
        let matches: [AppRelease] = assets.compactMap { item in
            guard let asset = JSON.object(item),
                  let name = JSON.string(asset["name"]),
                  let parsed = parsedZipName(name),
                  tag == "v\(parsed.version)",
                  let urlText = JSON.string(asset["browser_download_url"]),
                  let url = URL(string: urlText),
                  acceptsAssetURL(url, name: name, tag: tag),
                  let releaseURL = URL(string: "https://github.com/remnov/cost-notch/releases/tag/\(tag)") else {
                return nil
            }
            return AppRelease(version: parsed.version, build: parsed.build, assetURL: url, releaseURL: releaseURL)
        }
        return matches.max { $0.build < $1.build }
    }

    public static func isNewer(_ release: AppRelease, thanBuild currentBuild: Int) -> Bool {
        release.build > currentBuild
    }

    public static func acceptsDownloadedApp(
        bundleIdentifier: String,
        version: String,
        build: Int,
        release: AppRelease,
        currentBuild: Int
    ) -> Bool {
        bundleIdentifier == Self.bundleIdentifier
            && version == release.version
            && build == release.build
            && build > currentBuild
    }

    public static func isInstallableBundle(path: String, home: String) -> Bool {
        let bundle = standardized(path)
        if bundle == standardized("/Applications/\(applicationDirectoryName)") {
            return true
        }
        let userApplications = URL(fileURLWithPath: home)
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent(applicationDirectoryName)
            .path
        return bundle == standardized(userApplications)
    }

    public static func swapAllowed(
        pid: Int32,
        source: String,
        destination: String,
        cleanup: String,
        home: String
    ) -> Bool {
        guard pid > 0 else { return false }
        let sourceURL = URL(fileURLWithPath: source).standardizedFileURL
        let cleanupURL = URL(fileURLWithPath: cleanup).standardizedFileURL
        let destinationURL = URL(fileURLWithPath: destination).standardizedFileURL
        guard sourceURL.lastPathComponent == applicationDirectoryName else { return false }
        guard sourceURL.path.hasPrefix(cleanupURL.path + "/") else { return false }
        guard isInstallableBundle(path: destinationURL.path, home: home) else { return false }
        guard cleanupAllowed(cleanupURL) else { return false }
        guard destinationURL.path != cleanupURL.path else { return false }
        guard !destinationURL.path.hasPrefix(cleanupURL.path + "/") else { return false }
        guard !cleanupURL.path.hasPrefix(destinationURL.path + "/") else { return false }
        return sourceURL.path != destinationURL.path
    }

    public static func isTeamIdentifier(_ value: String) -> Bool {
        value.count == 10 && value.allSatisfy { character in
            character.isASCII && (character.isNumber || (character.isLetter && character.isUppercase))
        }
    }

    public static func allowsRedirect(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.port == nil || url.port == 443, let host = url.host else {
            return false
        }
        switch host.lowercased() {
        case "api.github.com", "github.com", "release-assets.githubusercontent.com",
             "objects.githubusercontent.com", "github-releases.githubusercontent.com":
            return true
        default:
            return false
        }
    }

    static func acceptsAssetURL(_ url: URL, name: String, tag: String) -> Bool {
        guard url.scheme == "https", url.host == "github.com", url.user == nil else { return false }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 6 else { return false }
        return parts[0] == "remnov"
            && parts[1] == "cost-notch"
            && parts[2] == "releases"
            && parts[3] == "download"
            && parts[4] == tag
            && parts[5] == name
            && parsedZipName(name) != nil
    }

    static func parsedZipName(_ name: String) -> (version: String, build: Int)? {
        let prefix = "Cost-Notch-"
        let suffix = ".zip"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
        let stem = String(name.dropFirst(prefix.count).dropLast(suffix.count))
        guard let separator = stem.lastIndex(of: "-") else { return nil }
        let version = String(stem[..<separator])
        let buildText = String(stem[stem.index(after: separator)...])
        guard isMarketingVersion(version), let build = Int(buildText), build > 0, String(build) == buildText else {
            return nil
        }
        return (version, build)
    }

    static func isMarketingVersion(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return false }
        return parts.allSatisfy { part in
            guard let number = Int(part), number >= 0, String(number) == part else { return false }
            return true
        }
    }

    private static func cleanupAllowed(_ cleanup: URL) -> Bool {
        let parts = cleanup.path.split(separator: "/").map(String.init)
        guard let library = parts.firstIndex(of: "Library"),
              parts.indices.contains(library + 4),
              parts[library + 1] == "Caches",
              parts[library + 2] == "local.cost-notch",
              parts[library + 3] == "updates" else {
            return false
        }
        return parts.count > library + 4
    }

    private static func standardized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

public enum AppUpdateInstallerScript {
    public static func swap(
        pid: Int32,
        source: String,
        destination: String,
        cleanup: String,
        consoleUser: UInt32? = nil
    ) -> String {
        let staging = destination + ".update"
        let open = shellQuote(destination)
        let reopen: String
        if let consoleUser, consoleUser > 0 {
            reopen = "/bin/launchctl asuser \(consoleUser) /usr/bin/open \(open) || /usr/bin/open \(open)"
        } else {
            reopen = "/usr/bin/open \(open)"
        }
        return """
        set -euo pipefail
        trap '' HUP
        while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done
        /bin/rm -rf \(shellQuote(staging))
        /usr/bin/ditto \(shellQuote(source)) \(shellQuote(staging))
        /bin/rm -rf \(shellQuote(destination))
        /bin/mv \(shellQuote(staging)) \(shellQuote(destination))
        \(reopen)
        /bin/rm -rf \(shellQuote(cleanup))
        """
    }

    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
