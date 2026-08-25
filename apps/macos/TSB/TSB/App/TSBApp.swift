import AppKit
import SwiftUI

@main
struct TSBApp: App {
    @NSApplicationDelegateAdaptor(TSBAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(model: appDelegate.settingsModel)
        }
        MenuBarExtra {
            MenuBarView(
                state: appDelegate.controller.state,
                toggleRecording: appDelegate.controller.toggleRecordingFromUI,
                cancelRecording: appDelegate.controller.cancelRecordingFromUI,
                openMicrophoneSettings: appDelegate.controller.openMicrophoneSettings,
                quit: { NSApplication.shared.terminate(nil) }
            )
        } label: {
            MenuBarLabel(state: appDelegate.controller.state)
        }
    }
}
