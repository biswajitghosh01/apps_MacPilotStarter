import SwiftUI

struct AppManagerView: View {
    var body: some View {
        ApplicationManagerView()
    }
}

import SwiftUI
import AppKit

struct DebloatView: View {
    @State private var records: [LaunchAgentRecord] = []
    @State private var selectedFolder: URL?
    @State private var skippedCount = 0
    @State private var truncated = false
    @State private var errorMessage: String?
    @State private var isScanning = false

    private let inventory = LaunchAgentInventory()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Debloat Manager").font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Review your user login agents. MacPilot does not disable or remove services.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Read-only inventory", systemImage: "lock.shield.fill").font(.headline).foregroundStyle(.green)
                        Text("Only plist files directly inside ~/Library/LaunchAgents are inspected. System LaunchDaemons, global LaunchAgents and Apple services are outside this scan.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Choose LaunchAgents Folder") { chooseFolder() }.buttonStyle(.borderedProminent)
                            Button("Scan again") { scanSelectedFolder() }.buttonStyle(.bordered)
                                .disabled(selectedFolder == nil || isScanning)
                        }
                        if let selectedFolder {
                            Text(selectedFolder.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                }
                if !records.isEmpty {
                    HStack(spacing: 12) {
                        summaryMetric("Found", value: "\(records.count)")
                        summaryMetric("Skipped", value: "\(skippedCount)")
                        summaryMetric("Scan limit", value: truncated ? "Reached" : "Not reached")
                    }
                    ForEach(records) { record in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(record.label).font(.headline)
                                    Spacer()
                                    Text(record.fileName).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                                Text(record.program).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                                HStack(spacing: 14) {
                                    Label(record.runsAtLoad ? "Run at login" : "Not marked RunAtLoad", systemImage: "arrow.clockwise")
                                    Label(record.keepsAlive ? "KeepAlive enabled" : "No KeepAlive flag", systemImage: "repeat")
                                }.font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                        }
                    }
                } else if selectedFolder != nil && !isScanning && errorMessage == nil {
                    ContentUnavailableView("No login agents found", systemImage: "tray", description: Text("No valid plist records were found in the selected folder."))
                } else {
                    ContentUnavailableView("Review background items", systemImage: "slider.horizontal.3", description: Text("Choose your user LaunchAgents folder to inspect login jobs."))
                }
                GroupBox("What this screen does not do") {
                    VStack(alignment: .leading, spacing: 8) {
                        safetyNote("Does not unload or disable launch agents")
                        safetyNote("Does not edit plist files or change login settings")
                        safetyNote("Does not inspect system LaunchDaemons or other users")
                        safetyNote("Does not claim every listed job is unnecessary or safe to remove")
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                }
            }.padding(26)
        }
        .overlay { if isScanning { ProgressView("Scanning…").padding(18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose your user LaunchAgents folder"
        panel.message = "MacPilot will only read plist metadata in ~/Library/LaunchAgents."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.directoryURL = inventory.permittedRoot
        panel.prompt = "Choose Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedFolder = url
        scanSelectedFolder()
    }

    private func scanSelectedFolder() {
        guard let selectedFolder else { return }
        isScanning = true
        errorMessage = nil
        let hasAccess = selectedFolder.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { selectedFolder.stopAccessingSecurityScopedResource() }
            isScanning = false
        }
        do {
            let result = try inventory.scan(selectedFolder)
            records = result.records
            skippedCount = result.skippedCount
            truncated = result.truncated
        } catch LaunchAgentInventoryError.unapprovedRoot {
            records = []
            errorMessage = "For safety, only ~/Library/LaunchAgents can be scanned."
        } catch {
            records = []
            errorMessage = "The selected folder could not be read. Check macOS privacy permissions and try again."
        }
    }

    private func summaryMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func safetyNote(_ value: String) -> some View {
        Label(value, systemImage: "checkmark.shield").font(.caption).foregroundStyle(.secondary)
    }
}


struct FeaturePlaceholderView: View {
    let title: String
    let subtitle: String
    let symbol: String
    let status: String
    let details: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.largeTitle.bold())
                Text(subtitle).foregroundStyle(.secondary)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Label(status, systemImage: "hammer.fill")
                        .font(.headline)
                        .foregroundStyle(.tint)
                    ForEach(details, id: \.self) { detail in
                        Label(detail, systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SafetyCenterView: View {
    private let policy = SafetyPolicy()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Safety Center").font(.largeTitle.bold())
                    Text("MacPilot uses a restrictive, fail-closed scanning policy.")
                        .foregroundStyle(.secondary)
                }

                GroupBox("Protected locations") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(policy.protectedPathsForDisplay, id: \.self) { path in
                            Label(path, systemImage: "lock.fill")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }

                GroupBox("Current safeguards") {
                    VStack(alignment: .leading, spacing: 10) {
                        safetyRow("Metadata-only candidate scan", detail: "Candidate discovery reads filesystem metadata only and never opens file contents.")
                        safetyRow("Separate scan and cleanup roots", detail: "Analysis can inspect user Caches, Logs or Trash. Cleanup is limited to user Caches and Logs; Trash is never a cleanup source.")
                        safetyRow("Symlink rejection", detail: "Symbolic-link scan roots are blocked and symbolic-link entries are skipped.")
                        safetyRow("No privilege escalation", detail: "The app does not invoke sudo or request administrator credentials.")
                        safetyRow("Bounded cleanup", detail: "Cleanup scans are limited to 20,000 entries and 250 candidates. Each confirmation batch is limited to 100 individual files.")
                        safetyRow("Constrained application removal", detail: "The direct edition can move one selected third-party .app bundle from /Applications or ~/Applications to Trash. App support data, preferences, helpers and documents are not removed. The App Store edition is inventory-only.")
                        safetyRow("Revalidation and audit", detail: "File identity, modification time, type and path are checked again before each coordinated move. Audit events store counts and event names, not file paths.")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                }

                Text("Cleanup is limited to old regular files selected individually by the user. Items are moved to macOS Trash through FileManager; no folder or permanent-delete operation is provided. These safeguards reduce risk but cannot guarantee that every file is safe to remove. Keep backups and close the affected app before cleanup.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
        }
    }

    private func safetyRow(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: "checkmark.shield")
                .font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
                .padding(.leading, 26)
        }
    }
}

struct SettingsView: View {
    @AppStorage("acceptedDisclaimerVersion") private var acceptedDisclaimerVersion = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings").font(.largeTitle.bold())
                Text("Local application preferences.").foregroundStyle(.secondary)
            }
            GroupBox("Agreement") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Accepted version", value: acceptedDisclaimerVersion.isEmpty ? "Not accepted" : acceptedDisclaimerVersion)
                    #if !APP_STORE_EDITION
                    Button("Review disclaimer on next launch", role: .destructive) {
                        acceptedDisclaimerVersion = ""
                        AuditLogStore.shared.record("disclaimer_reset_from_settings")
                    }
                    #else
                    Text("Safety guidance is available in Safety Center.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    #endif
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }
            GroupBox("About") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Application", value: "MacPilot")
                    LabeledContent("Version", value: "0.5.0")
                    LabeledContent("Build", value: "Phase 5 · Performance telemetry")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            }
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
