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
        VStack(spacing: 20) {
            if importer.isImporting || summary == nil {
                ProgressView(
                    value: Double(importer.progress.completed),
                    total: Double(max(importer.progress.total, 1))
                )
                .progressViewStyle(.linear)
                .padding(.horizontal, 32)
                Text("Importing \(importer.progress.completed) of \(importer.progress.total)")
                    .font(.body)
            } else if let summary {
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
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .interactiveDismissDisabled(importer.isImporting)
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
}
