import SwiftUI
import AppKit

/// Responsive, button-driven navigation. The sidebar changes to icon-only at compact widths.
struct MainShellView: View {
    @State private var selection: AppSection = .dashboard

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 1180

            HStack(spacing: 0) {
                sidebar(compact: compact)
                    .frame(width: compact ? 76 : 238)

                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)

                VStack(spacing: 0) {
                    topBar(compact: compact)
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1)
                    detail
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color(nsColor: .underPageBackgroundColor))
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(WindowMaximizer())
    }

    private func sidebar(compact: Bool) -> some View {
        VStack(alignment: compact ? .center : .leading, spacing: 0) {
            if compact {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.top, 20)
                    .padding(.bottom, 24)
            } else {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MacPilot")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                        Text("Clean. Optimise. Take control.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 17)
                .padding(.top, 22)
                .padding(.bottom, 27)

                Text("WORKSPACE")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 19)
                    .padding(.bottom, 9)
            }

            VStack(spacing: 5) {
                ForEach(AppSection.allCases) { section in
                    sidebarButton(section, compact: compact)
                }
            }
            .padding(.horizontal, compact ? 8 : 10)

            Spacer(minLength: 12)

            if compact {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.green)
                    .padding(.bottom, 18)
                    .help("Safe Mode — approved locations only")
            } else {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Safe Mode").font(.system(size: 12, weight: .semibold))
                        Text("Approved locations only")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
                .padding(.horizontal, 12)
                .padding(.bottom, 15)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func sidebarButton(_ section: AppSection, compact: Bool) -> some View {
        let isSelected = selection == section
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selection = section }
        } label: {
            Group {
                if compact {
                    Image(systemName: section.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 20)
                        Text(section.title)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                }
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary.opacity(0.82))
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.accentColor.opacity(0.14))
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor)
                                .frame(width: 3, height: 22)
                        }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(section.title)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func topBar(compact: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(selection.title).font(.system(size: 14, weight: .semibold))
                if !compact {
                    Text("Your Mac, clearly understood.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                if !compact {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Safe Mode").font(.system(size: 11, weight: .semibold))
                        Text("Only approved locations")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(.horizontal, compact ? 16 : 23)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .dashboard:
            DashboardView(
                onOpenStorage: { selection = .storage },
                onOpenCleanup: { selection = .cleanup },
                onOpenApplications: { selection = .applications }
            )
        case .storage: StorageView()
        case .cleanup: CleanupView()
        case .applications: AppManagerView()
        case .debloat: DebloatView()
        case .performance: PerformanceView()
        case .safety: SafetyCenterView()
        case .settings: SettingsView()
        }
    }
}

/// Zooms the initial window to the available desktop area once, without entering full-screen mode.
private struct WindowMaximizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { MaximizingView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class MaximizingView: NSView {
    private var didMaximize = false
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !didMaximize else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, !window.isZoomed else { return }
            window.zoom(nil)
            self.didMaximize = true
        }
    }
}
