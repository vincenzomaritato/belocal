import SwiftData
import SwiftUI

@main
struct BeLocalApp: App {
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
