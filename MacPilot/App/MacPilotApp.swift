import SwiftUI

@main
struct MacPilotApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1440, height: 900)
        .windowStyle(.automatic)
    }
}

struct RootView: View {
    @AppStorage("acceptedDisclaimerVersion") private var acceptedDisclaimerVersion = ""

    var body: some View {
        #if APP_STORE_EDITION
        MainShellView()
        #else
        if acceptedDisclaimerVersion == DisclaimerView.currentVersion {
            MainShellView()
        } else {
            DisclaimerView {
                acceptedDisclaimerVersion = DisclaimerView.currentVersion
                AuditLogStore.shared.record("disclaimer_accepted")
            }
        }
        #endif
    }
}
