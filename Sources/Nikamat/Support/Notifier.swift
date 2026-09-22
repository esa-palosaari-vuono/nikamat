import AppKit
import UserNotifications

/// Advance warning that a break is about to open.
///
/// A window that appears without warning mid-sentence is the reason these apps
/// get uninstalled, so the break announces itself a few seconds early.
///
/// Delivery is best-effort by design. An app signed ad hoc — which is what you
/// get without a paid developer certificate — is often refused by Notification
/// Centre, so there are three tiers: the real notification, then
/// `terminal-notifier` if it happens to be installed, and finally just a sound.
/// The break window itself never depends on any of this.
@MainActor
final class Notifier {

    private var systemNotificationsAllowed = false
    private let terminalNotifier = "/opt/homebrew/bin/terminal-notifier"

    init() {}

    /// Ask once, at launch. Failure is expected and not worth reporting.
    func requestPermission() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in self.systemNotificationsAllowed = granted }
        }
    }

    func announce(title: String, body: String, withSound: Bool) {
        if systemNotificationsAllowed {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if withSound { content.sound = .default }
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            )
            return
        }
        if FileManager.default.isExecutableFile(atPath: terminalNotifier) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: terminalNotifier)
            process.arguments = ["-title", title, "-message", body, "-group", Bundle.main.bundleIdentifier ?? "Nikamat"]
            try? process.run()
            return
        }
        if withSound { NSSound(named: "Tink")?.play() }
    }
}
