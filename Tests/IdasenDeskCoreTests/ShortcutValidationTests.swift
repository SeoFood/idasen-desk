import IdasenDeskCore
import XCTest

final class ShortcutValidationTests: XCTestCase {
    func testDetectsEnabledDuplicatesOnly() {
        let duplicates = ShortcutValidation.duplicates(in: [
            ShortcutBinding(id: "a", action: .moveToSit, keyCode: 1, modifiers: [.command], isEnabled: true),
            ShortcutBinding(id: "b", action: .moveToStand, keyCode: 1, modifiers: [.command], isEnabled: true),
            ShortcutBinding(id: "c", action: .stop, keyCode: 1, modifiers: [.command], isEnabled: false)
        ])

        XCTAssertEqual(duplicates.map(\.id), ["b"])
    }
}

