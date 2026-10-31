import SwiftUI

struct ScanResultDetailsView: View {
    let result: ScanResult

    private var largestFileBytes: Int64 {
        max(1, result.largestFiles.first?.byteCount ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Scan summary") {
                VStack(spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        summaryMetric("Observed size", value: result.formattedSize, symbol: "externaldrive")
                        Spacer()
                        summaryMetric("Files", value: result.fileCount.formatted(), symbol: "doc")
                        Spacer()
                        summaryMetric("Folders", value: result.directoryCount.formatted(), symbol: "folder")
                    }
                    Divider()
                    HStack {
                        Label("Skipped / unreadable", systemImage: "eye.slash")
                        Spacer()
                        Text(result.skippedCount.formatted())
                            .monospacedDigit()
                    }
                    .font(.caption)
                    if result.wasTruncated {
                        Label("Scan limit reached. Results may be incomplete.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("Observed size is not guaranteed reclaimable space. MacPilot has not changed any files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 6)
            }

            GroupBox("File type breakdown") {
                if result.extensionSummaries.isEmpty {
                    Text("No regular files were found in this location.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 12) {
                        ForEach(result.extensionSummaries) { summary in
                            VStack(spacing: 5) {
                                HStack {
                                    Text(summary.fileType)
                                        .font(.system(.subheadline, design: .monospaced).weight(.medium))
                                    Spacer()
                                    Text("\(summary.fileCount) files · \(summary.formattedSize)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ProgressView(value: Double(summary.byteCount), total: Double(max(1, result.totalBytes)))
                                    .tint(.blue)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            GroupBox("Largest files observed") {
                if result.largestFiles.isEmpty {
                    Text("No files to display.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(0..<result.largestFiles.count, id: \.self) { index in
                            let file = result.largestFiles[index]
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20, alignment: .leading)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(file.name)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    Text(file.relativePath)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .textSelection(.enabled)
                                }
                                Spacer(minLength: 8)
                                Text(file.formattedSize)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                            if index != result.largestFiles.count - 1 { Divider() }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func summaryMetric(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
        }
    }
}
