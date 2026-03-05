import SwiftData
import XCTest
@testable import Waypoint

@MainActor
final class SyncManagerTests: XCTestCase {
    func testEnqueueCreatesPendingOperation() throws {
        let settings = AppSettingsStore(defaults: UserDefaults(suiteName: #function) ?? .standard)

        let monitor = NetworkMonitor()
        let manager = SyncManager(
            networkMonitor: monitor,
            settingsStore: settings,
            supabaseSyncService: SupabaseSyncService(config: .placeholder),
            supabaseAuthService: SupabaseAuthService(config: .placeholder)
        )

        let container = SwiftDataStack.makeContainer(inMemory: true)
        let context = ModelContext(container)

        manager.enqueue(type: .createTrip, payload: ["id": "1"], context: context)

        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations.first?.status, .pending)
    }

    func testOfflineSkipsSyncProcessing() async throws {
        let settings = AppSettingsStore(defaults: UserDefaults(suiteName: #function) ?? .standard)

        let monitor = NetworkMonitor()
        let manager = SyncManager(
            networkMonitor: monitor,
            settingsStore: settings,
            supabaseSyncService: SupabaseSyncService(config: .placeholder),
            supabaseAuthService: SupabaseAuthService(config: .placeholder)
        )

        let container = SwiftDataStack.makeContainer(inMemory: true)
        let context = ModelContext(container)

        manager.enqueue(type: .createTrip, payload: ["id": "1"], context: context)
        await manager.processPendingOperations(context: context)

        let operations = try context.fetch(FetchDescriptor<SyncOperation>())
        XCTAssertEqual(operations.first?.status, .pending)
    }
}
