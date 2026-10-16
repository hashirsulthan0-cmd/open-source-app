import SwiftUI

/// Settings, split into tabs so each page is short. Every page scrolls on its own, so
/// nothing is cut off on smaller screens.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var clipboard: ClipboardManager
    @ObservedObject var scanner: MenuBarScanner
    let previewNotch: () -> Void

    var body: some View {
        TabView {
            GeneralSettings(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettings(settings: settings, previewNotch: previewNotch)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            FeatureSettings(settings: settings, clipboard: clipboard)
                .tabItem { Label("Features", systemImage: "square.grid.2x2") }
            PermissionSettings(scanner: scanner)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            ShortcutSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 540, idealWidth: 580, minHeight: 420, idealHeight: 480)
        .onAppear { scanner.refresh() }
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Launch NotchFlow at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                if let error = settings.launchAtLoginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Opening the notch") {
                Toggle("Open when the cursor rests on the notch", isOn: $settings.openOnHover)
                if settings.openOnHover {
                    Picker("Sensitivity", selection: $settings.hoverSensitivity) {
                        ForEach(HoverSensitivity.allCases) { sensitivity in
                            Text(sensitivity.title).tag(sensitivity)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(settings.hoverSensitivity.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Click the notch, or press ⌃⌥Space, to open it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Haptic feedback when it opens", isOn: $settings.hapticsEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    @ObservedObject var settings: SettingsStore
    let previewNotch: () -> Void

    var body: some View {
        Form {
            Section("Glass effect") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Glossiness")
                        Spacer()
                        Text(intensityLabel)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $settings.glassIntensity, in: 0...1) {
                        Text("Glossiness")
                    } minimumValueLabel: {
                        Text("Solid").font(.caption)
                    } maximumValueLabel: {
                        Text("Glass").font(.caption)
                    }
                }
                HStack {
                    Text("Changes show up in the notch right away.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Preview in Notch", action: previewNotch)
                }
            }

            Section("Beside the closed notch, show…") {
                Toggle("When an app is using the microphone", isOn: $settings.showMicrophoneIndicator)
                Toggle("What’s playing", isOn: $settings.showNowPlayingIndicator)
                Toggle("Battery level when the charger is connected", isOn: $settings.showChargingIndicator)
            }
        }
        .formStyle(.grouped)
    }

    private var intensityLabel: String {
        let percent = Int((settings.glassIntensity * 100).rounded())
        return percent == 0 ? "Solid black" : "\(percent)%"
    }
}

// MARK: - Features

private struct FeatureSettings: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var clipboard: ClipboardManager

    @State private var confirmClear = false

    var body: some View {
        Form {
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
                Text("Needs Accessibility permission to list and click your menu bar icons. See the Permissions tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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

// MARK: - Permissions

private struct PermissionSettings: View {
    @ObservedObject var scanner: MenuBarScanner

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    title: "Accessibility",
                    detail: "Lists your menu bar icons and clicks them for you, even ones hidden behind the notch. "
                        + "Also opens Spotlight from the drawer.",
                    isGranted: scanner.hasAccessibility,
                    request: scanner.requestAccessibility
                )
                PermissionRow(
                    title: "Screen Recording",
                    detail: "Optional. Shows the real menu bar icons instead of app icons. Nothing is recorded or saved.",
                    isGranted: scanner.hasScreenRecording,
                    request: scanner.requestScreenRecording
                )
                LabeledContent {
                    Text("Asked when needed")
                        .foregroundStyle(.secondary)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automation (Music, Spotify)")
                        Text("macOS asks the first time you play, pause or skip from the notch.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                HStack(alignment: .top) {
                    Text("Allowed a permission but it isn’t working? Remove NotchFlow from that list in System Settings and add it again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Privacy & Security") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            // Pick up permissions granted in System Settings without reopening this window.
            scanner.refresh()
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

// MARK: - Shortcuts

private struct ShortcutSettings: View {
    var body: some View {
        Form {
            Section("Anywhere") {
                LabeledContent("Open or close the notch", value: HotKeyCenter.toggleNotch.display)
                LabeledContent("Search the clipboard", value: HotKeyCenter.openClipboard.display)
            }
            Section("While the notch is focused") {
                LabeledContent("Switch tabs", value: "⌘1 – ⌘3")
                LabeledContent("Copy the top search result", value: "Return")
                LabeledContent("Close the notch", value: "Esc")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutSettings: View {
    private let repository = URL(string: "https://github.com/hashirsulthan0-cmd/open-source-app")!

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NotchFlow")
                            .font(.headline)
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Links") {
                Link("Source code on GitHub", destination: repository)
                Link("Download the latest release", destination: repository.appendingPathComponent("releases/latest"))
                Link("Report a problem or suggest an idea", destination: repository.appendingPathComponent("issues/new"))
            }
            Section("Credits") {
                Text("Universal Now Playing uses mediaremote-adapter by Jonas van den Berg and contributors (BSD 3-Clause License).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
