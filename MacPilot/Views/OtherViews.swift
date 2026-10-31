import SwiftUI

struct AppManagerView: View {
    var body: some View {
        ApplicationManagerView()
    }
}

struct DebloatView: View {
    var body: some View {
        FeaturePlaceholderView(
            title: "Debloat Manager",
            subtitle: "Review login items and background services without disabling macOS protections.",
            symbol: "slider.horizontal.3",
            status: "Planned for Phase 5",
            details: [
                "Login item inventory using supported macOS APIs",
                "Third-party background item review",
                "No automatic changes to launchd configuration",
                "No disabling of Apple services or security controls"
            ]
        )
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
                    LabeledContent("Version", value: "0.4.0")
                    LabeledContent("Build", value: "Phase 4 · Application Manager")
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
