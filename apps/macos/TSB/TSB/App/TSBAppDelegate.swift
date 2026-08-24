import AppKit

@MainActor
final class TSBAppDelegate: NSObject, NSApplicationDelegate {
    let controller: AppController
    let settingsModel: SettingsModel

    private let startController: (() -> Void)?
    private let stopController: (() -> Void)?
    private let startAcceptanceRunner: (() -> Void)?

    override convenience init() {
        let controller = AppController()
#if DEBUG
        self.init(
            controller: controller,
            settingsModel: SettingsModel(),
            startAcceptanceRunner: { V02AcceptanceRunner.startIfConfigured(controller: controller) }
        )
#else
        self.init(controller: controller, settingsModel: SettingsModel())
#endif
    }

    init(
        controller: AppController,
        settingsModel: SettingsModel,
        startController: (() -> Void)? = nil,
        stopController: (() -> Void)? = nil,
        startAcceptanceRunner: (() -> Void)? = nil
    ) {
        self.controller = controller
        self.settingsModel = settingsModel
        self.startController = startController
        self.stopController = stopController
        self.startAcceptanceRunner = startAcceptanceRunner
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let startController {
            startController()
        } else {
            controller.start()
        }
#if DEBUG
        startAcceptanceRunner?()
#endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let stopController {
            stopController()
        } else {
            controller.stop()
        }
    }
}
