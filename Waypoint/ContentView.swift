import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        RootTabView()
    }
}

#Preview {
    ContentView()
        .environment(AppBootstrap())
        .modelContainer(SwiftDataStack.makeContainer(inMemory: true))
}
