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
                    emptyState("No login agents found", detail: "No valid plist records were found in the selected folder.", symbol: "tray")
                } else {
                    emptyState("Review background items", detail: "Choose your user LaunchAgents folder to inspect login jobs.", symbol: "slider.horizontal.3")
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

    private func emptyState(_ title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
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


struct PerformanceView: View {
    @StateObject private var monitor = PerformanceMonitor()
    private var reading: PerformanceReading? { monitor.reading }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Performance").font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Live, read-only system health measurements. Refreshes every five seconds.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let reading {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        performanceCard(title: "1-minute system load", value: reading.oneMinuteLoadAverage.map { String(format: "%.2f", $0) } ?? "Unavailable", detail: "Runnable and uninterruptible tasks", symbol: "gauge.with.dots.needle.67percent", tint: .blue)
                        performanceCard(title: "Logical processors", value: "\(reading.logicalProcessorCount)", detail: "macOS-reported processing units", symbol: "cpu", tint: .purple)
                        performanceCard(title: "Memory in use", value: SystemSnapshot.bytes(reading.memoryUsedBytes), detail: "Estimated active, inactive, wired and compressed pages", symbol: "memorychip", tint: .orange)
                        performanceCard(title: "Memory available", value: SystemSnapshot.bytes(reading.memoryAvailableBytes), detail: "Free pages reported by the VM subsystem", symbol: "memorychip.fill", tint: .green)
                    }
                    GroupBox("System load history") {
                        VStack(alignment: .leading, spacing: 12) {
                            loadRow("1 minute", value: reading.oneMinuteLoadAverage)
                            loadRow("5 minutes", value: reading.fiveMinuteLoadAverage)
                            loadRow("15 minutes", value: reading.fifteenMinuteLoadAverage)
                            Divider()
                            Text("Load average is not a CPU percentage. Compare it with the \(reading.logicalProcessorCount) logical processors to understand relative system demand.")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "clock").foregroundStyle(.secondary)
                        Text("Last updated \(reading.sampledAt.formatted(date: .omitted, time: .standard))")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Refresh now") { monitor.refresh() }.buttonStyle(.bordered)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "waveform.path").font(.system(size: 30)).foregroundStyle(.secondary)
                        Text("Telemetry unavailable").font(.headline)
                        Text("macOS did not return a valid performance sample. Try refreshing.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Retry") { monitor.refresh() }
                    }.frame(maxWidth: .infinity).padding(28)
                }
                GroupBox("Measurement notes") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Read-only system APIs", systemImage: "checkmark.shield")
                        Text("MacPilot does not change process priority, terminate processes, alter system settings or run privileged commands.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Memory figures are an estimate based on VM page counters. They may not match Activity Monitor's memory-pressure presentation exactly.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                }
            }.padding(26)
        }
    }

    private func performanceCard(title: String, value: String, detail: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: symbol).font(.subheadline.weight(.medium)).foregroundStyle(tint)
            Text(value).font(.system(size: 25, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }

    private func loadRow(_ title: String, value: Double?) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value.map { String(format: "%.2f", $0) } ?? "Unavailable").monospacedDigit().fontWeight(.semibold)
        }.font(.subheadline)
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
                        safetyRow("Separate scan and cleanup roots", detail: "Storage analysis is read-only and limited to user Caches and Logs. Trash is excluded from scanning. Smart Cleanup can move only individually selected, revalidated files from Caches or Logs to Trash.")
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
                    LabeledContent("Version", value: "0.6.0")
                    LabeledContent("Build", value: "0.6.0 development · build 6")
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
