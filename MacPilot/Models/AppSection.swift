import Foundation

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case storage
    case cleanup
    case applications
    case debloat
    case performance
    case safety
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .storage: return "Storage Analyzer"
        case .cleanup: return "Smart Cleanup"
        case .applications: return "Applications"
        case .debloat: return "Debloat Manager"
        case .performance: return "System & Performance"
        case .safety: return "Safety Center"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .storage: return "externaldrive.fill"
        case .cleanup: return "sparkles"
        case .applications: return "app.dashed"
        case .debloat: return "slider.horizontal.3"
        case .performance: return "gauge.with.dots.needle.67percent"
        case .safety: return "checkmark.shield.fill"
        case .settings: return "gearshape.fill"
        }
    }
}
