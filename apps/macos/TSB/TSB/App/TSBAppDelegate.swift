import AppKit

@MainActor
final class TSBAppDelegate: NSObject, NSApplicationDelegate {
    let controller: AppController
    let settingsModel: SettingsModel

    private let startController: (() -> Void)?
    private let stopController: (() -> Void)?

    override convenience init() {
        self.init(controller: AppController(), settingsModel: SettingsModel())
    }

    init(
        controller: AppController,
        settingsModel: SettingsModel,
        startController: (() -> Void)? = nil,
        stopController: (() -> Void)? = nil
    ) {
        self.controller = controller
        self.settingsModel = settingsModel
        self.startController = startController
        self.stopController = stopController
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let startController {
            startController()
        } else {
            controller.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let stopController {
            stopController()
        } else {
            controller.stop()
        }
    }
}
