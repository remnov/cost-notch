import CursorCostCore
import Foundation
import Testing

struct AppUpdateTests {
    @Test
    func release_givenLatestZipAndOtherAssets_thenParsesTheHighestMatchingBuild() {
        let given = feed(
            tag: "v1.3.0",
            assets: [
                asset(
                    name: "Cost-Notch-1.3.0.dmg",
                    url: "https://github.com/remnov/cost-notch/releases/download/v1.3.0/Cost-Notch-1.3.0.dmg"
                ),
                asset(
                    name: "Cost-Notch-1.3.0-6.zip",
                    url: "https://github.com/remnov/cost-notch/releases/download/v1.3.0/Cost-Notch-1.3.0-6.zip"
                ),
                asset(
                    name: "Cost-Notch-1.3.0-7.zip",
                    url: "https://github.com/remnov/cost-notch/releases/download/v1.3.0/Cost-Notch-1.3.0-7.zip"
                ),
            ]
        )

        let then = AppUpdateFeed.release(from: given)

        #expect(then?.version == "1.3.0")
        #expect(then?.build == 7)
        #expect(then?.assetURL.absoluteString == "https://github.com/remnov/cost-notch/releases/download/v1.3.0/Cost-Notch-1.3.0-7.zip")
        #expect(then?.releaseURL.absoluteString == "https://github.com/remnov/cost-notch/releases/tag/v1.3.0")
    }

    @Test
    func release_givenUnusableFeed_thenReturnsNil() {
        let zip = asset(
            name: "Cost-Notch-1.3.0-6.zip",
            url: "https://github.com/remnov/cost-notch/releases/download/v1.3.0/Cost-Notch-1.3.0-6.zip"
        )
        let prerelease = feed(tag: "v1.3.0", prerelease: true, assets: [zip])
        let draft = feed(tag: "v1.3.0", draft: true, assets: [zip])
        let mismatchedTag = feed(tag: "v1.2.0", assets: [zip])
        let foreignHost = feed(
            tag: "v1.3.0",
            assets: [asset(name: "Cost-Notch-1.3.0-6.zip", url: "https://evil.example/Cost-Notch-1.3.0-6.zip")]
        )
        let insecure = feed(
            tag: "v1.3.0",
            assets: [asset(name: "Cost-Notch-1.3.0-6.zip", url: "http://github.com/remnov/cost-notch/releases/download/v1.3.0/Cost-Notch-1.3.0-6.zip")]
        )
        let otherRepo = feed(
            tag: "v1.3.0",
            assets: [asset(name: "Cost-Notch-1.3.0-6.zip", url: "https://github.com/other/cost-notch/releases/download/v1.3.0/Cost-Notch-1.3.0-6.zip")]
        )
        let diskImageOnly = feed(
            tag: "v1.3.0",
            assets: [asset(name: "Cost-Notch-1.3.0.dmg", url: "https://github.com/remnov/cost-notch/releases/download/v1.3.0/Cost-Notch-1.3.0.dmg")]
        )
        let leadingZero = feed(
            tag: "v1.3.0",
            assets: [asset(name: "Cost-Notch-1.3.0-06.zip", url: "https://github.com/remnov/cost-notch/releases/download/v1.3.0/Cost-Notch-1.3.0-06.zip")]
        )

        #expect(AppUpdateFeed.release(from: prerelease) == nil)
        #expect(AppUpdateFeed.release(from: draft) == nil)
        #expect(AppUpdateFeed.release(from: mismatchedTag) == nil)
        #expect(AppUpdateFeed.release(from: foreignHost) == nil)
        #expect(AppUpdateFeed.release(from: insecure) == nil)
        #expect(AppUpdateFeed.release(from: otherRepo) == nil)
        #expect(AppUpdateFeed.release(from: diskImageOnly) == nil)
        #expect(AppUpdateFeed.release(from: leadingZero) == nil)
    }

