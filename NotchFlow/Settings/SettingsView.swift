import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var clipboard: ClipboardManager
    @ObservedObject var scanner: MenuBarScanner

    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch NotchFlow at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                if let error = settings.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Toggle("Open the notch when the cursor comes close", isOn: $settings.openOnHover)
                Text(settings.openOnHover ? "Move the cursor to the notch to open it." : "Click the notch to open it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Haptic feedback when the notch opens", isOn: $settings.hapticsEnabled)
            }

            Section("Notch indicators") {
                Toggle("Show when an app is using the microphone", isOn: $settings.showMicrophoneIndicator)
                Toggle("Show battery level when the charger is connected", isOn: $settings.showChargingIndicator)
                Toggle("Show what’s playing", isOn: $settings.showNowPlayingIndicator)
            }

            Section("Now Playing") {
                Toggle("Universal media support", isOn: $settings.universalMediaSupport)
                    .disabled(!NowPlayingManager.isUniversalSupportAvailable)
                Text("Music and Spotify always work. Turn this on to also see browsers, podcasts and other players. "
                    + "It uses the open-source mediaremote-adapter, which isn’t supported by Apple and may stop "
                    + "working after a macOS update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu bar drawer") {
                Toggle("Show pinned apps and menu bar icons in the notch", isOn: $settings.showMenuBarDrawer)
                PermissionRow(
                    title: "Accessibility",
                    detail: "Lists your menu bar icons and clicks them for you, even ones hidden behind the notch.",
                    isGranted: scanner.hasAccessibility,
                    request: scanner.requestAccessibility
                )
                PermissionRow(
                    title: "Screen Recording",
                    detail: "Optional. Shows the real menu bar icons instead of app icons. Nothing is recorded or saved.",
                    isGranted: scanner.hasScreenRecording,
                    request: scanner.requestScreenRecording
                )
            }

            Section("Clipboard") {
                Toggle("Save clipboard history", isOn: $settings.saveClipboardHistory)
                Text("Passwords copied from password managers are never saved. History stays on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("\(clipboard.items.count) items saved")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear History…") { confirmClear = true }
                        .disabled(clipboard.items.isEmpty)
                }
            }

            Section("Keyboard shortcuts") {
                LabeledContent("Open or close the notch", value: HotKeyCenter.toggleNotch.display)
                LabeledContent("Search the clipboard", value: HotKeyCenter.openClipboard.display)
                LabeledContent("Switch tabs (while the notch is focused)", value: "⌘1 – ⌘3")
                LabeledContent("Close the notch", value: "Esc")
            }

            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                Link("NotchFlow on GitHub", destination: URL(string: "https://github.com/hashirsulthan0-cmd/open-source-app")!)
            }
        }
        .formStyle(.grouped)
        .onAppear { scanner.refresh() }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmClear) {
            Button("Clear Everything, Including Pinned", role: .destructive) {
                clipboard.clearAll()
            }
            Button("Clear All but Pinned") {
                clipboard.clearUnpinned()
            }
        } message: {
            Text("This can’t be undone.")
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let isGranted: Bool
    let request: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isGranted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow…", action: request)
            }
        }
    }
}
