import AppKit
import SwiftUI

struct CleanupView: View {
    @State private var selectedFolder: URL?
    @State private var scanResult: CleanupScanResult?
    @State private var selectedCandidateIDs = Set<String>()
    @State private var executionReport: CleanupExecutionReport?
    @State private var errorMessage: String?
    @State private var isScanning = false
    @State private var isCleaning = false
    @State private var showConfirmation = false

    private let policy = SafetyPolicy()
    private let rules = CleanupRules.standard
    private let scanner = CleanupCandidateScanner()

    private var selectedCandidates: [CleanupCandidate] {
        guard let scanResult else { return [] }
        return scanResult.candidates.filter { selectedCandidateIDs.contains($0.id) }
    }

    private var selectedBytes: Int64 {
        selectedCandidates.reduce(0) { $0 + $1.byteCount }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                safetyNotice
                folderPicker

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                if isScanning {
                    ProgressView("Scanning for eligible files…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if isCleaning {
                    ProgressView("Revalidating selected files and moving approved items to Trash…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let scanResult {
                    candidateResults(scanResult)
                }

                if let executionReport {
                    cleanupReport(executionReport)
                }
            }
            .padding(28)
        }
        .confirmationDialog(
            "Move \(selectedCandidates.count) selected files to Trash?",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move Selected Files to Trash", role: .destructive) {
                Task { await executeSelectedCleanup() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("MacPilot will recheck each file and move only the exact approved regular files to macOS Trash. Files changed since the scan will be skipped. No folders or system files will be deleted.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Smart Cleanup")
                .font(.largeTitle.bold())
            Text("Review old user cache and log files, then move selected items to macOS Trash.")
                .foregroundStyle(.secondary)
        }
    }

    private var safetyNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 5) {
                Text("Reversible cleanup · You stay in control")
                    .font(.headline)
                Text("Candidates must be regular files at least 30 days old and 1 KB or larger. MacPilot excludes databases, preference files, credentials, hidden items, hard links, symbolic links and selected browser or personal-communication caches. Review every item and close the related app before continuing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Moving an item to Trash is reversible in Finder in most cases, but restoration is not guaranteed. Keep a backup of important data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var folderPicker: some View {
        GroupBox("Choose a cleanup location") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Label("User Caches", systemImage: "shippingbox")
                    Text("~/Library/Caches")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…") { chooseFolder(startingAt: policy.cachesRoot) }
                        .buttonStyle(.bordered)
                }
                Divider()
                HStack(spacing: 10) {
                    Label("User Logs", systemImage: "doc.text")
                    Text("~/Library/Logs")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…") { chooseFolder(startingAt: policy.logsRoot) }
                        .buttonStyle(.bordered)
                }

                if let selectedFolder {
                    Divider()
                    Text(selectedFolder.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Button {
                        Task { await scanForCandidates() }
                    } label: {
                        if isScanning {
                            ProgressView().controlSize(.small)
                            Text("Scanning…")
                        } else {
                            Label("Find Cleanup Candidates", systemImage: "magnifyingglass")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isScanning || isCleaning)
                } else {
                    Text("Choose a folder inside your user Caches or Logs directory. Trash, Downloads, Documents, Applications and system locations are not cleanup sources.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func candidateResults(_ result: CleanupScanResult) -> some View {
        GroupBox("Cleanup review") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    metric("Eligible files", value: result.candidates.count.formatted())
                    Spacer()
                    metric("Eligible file size", value: result.formattedCandidateBytes)
                    Spacer()
                    metric("Skipped", value: result.skippedCount.formatted())
                }

                Text("Sizes are logical file sizes. Actual disk space recovered may differ because of filesystem compression, sparse allocation or other macOS storage behaviour.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if result.wasTruncated {
                    Label("The scan limit was reached. Results are incomplete; run a narrower scan before cleanup.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if result.candidates.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                        Text("No cleanup candidates found")
                            .font(.headline)
                        Text("No files met the current age, size and safety rules in this folder.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    HStack {
                        Text("Select individual files")
                            .font(.headline)
                        Spacer()
                        Button("Select up to 100") {
                            selectedCandidateIDs = Set(result.candidates.prefix(rules.maximumItemsPerBatch).map(\.id))
                        }
                        .buttonStyle(.borderless)
                        Button("Clear") { selectedCandidateIDs.removeAll() }
                            .buttonStyle(.borderless)
                    }

                    VStack(spacing: 0) {
                        ForEach(result.candidates) { candidate in
                            candidateRow(candidate)
                            if candidate.id != result.candidates.last?.id { Divider() }
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxHeight: 360)

                    Divider()
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(selectedCandidates.count) selected")
                                .font(.headline)
                            Text("Selected size: \(ByteCountFormatter.string(fromByteCount: selectedBytes, countStyle: .file))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            showConfirmation = true
                        } label: {
                            Label("Move to Trash", systemImage: "trash")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedCandidates.isEmpty || selectedCandidates.count > rules.maximumItemsPerBatch || isCleaning || isScanning || result.wasTruncated)
                    }
                    if selectedCandidates.count > rules.maximumItemsPerBatch {
                        Text("Select no more than \(rules.maximumItemsPerBatch) files per batch.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if result.wasTruncated {
                        Text("Cleanup is disabled for incomplete scans. Choose a narrower folder and scan again.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func candidateRow(_ candidate: CleanupCandidate) -> some View {
        Toggle(isOn: Binding(
            get: { selectedCandidateIDs.contains(candidate.id) },
            set: { isSelected in
                if isSelected { selectedCandidateIDs.insert(candidate.id) }
                else { selectedCandidateIDs.remove(candidate.id) }
            }
        )) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(candidate.relativePath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("Modified \(candidate.modifiedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                Text(candidate.formattedSize)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 7)
    }

    private func cleanupReport(_ report: CleanupExecutionReport) -> some View {
        GroupBox("Cleanup activity") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Moved to Trash", systemImage: "trash.fill")
                    Spacer()
                    Text("\(report.movedCount) files · \(report.formattedMovedBytes)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.green)
                }
                if report.skippedCount > 0 {
                    Label("\(report.skippedCount) skipped because they changed or failed a safety check.", systemImage: "arrow.uturn.backward.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if report.failedCount > 0 {
                    Label("\(report.failedCount) could not be moved. Review the item details below.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                ForEach(report.outcomes) { outcome in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: icon(for: outcome.status))
                            .foregroundStyle(color(for: outcome.status))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(outcome.name).font(.caption.weight(.medium))
                            Text(outcome.detail).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: outcome.byteCount, countStyle: .file))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if report.movedCount > 0 {
                    Button {
                        let trashURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
                        NSWorkspace.shared.open(trashURL)
                    } label: {
                        Label("Open Trash in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).monospacedDigit()
        }
    }

    private func icon(for status: CleanupItemStatus) -> String {
        switch status {
        case .moved: return "checkmark.circle.fill"
        case .skipped: return "arrow.uturn.backward.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }

    private func color(for status: CleanupItemStatus) -> Color {
        switch status {
        case .moved: return .green
        case .skipped: return .orange
        case .failed: return .red
        }
    }

    private func chooseFolder(startingAt directory: URL) {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder inside Caches or Logs"
        panel.prompt = "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard case .allowed = policy.validateCleanupRoot(url) else {
            errorMessage = "This folder is outside the approved user Caches or Logs locations. No cleanup scan was started."
            selectedFolder = nil
            scanResult = nil
            return
        }

        selectedFolder = url
        scanResult = nil
        executionReport = nil
        selectedCandidateIDs.removeAll()
        errorMessage = nil
    }

    @MainActor
    private func scanForCandidates() async {
        guard let selectedFolder else { return }
        isScanning = true
        errorMessage = nil
        executionReport = nil
        selectedCandidateIDs.removeAll()

        let result = await Task.detached(priority: .userInitiated) { () -> Result<CleanupScanResult, Error> in
            let didStartAccess = selectedFolder.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess { selectedFolder.stopAccessingSecurityScopedResource() }
            }
            do { return .success(try scanner.scan(selectedFolder)) }
            catch { return .failure(error) }
        }.value

        switch result {
        case .success(let report):
            scanResult = report
            AuditLogStore.shared.record("cleanup_candidate_scan_completed")
        case .failure(let error):
            errorMessage = error.localizedDescription
            scanResult = nil
            AuditLogStore.shared.record("cleanup_candidate_scan_failed")
        }
        isScanning = false
    }

    @MainActor
    private func executeSelectedCleanup() async {
        guard let selectedFolder else { return }
        let approvedCandidates = selectedCandidates
        guard !approvedCandidates.isEmpty else { return }

        isCleaning = true
        errorMessage = nil
        let executor = CleanupExecutor(safetyPolicy: policy, rules: rules)

        let result = await Task.detached(priority: .userInitiated) { () -> Result<CleanupExecutionReport, Error> in
            let didStartAccess = selectedFolder.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess { selectedFolder.stopAccessingSecurityScopedResource() }
            }
            do {
                return .success(try executor.execute(approvedCandidates, under: selectedFolder))
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let report):
            executionReport = report
            let movedIDs = Set(report.outcomes.filter { $0.status == .moved }.map(\.id))
            if let scanResult {
                self.scanResult = CleanupScanResult(
                    rootPath: scanResult.rootPath,
                    candidates: scanResult.candidates.filter { !movedIDs.contains($0.id) },
                    skippedCount: scanResult.skippedCount,
                    visitedCount: scanResult.visitedCount,
                    wasTruncated: scanResult.wasTruncated,
                    finishedAt: scanResult.finishedAt
                )
            }
            selectedCandidateIDs.subtract(movedIDs)
            selectedCandidateIDs.removeAll()
            if report.movedCount > 0 {
                AuditLogStore.shared.record("cleanup_moved_\(report.movedCount)_items")
            }
            if report.failedCount > 0 || report.skippedCount > 0 {
                AuditLogStore.shared.record("cleanup_batch_partial_or_skipped")
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
            AuditLogStore.shared.record("cleanup_batch_rejected")
        }
        isCleaning = false
    }
}
