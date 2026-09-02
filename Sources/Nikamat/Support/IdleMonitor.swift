import CoreGraphics

/// How long the Mac has been without keyboard, mouse or trackpad input.
///
/// Used to skip breaks you were never there to take. Without this, coming back
/// from lunch means walking into a stack of missed reminders, and a reminder
/// you have learned to dismiss is worse than no reminder.
enum IdleMonitor {
    /// Any HID input event: `~0` is Core Graphics' "any event type" wildcard.
    private static let anyInput = CGEventType(rawValue: ~0)!

    static var secondsSinceInput: Double {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
    }
}
