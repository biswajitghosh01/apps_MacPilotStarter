import SwiftUI

struct DisclaimerView: View {
    static let currentVersion = "1.1"

    let onAccept: () -> Void
    @State private var accepted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MacPilot")
                        .font(.largeTitle.bold())
                    Text("System Optimizer · First-use agreement")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 22)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Important – Please read before continuing", systemImage: "exclamationmark.shield.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    Text("MacPilot is a third-party maintenance utility intended to help you review storage, applications and system resources. MacPilot can analyse selected user-level folders and move individually approved old cache or log files to macOS Trash. Cleanup carries risk, and you should review each item and keep backups.")

                    Group {
                        disclaimerItem("Your responsibility", "You are responsible for reviewing every proposed file and explicitly authorising each cleanup batch. Keep current backups of important data.")
                        disclaimerItem("No warranty", "To the maximum extent permitted by applicable law, the software is provided ‘as is’ and ‘as available’, without express or implied warranties, including warranties of merchantability, fitness for a particular purpose and non-infringement.")
                        disclaimerItem("Potential impact", "Moving cache or log files to Trash may affect application behaviour, settings or locally stored information. Not every file labelled as a cache is necessarily safe to remove. Close the related application before cleanup and review each selected item.")
                        disclaimerItem("Limitation of liability", "To the maximum extent permitted by applicable law, the developer is not liable for indirect, incidental, special or consequential loss arising from use of the software. Nothing in this notice excludes rights or remedies that cannot lawfully be excluded.")
                        disclaimerItem("Security boundaries", "MacPilot does not bypass System Integrity Protection, disable macOS security controls, or permanently delete protected operating-system files. Its current cleanup feature only moves individually approved regular files from selected user Caches or Logs folders to macOS Trash. These safeguards reduce risk but cannot guarantee that every file is safe to remove.")
                    }

                    Text("This notice is not legal advice or a substitute for a separately reviewed end-user licence agreement and privacy policy.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            }

            Divider().padding(.vertical, 16)

            Toggle("I have read and understood this notice and accept responsibility for actions I explicitly authorise.", isOn: $accepted)
                .toggleStyle(.checkbox)
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.bottom, 14)

            Button(action: onAccept) {
                Text("Accept & Continue")
                    .frame(maxWidth: 260)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!accepted)
        }
        .padding(32)
        .frame(minWidth: 680, minHeight: 580)
    }

    private func disclaimerItem(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary)
        }
    }
}
