import SwiftUI

/// The break window's contents: one exercise at a time, animated, timed.
///
/// The running break is wrapped in a `TimelineView(.animation)`, so it redraws
/// at the display's refresh rate and reads the session's state as a function of
/// the current instant. Nothing here holds animation state of its own, which is
/// why pausing is a single boolean and skipping a step needs no cleanup. The
/// closing screen is static and stays outside the timeline.
struct BreakView: View {
    @ObservedObject var session: BreakSession
    let onSnooze: () -> Void
    let onClose: () -> Void

    private let accent = Color(red: 0.89, green: 0.42, blue: 0.22)

    var body: some View {
        Group {
            if let outcome = session.finished {
                FinishedView(outcome: outcome)
            } else {
                TimelineView(.animation) { context in
                    running(now: context.date)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 580)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Running

    @ViewBuilder
    private func running(now: Date) -> some View {
        if let step = session.currentStep, let frame = session.frame(at: now) {
            VStack(spacing: 0) {
                header(now: now)
                progressBar(now: now)

                FigureView(
                    pose: frame.pose,
                    orientation: step.exercise.orientation,
                    highlight: step.exercise.highlight,
                    prop: step.exercise.prop
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 4)

                instructions(step: step)
                counter(step: step, frame: frame, now: now)
                controls()
            }
        }
    }

    private func header(now: Date) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(session.plan.tier.title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(accent)
            Spacer()
            Text("\(clock(session.remainingTotal(at: now))) jäljellä")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    /// Progress through the whole break, plus a marker per step so it is clear
    /// how many exercises are still coming.
    private func progressBar(now: Date) -> some View {
        let total = max(session.plan.duration, 1)
        let done = total - session.remainingTotal(at: now)
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(accent)
                    .frame(width: geometry.size.width * min(1, max(0, done / total)))
                HStack(spacing: 0) {
                    ForEach(Array(session.plan.steps.enumerated()), id: \.element.id) { index, step in
                        Rectangle()
                            .fill(Color(nsColor: .windowBackgroundColor))
                            .frame(width: index == 0 ? 0 : 1.5)
                        Spacer()
                            .frame(width: geometry.size.width * step.duration / total - (index == 0 ? 0 : 1.5))
                    }
                }
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 22)
    }

    private func instructions(step: BreakStep) -> some View {
        VStack(spacing: 6) {
            Text(step.exercise.name)
                .font(.system(size: 21, weight: .semibold))
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                Text(step.exercise.region.label)
                Text("·")
                Text(step.exercise.posture.label)
                if let side = step.sideLabel {
                    Text("·")
                    Text(side).foregroundStyle(accent)
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            Text(step.exercise.cue)
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .padding(.top, 2)

            if let note = step.exercise.note {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 28)
        .frame(height: 132, alignment: .top)
    }

    /// The countdown ring. The ring drains over the current step and the label
    /// inside it names the phase, so "hold" and "release" are legible without
    /// having to count seconds yourself.
    private func counter(step: BreakStep, frame: MovementFrame, now: Date) -> some View {
        let remaining = session.remainingInStep(at: now)
        let fraction = 1 - min(1, max(0, remaining / max(step.duration, 0.01)))
        return HStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.10), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(remaining.rounded(.up)))")
                        .font(.system(size: 22, weight: .medium).monospacedDigit())
                    Text(session.isPaused ? "tauolla" : frame.phase)
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 4) {
                if let repetition = frame.repetition, let count = frame.repetitionCount {
                    Text("toisto \(repetition) / \(count)")
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                }
                Text("liike \(session.stepIndex + 1) / \(session.plan.steps.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private func controls() -> some View {
        HStack(spacing: 10) {
            Button(session.isPaused ? "Jatka" : "Tauota") { session.togglePause() }
                .keyboardShortcut(.space, modifiers: [])
            Spacer()
            Button("Lykkää") { onSnooze() }
            Button("Ohita liike") { session.skipStep() }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("Sulje") { onClose() }
                .keyboardShortcut(.cancelAction)
        }
        .controlSize(.regular)
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// The closing screen. Short and factual: what you did, and how the week looks.
private struct FinishedView: View {
    let outcome: BreakOutcome

    // Loaded once on appearance. A property initialiser would query the
    // database every time SwiftUI recreates this struct.
    @State private var summary = BreakLog.Summary()

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: outcome == .completed ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(outcome == .completed ? Color(red: 0.30, green: 0.62, blue: 0.36) : .secondary)
            Text(outcome == .completed ? "Tauko tehty" : "Tauko \(outcome.label)")
                .font(.system(size: 20, weight: .semibold))
            Text("Tänään \(summary.todayDone) / \(summary.todayOffered) taukoa")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if summary.streak > 1 {
                Text("\(summary.streak) päivää putkeen")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { summary = BreakLog.shared.summary() }
    }
}
