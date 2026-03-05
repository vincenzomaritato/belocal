import SwiftData
import SwiftUI

@main
struct WaypointApp: App {
    @State private var bootstrap = AppBootstrap()

    private let container = SwiftDataStack.makeContainer()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(bootstrap)
                .tint(.accentColor)
        }
        .modelContainer(container)
    }
}
