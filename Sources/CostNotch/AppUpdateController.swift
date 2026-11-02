import AppKit
import Combine
import CursorCostCore
import Foundation

private enum AppUpdateWorkError: Error {
    case download
    case rejected
    case replace
}

private struct PreparedUpdate: Sendable {
    let app: URL
    let cleanup: URL
}

private final class AppUpdateSessionGate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let url = request.url, AppUpdateFeed.allowsRedirect(url) else { return nil }
        return request
    }
}

@MainActor
final class AppUpdateController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppRelease)
        case installing(AppRelease)
        case checkFailed
        case failed(AppRelease, String)
    }

    @Published private(set) var phase: Phase = .idle

    private let session: URLSession
    private let gate: AppUpdateSessionGate
    private let currentBuild: Int
    private let bundleURL: URL
    private let homeDirectory: URL
    private var started = false
    private var checking = false
    private var reportResult = false

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 180
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        let gate = AppUpdateSessionGate()
        self.gate = gate
        session = URLSession(configuration: configuration, delegate: gate, delegateQueue: nil)
        currentBuild = Self.readBuild()
        bundleURL = Bundle.main.bundleURL
        homeDirectory = FileManager.default.homeDirectoryForCurrentUser
    }

    var offeredVersion: String? {
        switch phase {
        case .available(let release), .installing(let release), .failed(let release, _):
            return release.version
        case .idle, .checking, .upToDate, .checkFailed:
            return nil
        }
    }

    var isChecking: Bool {
        if case .checking = phase { return true }
        return false
    }

    var isInstalling: Bool {
        if case .installing = phase { return true }
        return false
    }

    var statusMessage: String? {
        switch phase {
        case .upToDate:
            return "Cost Notch is up to date"
        case .checkFailed:
            return "Couldn't check for updates"
        case .failed(_, let message):
            return message
        case .idle, .checking, .available, .installing:
            return nil
        }
    }

    func start() {
        guard !started else { return }
        started = true
        Task { await run() }
    }

    func checkForUpdates() async {
        guard !isInstalling else { return }
        reportResult = true
        phase = .checking
        await check()
    }

    func install() async {
        let release: AppRelease
        switch phase {
        case .available(let value), .failed(let value, _):
            release = value
        case .idle, .checking, .upToDate, .checkFailed, .installing:
            return
        }
        guard AppUpdateFeed.isInstallableBundle(path: bundleURL.path, home: homeDirectory.path) else {
            NSWorkspace.shared.open(release.releaseURL)
            return
        }
        guard let team = AppUpdateSignature.teamIdentifier(at: bundleURL),
              AppUpdateSignature.isTrusted(bundleURL, teamIdentifier: team) else {
            NSWorkspace.shared.open(release.releaseURL)
            return
        }
        phase = .installing(release)
        var cleanup: URL?
        do {
            let prepared = try await download(release)
            cleanup = prepared.cleanup
            guard AppUpdateSignature.isTrusted(prepared.app, teamIdentifier: team) else {
                throw AppUpdateWorkError.rejected
            }
            let destination = bundleURL.standardizedFileURL.path
            let privileged = !FileManager.default.isWritableFile(atPath: bundleURL.deletingLastPathComponent().path)
            guard AppUpdateFeed.swapAllowed(
                pid: ProcessInfo.processInfo.processIdentifier,
                source: prepared.app.path,
                destination: destination,
                cleanup: prepared.cleanup.path,
                home: homeDirectory.path
            ) else {
                throw AppUpdateWorkError.replace
            }
            let source = prepared.app.path
            let cleanupPath = prepared.cleanup.path
            let pid = ProcessInfo.processInfo.processIdentifier
            try await Task.detached {
                try AppUpdateLauncher.launch(
                    pid: pid,
                    source: source,
                    destination: destination,
                    cleanup: cleanupPath,
                    privileged: privileged
                )
            }.value
            NSApp.terminate(nil)
        } catch let error as AppUpdateWorkError {
            discard(cleanup)
            switch error {
            case .download:
                phase = .failed(release, "Couldn't download the update")
            case .rejected:
                phase = .failed(release, "Update could not be verified")
            case .replace:
                phase = .failed(release, "Cost Notch could not be replaced")
            }
        } catch let error as AppUpdateLaunchError {
            discard(cleanup)
            switch error {
            case .cancelled:
                phase = .available(release)
            case .failed:
                phase = .failed(release, "Cost Notch could not be replaced")
            }
        } catch {
            discard(cleanup)
            phase = .failed(release, "Couldn't download the update")
        }
    }

    private func run() async {
        await check()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 6 * 60 * 60 * 1_000_000_000)
            if Task.isCancelled { break }
            await check()
        }
    }

    private func check() async {
        guard !isInstalling else { return }
        guard currentBuild > 0 else {
            finishCheck(release: nil, failed: true)
            return
        }
        guard !checking else { return }
        checking = true
        defer { checking = false }
        do {
            var request = URLRequest(url: AppUpdateFeed.latestURL)
            request.setValue("CostNotch", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await session.data(for: request)
            guard !isInstalling else {
                reportResult = false
                return
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                finishCheck(release: nil, failed: true)
                return
            }
            finishCheck(release: AppUpdateFeed.release(from: data), failed: false)
        } catch {
            finishCheck(release: nil, failed: true)
        }
    }

    private func finishCheck(release: AppRelease?, failed: Bool) {
        let report = reportResult
        reportResult = false
        guard !isInstalling else { return }
        if let release, AppUpdateFeed.isNewer(release, thanBuild: currentBuild) {
            phase = .available(release)
            return
        }
        if failed {
            if report {
                phase = .checkFailed
            }
            return
        }
        if report {
            phase = .upToDate
            return
        }
        switch phase {
        case .available, .failed, .checkFailed, .checking:
            phase = .idle
        case .idle, .upToDate, .installing:
            break
        }
    }

    private func download(_ release: AppRelease) async throws -> PreparedUpdate {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? homeDirectory.appendingPathComponent("Library/Caches", isDirectory: true)
        let work = caches
            .appendingPathComponent("local.cost-notch", isDirectory: true)
            .appendingPathComponent("updates", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            var request = URLRequest(url: release.assetURL)
            request.setValue("CostNotch", forHTTPHeaderField: "User-Agent")
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (temp, response) = try await session.download(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw AppUpdateWorkError.download
            }
            let zip = work.appendingPathComponent("update.zip")
            try moveDownload(from: temp, to: zip)
            let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
            try FileManager.default.createDirectory(at: unpacked, withIntermediateDirectories: true)
            try await unzip(zip: zip, to: unpacked)
            let app = unpacked.appendingPathComponent(AppUpdateFeed.applicationDirectoryName, isDirectory: true)
            var isDirectory = ObjCBool(false)
            guard FileManager.default.fileExists(atPath: app.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw AppUpdateWorkError.rejected
            }
            guard let info = readInfo(app),
                  AppUpdateFeed.acceptsDownloadedApp(
                    bundleIdentifier: info.bundleIdentifier,
                    version: info.version,
                    build: info.build,
                    release: release,
                    currentBuild: currentBuild
                  ) else {
                throw AppUpdateWorkError.rejected
            }
            return PreparedUpdate(app: app, cleanup: work)
        } catch {
            try? FileManager.default.removeItem(at: work)
            if let workError = error as? AppUpdateWorkError {
                throw workError
            }
            throw AppUpdateWorkError.download
        }
    }

    private func unzip(zip: URL, to destination: URL) async throws {
        let zipPath = zip.path
        let destinationPath = destination.path
        let status = try await Task.detached { () -> Int32 in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", zipPath, destinationPath]
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }.value
        guard status == 0 else { throw AppUpdateWorkError.download }
    }

    private func moveDownload(from temp: URL, to zip: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: zip.path) {
            try manager.removeItem(at: zip)
        }
        do {
            try manager.moveItem(at: temp, to: zip)
        } catch {
            try manager.copyItem(at: temp, to: zip)
        }
    }

    private func readInfo(_ appURL: URL) -> (bundleIdentifier: String, version: String, build: Int)? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleIdentifier = object["CFBundleIdentifier"] as? String,
              let version = object["CFBundleShortVersionString"] as? String,
              let build = Self.buildValue(object["CFBundleVersion"]) else {
            return nil
        }
        return (bundleIdentifier, version, build)
    }

    private func discard(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func readBuild() -> Int {
        buildValue(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")) ?? 0
    }

    private static func buildValue(_ value: Any?) -> Int? {
        if let string = value as? String {
            guard let build = Int(string), build > 0, String(build) == string else { return nil }
            return build
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
            let build = number.intValue
            return build > 0 ? build : nil
        }
        return nil
    }
}
