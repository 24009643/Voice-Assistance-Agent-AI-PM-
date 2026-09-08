import AppKit

@MainActor
final class TSBAppDelegate: NSObject, NSApplicationDelegate {
    let controller: AppController
    let settingsModel: SettingsModel

    private let startController: (() -> Void)?
    private let stopController: (() -> Void)?
    private let startAcceptanceRunner: (() -> Void)?

    static func makeSettingsModel(
        store: OrganizationSettingsStore = OrganizationSettingsStore(),
        loadPersistedState: Bool = true,
        cancelPendingPolish: @escaping @MainActor () -> Void
    ) -> SettingsModel {
        SettingsModel(
            store: store,
            loadPersistedState: loadPersistedState,
            onPolishAccessRevoked: cancelPendingPolish
        )
    }

    override convenience init() {
        let controller = AppController()
        let settingsModel = Self.makeSettingsModel(
            loadPersistedState: ProcessInfo.processInfo.environment["TSB_XCTEST_HOST"] != "1",
            cancelPendingPolish: { controller.cancelPendingPolishAfterRevoke() }
        )
#if DEBUG
        self.init(
            controller: controller,
            settingsModel: settingsModel,
            startAcceptanceRunner: { V02AcceptanceRunner.startIfConfigured(controller: controller) }
        )
#else
        self.init(controller: controller, settingsModel: settingsModel)
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
