import AppKit
import SwiftUI

/// App entry point: a menu bar extra plus a settings window. No Dock icon (LSUIElement).
@main
struct SwitchClatterApp: App {
    @StateObject private var controller = AppController.shared
    @AppStorage(Prefs.enabled) private var enabled = true

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(controller)
        } label: {
            Image(nsImage: MenuBarIcon.make(dimmed: !controller.hasPermission || !enabled))
        }
        .menuBarExtraStyle(.window)

        Window("SwitchClatter Settings", id: "settings") {
            SettingsView()
                .environmentObject(controller)
        }
        .windowResizability(.contentSize)
    }
}

/// Builds the keyboard template image for the menu bar, faded when inactive or missing permission.
enum MenuBarIcon {
    static func make(dimmed: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "SwitchClatter")?
            .withSymbolConfiguration(config) else { return NSImage() }
        let image = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: dimmed ? 0.35 : 1)
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Opens the Ko-fi donation page.
enum Support {
    static func openDonation() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }
}
