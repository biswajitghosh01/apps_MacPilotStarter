import SwiftUI

struct DashboardView: View {
    var onOpenStorage: () -> Void = {}
    var onOpenCleanup: () -> Void = {}
    var onOpenApplications: () -> Void = {}

    @State private var snapshot = SystemInfoService().snapshot()

    private var storageFraction: Double { snapshot.diskUsageFraction ?? 0 }
    private var storageUsed: String { SystemSnapshot.bytes(snapshot.usedDiskBytes) }
    private var storageTotal: String { SystemSnapshot.bytes(snapshot.totalDiskBytes) }
    private var storageFree: String { SystemSnapshot.bytes(snapshot.freeDiskBytes) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Your Mac at a glance")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("A clear overview of storage, hardware and maintenance tools.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label(snapshot.operatingSystem, systemImage: "laptopcomputer")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(.quaternary.opacity(0.55), in: Capsule())
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 13), GridItem(.flexible(), spacing: 13)], spacing: 13) {
                    DashboardMetricCard(
                        title: "Processor",
                        value: "\(snapshot.processorCount) cores",
                        detail: "Logical processors reported by macOS",
                        symbol: "cpu.fill",
                        tint: .blue
                    )
                    DashboardMetricCard(
                        title: "Installed Memory",
                        value: SystemSnapshot.bytes(snapshot.physicalMemoryBytes),
                        detail: "Physical RAM in this Mac",
                        symbol: "memorychip.fill",
                        tint: .purple
                    )
                    DashboardMetricCard(
                        title: "Storage Used",
                        value: storageUsed,
                        detail: "Of \(storageTotal) total capacity",
                        symbol: "internaldrive.fill",
                        tint: .green,
                        progress: snapshot.diskUsageFraction
                    )
                    DashboardMetricCard(
                        title: "Available Storage",
                        value: storageFree,
                        detail: "Reported free space on the home volume",
                        symbol: "externaldrive.fill",
                        tint: .orange
                    )
                }

                VStack(alignment: .leading, spacing: 13) {
                    Text("Quick Actions")
                        .font(.headline)
                    HStack(spacing: 12) {
                        QuickActionCard(
                            title: "Analyse Storage",
                            subtitle: "Understand what's using space",
                            symbol: "externaldrive.fill",
                            tint: .blue,
                            action: onOpenStorage
                        )
                        QuickActionCard(
                            title: "Scan for Cleanup",
                            subtitle: "Review eligible cache and log files",
                            symbol: "sparkles",
                            tint: .purple,
                            action: onOpenCleanup
                        )
                        QuickActionCard(
                            title: "Manage Applications",
                            subtitle: "Inspect installed applications",
                            symbol: "app.dashed",
                            tint: .orange,
                            action: onOpenApplications
                        )
                    }
                }

                HStack(alignment: .top, spacing: 14) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Storage Overview", systemImage: "chart.pie.fill")
                                .font(.headline)
                            HStack(alignment: .center, spacing: 18) {
                                ZStack {
                                    Circle().stroke(Color.primary.opacity(0.08), lineWidth: 13)
                                    Circle()
                                        .trim(from: 0, to: storageFraction)
                                        .stroke(Color.accentColor.gradient, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                                        .rotationEffect(.degrees(-90))
                                    VStack(spacing: 2) {
                                        Text(snapshot.diskUsageFraction.map { "\(Int($0 * 100))%" } ?? "—")
                                            .font(.title2.bold())
                                        Text("used")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 104, height: 104)
                                VStack(alignment: .leading, spacing: 9) {
                                    storageLegend("Used", value: storageUsed, color: .blue)
                                    storageLegend("Available", value: storageFree, color: .green)
                                    storageLegend("Capacity", value: storageTotal, color: .secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Button("View Storage Details", action: onOpenStorage)
                                .buttonStyle(.link)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(7)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Safety Status", systemImage: "checkmark.shield.fill")
                                .font(.headline)
                            Label("Protected mode active", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                            Text("MacPilot uses approved user locations, previews changes and asks for confirmation before moving selected files to Trash.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
                        .padding(7)
                    }
                }

                HStack(spacing: 9) {
                    Image(systemName: "info.circle.fill").foregroundStyle(.blue)
                    Text("CPU utilisation and live memory pressure are not yet measured. This dashboard shows verified hardware and storage information only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(24)
        }
        .onAppear { snapshot = SystemInfoService().snapshot() }
    }

    private func storageLegend(_ title: String, value: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 5)
            Text(value).font(.caption.weight(.medium).monospacedDigit())
        }
    }
}

private struct DashboardMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
            }
            Text(value)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let progress {
                ProgressView(value: progress).tint(tint)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

private struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 0)
                HStack {
                    Text("Open")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .leading)
            .background(tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(tint.opacity(0.12), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
