import SwiftUI

struct ImportProgressSheet: View {
    let urls: [URL]
    /// URLs the picker returned whose security-scoped access could not be started.
    /// These never reach `ImportService`, but must still be reported as failures
    /// rather than silently dropped from the summary.
    let inaccessibleFailures: [(url: URL, error: ImportError)]
    let importer: ImportService

    @Environment(\.dismiss) private var dismiss
    @State private var summary: ImportSummary?

    var body: some View {
        Group {
            if importer.isImporting || summary == nil {
                VStack(spacing: 20) {
                    ProgressView(
                        value: Double(importer.progress.completed),
                        total: Double(max(importer.progress.total, 1))
                    )
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 32)
                    Text("Importing \(importer.progress.completed) of \(importer.progress.total)")
                        .font(.body)
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let summary {
                // Scrolls because the failure-reason list has no fixed height:
                // `.fileNotAccessible` embeds the filename, so those reasons
                // never dedupe and several long ones can exceed the detent.
                ScrollView {
                    VStack(spacing: 20) {
                        Image(systemName: summary.failures.isEmpty
                              ? "checkmark.circle.fill"
                              : "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(summary.failures.isEmpty ? .green : .orange)
                        Text("Import complete")
                            .font(.title2.bold())
                        VStack(spacing: 4) {
                            summaryLine(count: summary.imported.count, text: "imported")
                            if summary.duplicates.count > 0 {
                                summaryLine(count: summary.duplicates.count, text: "duplicate(s) skipped")
                            }
                            if summary.failures.count > 0 {
                                summaryLine(count: summary.failures.count, text: "failed")
                            }
                        }
                        if !failureReasons(for: summary).isEmpty {
                            failureReasonsList(for: summary)
                        }
                        Button("Done") { dismiss() }
                            .buttonStyle(.borderedProminent)
                            .padding(.top, 8)
                    }
                    .padding(40)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .interactiveDismissDisabled(importer.isImporting)
        // Hidden while importing: dismissal is disabled then, and a grabber
        // the user cannot act on is a false affordance.
        .presentationDragIndicator(importer.isImporting ? .hidden : .visible)
        .task {
            let result = await importer.importFiles(at: urls)
            summary = ImportSummary(
                imported: result.imported,
                failures: result.failures + inaccessibleFailures,
                duplicates: result.duplicates
            )
        }
    }

    private func summaryLine(count: Int, text: String) -> some View {
        Text("\(count) \(text)")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    /// The distinct reasons behind `summary.failures`, deduplicated so ten
    /// files that all failed the same way produce one line, not ten.
    /// Preserves first-seen order so the list is stable rather than
    /// reshuffling between renders.
    private func failureReasons(for summary: ImportSummary) -> [String] {
        var seen = Set<String>()
        var reasons: [String] = []
        for failure in summary.failures {
            guard let description = failure.error.errorDescription else { continue }
            if seen.insert(description).inserted {
                reasons.append(description)
            }
        }
        return reasons
    }

    /// Caps the visible list at 4 distinct reasons, folding the rest into a
    /// "+N more" line to keep the common case tidy. The sheet also scrolls
    /// and can be dragged to `.large`, so the cap is about readability now
    /// rather than about fitting a fixed height.
    private func failureReasonsList(for summary: ImportSummary) -> some View {
        let reasons = failureReasons(for: summary)
        let maxShown = 4
        let shown = reasons.prefix(maxShown)
        let remaining = reasons.count - shown.count
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(shown), id: \.self) { reason in
                Text("• \(reason)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            if remaining > 0 {
                Text("+\(remaining) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
        .padding(.top, 4)
    }
}
