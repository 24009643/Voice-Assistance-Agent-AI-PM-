import SwiftUI

@main
struct TSBApp: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        WindowGroup {
            PlaceholderView(state: controller.state, onToggle: controller.toggleForDevelopment)
                .onAppear(perform: controller.start)
        }
    }
}
