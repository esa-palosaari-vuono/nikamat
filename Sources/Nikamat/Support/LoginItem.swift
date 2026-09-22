import Foundation

/// Start at login, via a plain launchd agent.
///
/// `SMAppService` would be the modern route, but it requires a signed
/// application and this one is signed ad hoc. A LaunchAgent plist has no such
/// requirement, works on every macOS in living memory, and — being a file the
/// user can read and delete — is easy to reason about. `make autostart` runs
/// `Nikamat --login-item on`, so the Makefile and this checkbox write the very
/// same file.
@MainActor
enum LoginItem {
    private static let label = Bundle.main.bundleIdentifier ?? "fi.esapalosaari.nikamat"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) {
        let url = plistURL
        if enabled {
            guard let plist = try? agentPlist(label: label, appPath: Bundle.main.bundleURL.path) else {
                return
            }
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? plist.write(to: url, options: .atomic)
            launchctl("load")
        } else {
            launchctl("unload")
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// The LaunchAgent, serialised by Foundation rather than pasted into an XML
    /// template, so an application path containing `&` or `<` still produces a
    /// valid file.
    static func agentPlist(label: String, appPath: String) throws -> Data {
        let agent: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-a", appPath],
            "RunAtLoad": true,
        ]
        return try PropertyListSerialization.data(fromPropertyList: agent, format: .xml, options: 0)
    }

    private static func launchctl(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = [command, plistURL.path]
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