    @Test
    func isNewer_givenBuildNumbers_thenIgnoresMarketingVersion() {
        let higher = sample(version: "1.2.0", build: 6)
        let same = sample(version: "9.0.0", build: 5)
        let lower = sample(version: "1.3.0", build: 4)

        #expect(AppUpdateFeed.isNewer(higher, thanBuild: 5))
        #expect(!AppUpdateFeed.isNewer(same, thanBuild: 5))
        #expect(!AppUpdateFeed.isNewer(lower, thanBuild: 5))
    }

    @Test
    func acceptsDownloadedApp_givenPlist_thenRequiresExactReleaseAboveCurrentBuild() {
        let given = sample(version: "1.3.0", build: 6)

        let accepted = AppUpdateFeed.acceptsDownloadedApp(
            bundleIdentifier: "local.cost-notch",
            version: "1.3.0",
            build: 6,
            release: given,
            currentBuild: 5
        )
        let wrongBundle = AppUpdateFeed.acceptsDownloadedApp(
            bundleIdentifier: "com.example.other",
            version: "1.3.0",
            build: 6,
            release: given,
            currentBuild: 5
        )
        let wrongVersion = AppUpdateFeed.acceptsDownloadedApp(
            bundleIdentifier: "local.cost-notch",
            version: "1.3.1",
            build: 6,
            release: given,
            currentBuild: 5
        )
        let notNewer = AppUpdateFeed.acceptsDownloadedApp(
            bundleIdentifier: "local.cost-notch",
            version: "1.3.0",
            build: 6,
            release: given,
            currentBuild: 6
        )

        #expect(accepted)
        #expect(!wrongBundle)
        #expect(!wrongVersion)
        #expect(!notNewer)
    }

    @Test
    func isInstallableBundle_givenApplicationsPaths_thenAcceptsOnlyThoseCopies() {
        let home = "/Users/remi"

        #expect(AppUpdateFeed.isInstallableBundle(path: "/Applications/Cost Notch.app", home: home))
        #expect(AppUpdateFeed.isInstallableBundle(path: "/Applications/../Applications/Cost Notch.app/", home: home))
        #expect(AppUpdateFeed.isInstallableBundle(path: "/Users/remi/Applications/Cost Notch.app", home: home))
        #expect(!AppUpdateFeed.isInstallableBundle(path: "/Users/remi/PROJECTS/dist/Cost Notch.app", home: home))
        #expect(!AppUpdateFeed.isInstallableBundle(path: "/Applications/CostNotch.app", home: home))
    }

    @Test
    func swapAllowed_givenCacheCleanupAndApplicationsDestination_thenAllowsOnlyThatSwap() {
        let home = "/Users/remi"
        let cleanup = "/Users/remi/Library/Caches/local.cost-notch/updates/abc"
        let source = cleanup + "/unpacked/Cost Notch.app"
        let destination = "/Applications/Cost Notch.app"

        let allowed = AppUpdateFeed.swapAllowed(
            pid: 42,
            source: source,
            destination: destination,
            cleanup: cleanup,
            home: home
        )
        let outsideApplications = AppUpdateFeed.swapAllowed(
            pid: 42,
            source: source,
            destination: "/Users/remi/PROJECTS/dist/Cost Notch.app",
            cleanup: cleanup,
            home: home
        )
        let outsideCache = AppUpdateFeed.swapAllowed(
            pid: 42,
            source: "/tmp/Cost Notch.app",
            destination: destination,
            cleanup: "/tmp/updates/abc",
            home: home
        )
        let deadProcess = AppUpdateFeed.swapAllowed(
            pid: 0,
            source: source,
            destination: destination,
            cleanup: cleanup,
            home: home
        )

        #expect(allowed)
        #expect(!outsideApplications)
        #expect(!outsideCache)
        #expect(!deadProcess)
    }

