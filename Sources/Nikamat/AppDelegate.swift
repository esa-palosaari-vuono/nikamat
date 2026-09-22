import AppKit
import SwiftUI

/// Wires the pieces together and owns the menu bar item.
///
/// There is no main window and no Dock icon: the app is a clock with a drawing
/// attached, and both of those live in the menu bar until a break is due.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings()
    private let log = BreakLog()
    private let notifier = Notifier()
    private lazy var scheduler = Scheduler(settings: settings, notifier: notifier)
    private lazy var breaks = BreakCoordinator(
        log: log, display: BreakWindow(), preferences: { [settings] in settings.preferences }
    )
    private let panels = PanelWindows()

    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Self.menuBarIcon()
        statusItem.button?.imagePosition = .imageLeading

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        scheduler.onFire = { [weak self] tier in self?.startBreak(tier: tier) }
        scheduler.onTick = { [weak self] in self?.updateStatusTitle() }
        breaks.onSnoozed = { [weak self] tier in self?.scheduler.snooze(tier: tier) }
        breaks.onEnded = { [weak self] in
            self?.scheduler.breakFinished()
            self?.updateStatusTitle()
        }

        notifier.requestPermission()
        updateStatusTitle()

        // --break-now opens a break immediately. Useful for trying the window
        // out without waiting for the clock, and for checking a pose change.
        if CommandLine.arguments.contains("--break-now") {
            let tier: Tier = CommandLine.arguments.contains("micro") ? .micro : .long
            startBreak(tier: tier)
        }
    }

    /// The first symbol that exists on this system. Symbol availability moves
    /// between releases, and a menu bar item with no image is invisible.
    private static func menuBarIcon() -> NSImage? {
        let candidates = [
            "figure.cooldown", "figure.flexibility", "figure.arms.open",
            "figure.stand", "person.fill"
        ]
        for name in candidates {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: "Nikamat") {
                image.isTemplate = true
                return image
            }
        }
        return nil
    }

    /// Opening the app again while it runs — from Spotlight, Launchpad or the
    /// Finder — shows the settings. On a crowded menu bar macOS hides the
    /// status item, and without this there would be no way in at all.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    // MARK: - Menu bar title

    private func updateStatusTitle() {
        guard let button = statusItem?.button else { return }
        guard settings.preferences.showCountdown, !scheduler.isPaused, !breaks.isRunning else {
            button.title = ""
            return
        }
        let remaining = scheduler.nextFire.timeIntervalSinceNow
        button.title = " " + Self.compactCountdown(remaining)
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    }

    /// Minutes while there is time, seconds when it is imminent. A menu bar is
    /// too narrow for "00:24:13".
    private static func compactCountdown(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "nyt" }
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60) + 1)m" }
        return String(format: "%.0fh", (seconds / 3600).rounded(.down))
    }

    // MARK: - Breaks

    private func startBreak(tier: Tier) {
        breaks.start(tier: tier)
        updateStatusTitle()
    }

    @objc private func startMicro() { scheduler.fireNow(tier: .micro) }
    @objc private func startLong() { scheduler.fireNow(tier: .long) }
    @objc private func snooze() { scheduler.snooze() }

    @objc private func togglePause() {
        if scheduler.isPaused { scheduler.resume() } else { scheduler.pause() }
        updateStatusTitle()
    }

    @objc private func showStats() {
        panels.show(
            id: "stats", title: "Nikamat – tilastot",
            size: CGSize(width: 460, height: 520), view: StatsView(log: log)
        )
    }

    @objc private func showSettings() {
        panels.show(
            id: "settings", title: "Nikamat – asetukset",
            size: CGSize(width: 480, height: 680),
            view: SettingsView(
                settings: settings,
                scheduler: scheduler,
                onRhythmChanged: { [weak self] in
                    self?.scheduler.reschedule()
                    self?.updateStatusTitle()
                },
                onStartBreak: { [weak self] tier in self?.scheduler.fireNow(tier: tier) }
            )
        )
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - Menu

extension AppDelegate: NSMenuDelegate {
    /// The menu is rebuilt every time it opens, because most of it is status:
    /// when the next break is, and why it has not opened yet.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status: String
        if scheduler.isPaused {
            status = "Muistutukset tauolla"
        } else if let reason = scheduler.deferralReason {
            status = "Tauko odottaa: \(reason)"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH.mm"
            let tier = scheduler.nextTier == .long ? "Pitkä tauko" : "Mikrotauko"
            status = "\(tier) klo \(formatter.string(from: scheduler.nextFire))"
        }
        let header = NSMenuItem(title: status, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        menu.addItem(.separator())
        menu.addItem(item("Aloita mikrotauko", #selector(startMicro)))
        menu.addItem(item("Aloita pitkä tauko", #selector(startLong)))
        menu.addItem(item("Lykkää \(settings.preferences.snoozeMinutes) min", #selector(snooze)))
        menu.addItem(item(
            scheduler.isPaused ? "Jatka muistutuksia" : "Tauota muistutukset",
            #selector(togglePause)
        ))

        menu.addItem(.separator())
        menu.addItem(item("Tilastot…", #selector(showStats)))
        menu.addItem(item("Asetukset…", #selector(showSettings)))

        menu.addItem(.separator())
        menu.addItem(item("Lopeta Nikamat", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
}
