import CursorCostCore
import Darwin
import Foundation
import Security

enum AppUpdateLaunchError: Error {
    case cancelled
    case failed
}

enum AppUpdateSignature {
    static func teamIdentifier(at url: URL) -> String? {
        guard let code = staticCode(at: url) else { return nil }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String,
              AppUpdateFeed.isTeamIdentifier(team) else {
            return nil
        }
        return team
    }

    static func isTrusted(_ url: URL, teamIdentifier: String) -> Bool {
        guard AppUpdateFeed.isTeamIdentifier(teamIdentifier), let code = staticCode(at: url) else { return false }
        let requirementText = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement else {
            return false
        }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    private static func staticCode(at url: URL) -> SecStaticCode? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess else { return nil }
        return code
    }
}

enum AppUpdateLauncher {
    static func launch(
        pid: Int32,
        source: String,
        destination: String,
        cleanup: String,
        privileged: Bool
    ) throws {
        let consoleUser: UInt32? = privileged && getuid() != 0 ? UInt32(getuid()) : nil
        let script = AppUpdateInstallerScript.swap(
            pid: pid,
            source: source,
            destination: destination,
            cleanup: cleanup,
            consoleUser: consoleUser
        )
        if privileged {
            try launchPrivileged(script)
        } else {
            try launchDetached(script)
        }
    }

    private static func launchDetached(_ script: String) throws {
        let arguments = ["/bin/bash", "-c", script]
        let allocated = arguments.compactMap { strdup($0) }
        guard allocated.count == arguments.count else {
            allocated.forEach { free($0) }
            throw AppUpdateLaunchError.failed
        }
        defer { allocated.forEach { free($0) } }
        var argv: [UnsafeMutablePointer<CChar>?] = allocated.map { $0 }
        argv.append(nil)
        var attributes: posix_spawnattr_t?
        guard posix_spawnattr_init(&attributes) == 0 else { throw AppUpdateLaunchError.failed }
        defer { posix_spawnattr_destroy(&attributes) }
        guard posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID)) == 0 else {
            throw AppUpdateLaunchError.failed
        }
        var pid: pid_t = 0
        let status = argv.withUnsafeBufferPointer { buffer in
            posix_spawn(&pid, "/bin/bash", nil, &attributes, buffer.baseAddress, environ)
        }
        guard status == 0 else { throw AppUpdateLaunchError.failed }
    }

    private static func launchPrivileged(_ script: String) throws {
        let source = #"""
        on run argv
            set payload to item 1 of argv
            set command to "/usr/bin/perl -e 'use POSIX; $SIG{HUP}=\"IGNORE\"; fork and exit; POSIX::setsid(); fork and exit; exec @ARGV' /bin/bash -c " & quoted form of payload
            do shell script command with administrator privileges
        end run
        """#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source, script]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let errorText = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            if errorText.contains("User canceled") || errorText.contains("(-128)") {
                throw AppUpdateLaunchError.cancelled
            }
            throw AppUpdateLaunchError.failed
        }
    }
}
