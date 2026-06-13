import Foundation
import IdasenDeskCore
import XCTest

final class SettingsStoreTests: XCTestCase {
    func testStoresAndLoadsSettings() throws {
        let suiteName = "IdasenDeskTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        let id = DeskID(rawValue: "desk-1")
        let settings = AppSettings(
            hasCompletedOnboarding: true,
            measurementSystem: .metric,
            activeDeskID: id,
            savedDesks: [SavedDesk(id: id, displayName: "Desk")]
        )

        try store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }
}

