import SwiftUI

/// Contents of the menu bar popover: permission prompt, on/off, profile, volume and actions.
struct MenuView: View {
    @EnvironmentObject private var controller: AppController
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Prefs.enabled) private var enabled = true
    @AppStorage(Prefs.profile) private var profile = SwitchProfile.linear.rawValue
    @AppStorage(Prefs.volume) private var volume = 0.6
    @AppStorage(Prefs.mutedApps) private var mutedApps = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "keyboard").font(.title2)
                Text("SwitchClatter").font(.headline)
                Spacer()
                Toggle("", isOn: $enabled).toggleStyle(.switch).labelsHidden()
                    .disabled(!controller.hasPermission)
            }

            if !controller.hasPermission {
                PermissionCard()
            } else if controller.tapFailed {
                ErrorRow(message: "Couldn't start listening for keys. Try relaunching SwitchClatter.")
            }
            if let error = controller.engineError {
                ErrorRow(message: error, retry: controller.retryAudio)
            }
            if let reason = controller.muteReason(mutedApps: mutedApps) {
                Label(reason, systemImage: "speaker.slash").font(.caption).foregroundStyle(.secondary)
            }

            Picker("Switch", selection: $profile) {
                ForEach(SwitchProfile.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: profile) { controller.preview() }

            HStack {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: $volume, in: 0...1)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
            }

            Divider()

            Button {
                Support.openDonation()
            } label: {
                Label("Support / Donate ❤️", systemImage: "heart.fill").frame(maxWidth: .infinity)
            }
            .controlSize(.large)

            HStack {
                Button("Settings…") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { controller.refreshPermission() }
    }
}

/// Prominent explanation + button shown until Input Monitoring is granted.
struct PermissionCard: View {
    @EnvironmentObject private var controller: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Input Monitoring needed", systemImage: "lock.shield").font(.subheadline.bold())
            Text("SwitchClatter needs Input Monitoring to hear when keys go down and up. It only sees key codes — never what you type.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                controller.requestPermission()
            } label: {
                Text("Open Input Monitoring Settings").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A red warning row with an optional retry action.
struct ErrorRow: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let retry { Button("Retry", action: retry).controlSize(.small) }
        }
        .padding(8)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}
