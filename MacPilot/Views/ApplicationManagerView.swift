import AppKit
import SwiftUI

struct ApplicationManagerView: View {
    @State private var selectedRoot: URL?
    @State private var inventory: ApplicationInventoryResult?
    @State private var selectedApplicationID: String?
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var isScanning = false
    @State private var isUninstalling = false
    @State private var showUninstallConfirmation = false

    private let policy = ApplicationSafetyPolicy()
    private let scanner = ApplicationInventoryScanner()

    private var selectedApplication: InstalledApplication? {
        inventory?.applications.first { $0.id == selectedApplicationID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            safetyNotice

            HStack(spacing: 10) {
                Button {
                    chooseApplicationsFolder()
                } label: {
                    Label("Choose Applications Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isScanning || isUninstalling)

                if let selectedRoot {
                    Button {
                        Task { await scan(selectedRoot) }
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isScanning || isUninstalling)
                }

                Spacer()
                if let inventory {
                    Text("\(inventory.applications.count) applications")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let selectedRoot {
                Label(selectedRoot.path, systemImage: "folder")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            if let statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }

            if isScanning {
                ProgressView("Inspecting application bundles…")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let inventory {
                inventoryContent(inventory)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 42))
                        .foregroundStyle(.secondary)
                    Text("No Applications Folder Selected")
                        .font(.title3.weight(.semibold))
                    Text("Choose /Applications or your home folder's Applications directory. MacPilot will only inspect direct .app children of that folder.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 460)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(26)
        .onDisappear {
            releaseSelectedApplicationsFolder()
        }
        .confirmationDialog(
            "Move \(selectedApplication?.displayName ?? "this application") to Trash?",
            isPresented: $showUninstallConfirmation,
            titleVisibility: .visible
        ) {
            Button("Move Application to Trash", role: .destructive) {
                Task { await uninstallSelectedApplication() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Only the selected .app bundle will be moved to macOS Trash. Application Support files, preferences, login items, containers, keychain data and user documents will not be touched. Close the application first. If the developer provides its own uninstaller, use that instead to remove related helpers and services.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("App Manager")
                .font(.largeTitle.bold())
            Text("Inspect installed applications and review a single-app removal before it is moved to Trash.")
                .foregroundStyle(.secondary)
        }
    }

    private var safetyNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.title2)
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("Protected application management")
                    .font(.headline)
                Text("MacPilot does not scan /System/Applications, nested application folders or arbitrary directories. Apple bundle IDs are protected. No administrator prompt or permanent deletion is used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func inventoryContent(_ result: ApplicationInventoryResult) -> some View {
        if result.wasTruncated {
            Label("The inventory reached its application limit. Removal is disabled until you choose a narrower folder.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        if result.skippedCount > 0 {
            Text("\(result.skippedCount) item(s) could not be inspected and were skipped.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        HStack(spacing: 14) {
            List(selection: $selectedApplicationID) {
                ForEach(result.applications) { application in
                    ApplicationInventoryRow(application: application)
                        .tag(application.id as String?)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedApplicationID = application.id }
                }
            }
            .listStyle(.inset)
            .frame(minWidth: 340, idealWidth: 430, maxWidth: 520)

            if let selectedApplication {
                applicationDetails(selectedApplication, inventoryIsTruncated: result.wasTruncated)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "cursorarrow.click")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("Select an Application")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func applicationDetails(_ application: InstalledApplication, inventoryIsTruncated: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: application.path))
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(application.displayName).font(.title2.bold())
                        Text(application.version == "Unknown" ? "Version unavailable" : "Version \(application.version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Application details") {
                    VStack(alignment: .leading, spacing: 9) {
                        detailRow("Bundle ID", application.bundleIdentifier ?? "Unavailable")
                        detailRow("Bundle size", application.formattedSize)
                        detailRow("Inspected entries", "\(application.estimatedEntries)")
                        detailRow("Location", application.url.deletingLastPathComponent().path)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }

                if application.sizeIsLowerBound {
                    Label("Bundle size is a lower-bound estimate because the inspection limit was reached or some entries were inaccessible.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GroupBox("What uninstall does") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Moves only this .app bundle to macOS Trash", systemImage: "checkmark.circle")
                        Label("Does not remove preferences or Application Support data", systemImage: "lock")
                        Label("Does not remove login items, services or helper tools", systemImage: "lock")
                        Label("Does not remove containers, keychain records or documents", systemImage: "lock")
                        Label("Use the vendor uninstaller when one is provided", systemImage: "info.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                }

                #if APP_STORE_EDITION
                Label("App Store edition: use Finder to uninstall applications. MacPilot's App Store build provides inventory only.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #else
                if let reason = application.removalBlockReason {
                    Label(reason, systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Button(role: .destructive) {
                    showUninstallConfirmation = true
                } label: {
                    Label("Move Application to Trash", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!application.canMoveToTrash || inventoryIsTruncated || isUninstalling)
                #endif

                if isUninstalling {
                    ProgressView("Moving application to Trash…")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline).textSelection(.enabled)
                .lineLimit(2)
        }
    }

    private func chooseApplicationsFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose an Applications Folder"
        panel.message = "Choose exactly /Applications or your home folder's Applications directory. Other locations are blocked."
        panel.prompt = "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        // NSOpenPanel returns a security-scoped URL in a sandboxed application.
        // Start access while validating the selected root; the scan and move operations
        // independently acquire/release access around their work on the background queue.
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
        }
        switch policy.validateSelectedRoot(url) {
        case .allowed:
            releaseSelectedApplicationsFolder()
            selectedRoot = url
            inventory = nil
            selectedApplicationID = nil
            errorMessage = nil
            statusMessage = nil
            Task { await scan(url) }
        case .blocked(let reason):
            errorMessage = reason
            statusMessage = nil
        }
    }

    private func releaseSelectedApplicationsFolder() {
        // Access scopes are acquired and released by each background scan/move operation.
        // No security-scoped bookmark or long-lived access is retained by this screen.
        selectedRoot = nil
        inventory = nil
        selectedApplicationID = nil
    }

    @MainActor
    private func scan(_ root: URL) async {
        isScanning = true
        errorMessage = nil
        statusMessage = nil
        defer { isScanning = false }

        do {
            let service = scanner
            let result = try await Task.detached(priority: .utility) {
                let didStartAccess = root.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccess { root.stopAccessingSecurityScopedResource() }
                }
                return try service.scan(root)
            }.value
            inventory = result
            selectedApplicationID = result.applications.first?.id
            AuditLogStore.shared.record("application_inventory_completed_\(result.applications.count)")
        } catch {
            errorMessage = error.localizedDescription
            inventory = nil
        }
    }

    @MainActor
    private func uninstallSelectedApplication() async {
        guard let root = selectedRoot, let application = selectedApplication else {
            errorMessage = ApplicationManagerError.noSelection.localizedDescription
            return
        }

        #if APP_STORE_EDITION
        errorMessage = "Application removal is not available in the App Store edition. Use Finder."
        return
        #else
        isUninstalling = true
        errorMessage = nil
        statusMessage = nil
        defer { isUninstalling = false }

        do {
            let operation = ApplicationUninstaller()
            try await Task.detached(priority: .userInitiated) {
                let didStartAccess = root.startAccessingSecurityScopedResource()
                defer {
                    if didStartAccess { root.stopAccessingSecurityScopedResource() }
                }
                try operation.moveToTrash(application, under: root)
            }.value
            AuditLogStore.shared.record("application_bundle_moved_to_trash")
            await scan(root)
            statusMessage = "\(application.displayName) was moved to macOS Trash. Associated data was not changed."
        } catch {
            errorMessage = error.localizedDescription
            AuditLogStore.shared.record("application_uninstall_failed")
        }
        #endif
    }
}

private struct ApplicationInventoryRow: View {
    let application: InstalledApplication

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: application.path))
                .resizable()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(application.displayName)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(application.bundleIdentifier ?? "Bundle identifier unavailable")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(application.formattedSize)
                    #if APP_STORE_EDITION
                    Text("• Inventory only")
                        .foregroundStyle(.secondary)
                    #else
                    if !application.canMoveToTrash {
                        Text("• Protected / inventory only")
                            .foregroundStyle(.orange)
                    } else {
                        Text("• Eligible for review")
                            .foregroundStyle(.green)
                    }
                    #endif
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}
