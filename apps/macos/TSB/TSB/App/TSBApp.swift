import SwiftUI

@main
struct TSBApp: App {
    @NSApplicationDelegateAdaptor(TSBAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(model: appDelegate.settingsModel)
        }
    }
}