    @Test
    func installerScript_givenPathWithQuoteAndSpace_thenQuotesAndStagesBesideTheApp() {
        let given = AppUpdateInstallerScript.swap(
            pid: 42,
            source: "/tmp/Cost's Notch.app",
            destination: "/Applications/Cost Notch.app",
            cleanup: "/Users/remi/Library/Caches/local.cost-notch/updates/abc"
        )

        #expect(given == """
        set -euo pipefail
        trap '' HUP
        while /bin/kill -0 42 2>/dev/null; do /bin/sleep 0.2; done
        /bin/rm -rf '/Applications/Cost Notch.app.update'
        /usr/bin/ditto '/tmp/Cost'\\''s Notch.app' '/Applications/Cost Notch.app.update'
        /bin/rm -rf '/Applications/Cost Notch.app'
        /bin/mv '/Applications/Cost Notch.app.update' '/Applications/Cost Notch.app'
        /usr/bin/open '/Applications/Cost Notch.app'
        /bin/rm -rf '/Users/remi/Library/Caches/local.cost-notch/updates/abc'
        """)
        let rooted = AppUpdateInstallerScript.swap(
            pid: 42,
            source: "/tmp/Cost's Notch.app",
            destination: "/Applications/Cost Notch.app",
            cleanup: "/Users/remi/Library/Caches/local.cost-notch/updates/abc",
            consoleUser: 501
        )
        #expect(rooted.contains("/bin/launchctl asuser 501 /usr/bin/open '/Applications/Cost Notch.app' || /usr/bin/open '/Applications/Cost Notch.app'"))
    }

    @Test
    func isTeamIdentifier_givenAlphabet_thenAcceptsTenUppercaseCharacters() {
        #expect(AppUpdateFeed.isTeamIdentifier("ABCDE12345"))
        #expect(!AppUpdateFeed.isTeamIdentifier("abcde12345"))
        #expect(!AppUpdateFeed.isTeamIdentifier("ABCDE1234"))
        #expect(!AppUpdateFeed.isTeamIdentifier("ABCDE123456"))
        #expect(!AppUpdateFeed.isTeamIdentifier("ABCDE1234!"))
    }

    @Test
    func allowsRedirect_givenDownloadHosts_thenAllowsOnlyHTTPSGitHub() {
        #expect(AppUpdateFeed.allowsRedirect(URL(string: "https://api.github.com/repos/remnov/cost-notch/releases/latest")!))
        #expect(AppUpdateFeed.allowsRedirect(URL(string: "https://github.com/remnov/cost-notch/releases/download/v1.3.0/Cost-Notch-1.3.0-6.zip")!))
        #expect(AppUpdateFeed.allowsRedirect(URL(string: "https://release-assets.githubusercontent.com/file?sig=1")!))
        #expect(!AppUpdateFeed.allowsRedirect(URL(string: "http://github.com/remnov/cost-notch")!))
        #expect(!AppUpdateFeed.allowsRedirect(URL(string: "https://user@github.com/remnov/cost-notch")!))
        #expect(!AppUpdateFeed.allowsRedirect(URL(string: "https://evil.example/file.zip")!))
        #expect(!AppUpdateFeed.allowsRedirect(URL(string: "https://github.com:444/remnov/cost-notch")!))
    }
}

private func feed(tag: String, draft: Bool = false, prerelease: Bool = false, assets: [String]) -> Data {
    let json = """
    {"tag_name":"\(tag)","draft":\(draft),"prerelease":\(prerelease),"assets":[\(assets.joined(separator: ","))]}
    """
    return Data(json.utf8)
}

private func asset(name: String, url: String) -> String {
    #"{"name":"\#(name)","browser_download_url":"\#(url)"}"#
}

private func sample(version: String, build: Int) -> AppRelease {
    let tag = "v\(version)"
    let name = "Cost-Notch-\(version)-\(build).zip"
    return AppRelease(
        version: version,
        build: build,
        assetURL: URL(string: "https://github.com/remnov/cost-notch/releases/download/\(tag)/\(name)")!,
        releaseURL: URL(string: "https://github.com/remnov/cost-notch/releases/tag/\(tag)")!
    )
}
