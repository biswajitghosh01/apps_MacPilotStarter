import AppKit
import SwiftUI

struct StorageView: View {
    @State private var snapshot = SystemInfoService().snapshot()
    @State private var selectedFolder: URL?
    @State private var scanResult: ScanResult?
    @State private var errorMessage: String?
    @State private var isScanning = false

    private let policy = SafetyPolicy()
    private let scanner = ReadOnlyScanner()

    private var usageFraction: Double {
        snapshot.diskUsageFraction ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Storage Analyzer")
                        .font(.largeTitle.bold())
                    Text("Understand disk usage and inspect approved user folders without changing files.")
                        .foregroundStyle(.secondary)
                }

                GroupBox("Home volume") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(SystemSnapshot.bytes(snapshot.usedDiskBytes))
                                    .font(.system(size: 30, weight: .bold, design: .rounded))
                                Text("Used storage")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(SystemSnapshot.bytes(snapshot.freeDiskBytes))
                                    .font(.title3.weight(.semibold))
                                Text("Available")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ProgressView(value: usageFraction)
                            .tint(usageFraction > 0.9 ? .orange : .blue)
                        HStack {
                            Text("Volume capacity: \(SystemSnapshot.bytes(snapshot.totalDiskBytes))")
                            Spacer()
                            Text("\(Int(usageFraction * 100))% used")
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                GroupBox("Inspect user storage") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Select one of the approved folders. MacPilot will report file counts, observed sizes, file types and the largest files. It will not infer that these files are safe to delete.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        storageRootRow(title: "Application caches", path: "~/Library/Caches", symbol: "shippingbox")
                        Divider()
                        storageRootRow(title: "Application logs", path: "~/Library/Logs", symbol: "doc.text")
                        Divider()
                        storageRootRow(title: "Trash", path: "~/.Trash", symbol: "trash")
                    }
                    .padding(.vertical, 6)
                }

                if let selectedFolder {
                    GroupBox("Selected location") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(selectedFolder.path)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            Button {
                                Task { await analyseSelectedFolder() }
                            } label: {
                                if isScanning {
                                    ProgressView().controlSize(.small)
                                    Text("Analysing…")
                                } else {
                                    Label("Analyse selected folder", systemImage: "magnifyingglass")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isScanning)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }

                if let scanResult {
                    ScanResultDetailsView(result: scanResult)
                }
            }
            .padding(28)
        }
        .onAppear { snapshot = SystemInfoService().snapshot() }
    }

    private func storageRootRow(title: String, path: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(path).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Choose…") { chooseFolder(startingAt: path) }
                .buttonStyle(.bordered)
        }
    }

    private func chooseFolder(startingAt relativePath: String) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let relative = String(relativePath.dropFirst(2))
        let directory = home.appendingPathComponent(relative, isDirectory: true)
        let panel = NSOpenPanel()
        panel.title = "Choose a folder under \(relativePath)"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard case .allowed = policy.validateReadOnlyScanRoot(url) else {
            errorMessage = "That folder is outside the approved scan roots. No scan was started."
            selectedFolder = nil
            scanResult = nil
            return
        }
        selectedFolder = url
        scanResult = nil
        errorMessage = nil
    }

    @MainActor
    private func analyseSelectedFolder() async {
        guard let selectedFolder else { return }
        isScanning = true
        errorMessage = nil
        scanResult = nil

        let result = await Task.detached(priority: .userInitiated) { () -> Result<ScanResult, Error> in
            let didStartAccess = selectedFolder.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess { selectedFolder.stopAccessingSecurityScopedResource() }
            }
            do {
                return .success(try scanner.scan(selectedFolder))
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let report):
            scanResult = report
            AuditLogStore.shared.record("storage_analysis_completed")
        case .failure(let error):
            errorMessage = error.localizedDescription
            AuditLogStore.shared.record("storage_analysis_failed")
        }
        isScanning = false
    }
}
