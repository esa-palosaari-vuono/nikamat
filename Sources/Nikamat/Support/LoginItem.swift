import Foundation

/// Start at login, via a plain launchd agent.
///
/// `SMAppService` would be the modern route, but it requires a signed
/// application and this one is signed ad hoc. A LaunchAgent plist has no such
/// requirement, works on every macOS in living memory, and — being a file the
/// user can read and delete — is easy to reason about. The Makefile writes the
/// same plist, so `make autostart` and this checkbox are interchangeable.
@MainActor
enum LoginItem {
    private static let label = "fi.esapalosaari.nikamat"

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
            let appPath = Bundle.main.bundleURL.path
            let plist = """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
                "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
                <plist version="1.0"><dict>
                    <key>Label</key><string>\(label)</string>
                    <key>ProgramArguments</key>
                    <array>
                        <string>/usr/bin/open</string>
                        <string>-a</string>
                        <string>\(appPath)</string>
                    </array>
                    <key>RunAtLoad</key><true/>
                </dict></plist>
                """
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? plist.write(to: url, atomically: true, encoding: .utf8)
            launchctl("load")
        } else {
            launchctl("unload")
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func launchctl(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = [command, plistURL.path]
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
