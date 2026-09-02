import AppKit
import SwiftUI

/// What has actually happened, read back out of the log.
struct StatsView: View {
    @State private var summary = BreakLog.shared.summary()

    private let accent = Color(red: 0.89, green: 0.42, blue: 0.22)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headline
                chart
                if let skipped = summary.mostSkipped {
                    detail(
                        title: "Useimmin kesken jäävä liike",
                        value: skipped.name,
                        caption: "\(skipped.percent) % tehty loppuun"
                    )
                }
                databaseNote
            }
            .padding(24)
        }
        .frame(minWidth: 420, minHeight: 460)
        // Recomputed on appearance rather than continuously: nothing here
        // changes while you are looking at it except by taking a break.
        .onAppear { summary = BreakLog.shared.summary() }
    }

    private var headline: some View {
        HStack(spacing: 28) {
            metric("Tänään", "\(summary.todayDone) / \(summary.todayOffered)",
                   caption: String(format: "%.0f min liikettä", summary.todayMinutes))
            metric("7 päivää", "\(summary.weekDone) / \(summary.weekOffered)",
                   caption: summary.weekOffered > 0
                       ? "\(Int(100.0 * Double(summary.weekDone) / Double(summary.weekOffered))) %"
                       : "–")
            metric("Putki", "\(summary.streak)",
                   caption: summary.streak == 1 ? "päivä" : "päivää")
        }
    }

    private func metric(_ title: String, _ value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                .foregroundStyle(.secondary)
            Text(value).font(.system(size: 24, weight: .medium).monospacedDigit())
            Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    /// Two weeks of days. Each bar is breaks offered, the filled part breaks
    /// taken, so a day you were away reads differently from a day you ignored.
    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Kaksi viikkoa")
                .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                .foregroundStyle(.secondary)
            let peak = max(summary.recent.map(\.offered).max() ?? 1, 1)
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(summary.recent, id: \.day) { entry in
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 80 * Double(entry.offered) / Double(peak))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(accent)
                                .frame(height: 80 * Double(entry.done) / Double(peak))
                        }
                        .frame(width: 16)
                        Text(String(entry.day.suffix(2)))
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if summary.recent.isEmpty {
                    Text("Ei vielä kirjattuja taukoja.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(height: 100, alignment: .bottom)
        }
    }

    private func detail(title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                .foregroundStyle(.secondary)
            Text(value).font(.system(size: 14, weight: .medium))
            Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    /// The log is a plain SQLite file on purpose; this says where it is and how
    /// to read it from somewhere else.
    private var databaseNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("Kirjanpito")
                .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                .foregroundStyle(.secondary)
            Text(BreakLog.shared.path)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Näkymät v_days ja v_exercises sisältävät päivä- ja liikekohtaiset koosteet.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack {
                Button("Näytä Finderissa") {
                    NSWorkspace.shared.selectFile(
                        BreakLog.shared.path, inFileViewerRootedAtPath: ""
                    )
                }
                Button("Kopioi org-lohko") {
                    let snippet = """
                        #+begin_src sqlite :db \(BreakLog.shared.path)
                        select * from v_days limit 14;
                        #+end_src
                        """
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snippet, forType: .string)
                }
            }
            .controlSize(.small)
        }
    }
}
