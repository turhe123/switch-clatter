import AppKit
import ServiceManagement
import SwiftUI

/// The settings window: sound options, per-app mute list, launch at login and About.
struct SettingsView: View {
    @EnvironmentObject private var controller: AppController
    @AppStorage(Prefs.profile) private var profile = SwitchProfile.linear.rawValue
    @AppStorage(Prefs.volume) private var volume = 0.6
    @AppStorage(Prefs.pitchVariance) private var pitchVariance = 0.5
    @AppStorage(Prefs.stereoSpread) private var stereoSpread = true
    @AppStorage(Prefs.playRelease) private var playRelease = true
    @AppStorage(Prefs.playModifiers) private var playModifiers = false
    @AppStorage(Prefs.mutedApps) private var mutedApps = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private var mutedList: [String] { Prefs.decodeApps(mutedApps) }

    var body: some View {
        Form {
            if !controller.hasPermission {
                Section { PermissionCard() }
            }

            Section("Sound") {
                Picker("Switch profile", selection: $profile) {
                    ForEach(SwitchProfile.allCases) { Text($0.title).tag($0.rawValue) }
                }
                LabeledContent("Volume") { Slider(value: $volume, in: 0...1) }
                LabeledContent("Pitch variance") { Slider(value: $pitchVariance, in: 0...1) }
                Toggle("Stereo spread by key position", isOn: $stereoSpread)
                Toggle("Play release sounds", isOn: $playRelease)
                Toggle("Play sounds for modifier keys", isOn: $playModifiers)
                Button("Play Test Sound") { controller.preview() }
            }

            Section {
                if mutedList.isEmpty {
                    Text("No apps muted").foregroundStyle(.secondary)
                }
                ForEach(mutedList, id: \.self) { id in
                    HStack {
                        Text(displayName(for: id))
                        Spacer()
                        Button(role: .destructive) {
                            mutedApps = mutedList.filter { $0 != id }.joined(separator: "\n")
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }
                Menu("Add Running App…") {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                            if let id = app.bundleIdentifier { mutedApps = (mutedList + [id]).joined(separator: "\n") }
                        }
                    }
                }
            } header: {
                Text("Mute in these apps")
            } footer: {
                Text("Sounds are also muted automatically while the screen is locked.")
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { updateLoginItem() }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section("About") {
                Text("SwitchClatter synthesizes mechanical keyboard sounds in real time. It is privacy safe: it only ever reads key codes to choose a sound and stereo position — it never inspects, logs or stores the characters you type, and it makes no network connections.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                Button {
                    Support.openDonation()
                } label: {
                    Label("Support / Donate ❤️", systemImage: "heart.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 640)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .filter { !mutedList.contains($0.bundleIdentifier ?? "") && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func displayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
