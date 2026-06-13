import IdasenDeskCore
import XCTest

final class CommandParsingTests: XCTestCase {
    func testParsesAppleScriptMoveCommands() {
        XCTAssertEqual(DeskCommandParser.parseMove("to-sit"), .moveToPreset(.sit))
        XCTAssertEqual(DeskCommandParser.parseMove("to-stand"), .moveToPreset(.stand))
        XCTAssertEqual(DeskCommandParser.parseMove("up"), .moveUp)
        XCTAssertEqual(DeskCommandParser.parseMove("down"), .moveDown)
        XCTAssertEqual(DeskCommandParser.parseMove("stop"), .stop)
        XCTAssertNil(DeskCommandParser.parseMove("sideways"))
    }

    func testParsesExplicitHeightUnits() {
        XCTAssertEqual(
            DeskCommandParser.parseMoveToHeight("120cm", measurementSystem: .imperial),
            .moveToHeight(DeskHeight(centimeters: 120))
        )

        let command = DeskCommandParser.parseMoveToHeight("55in", measurementSystem: .metric)
        guard case .moveToHeight(let height) = command else {
            return XCTFail("Expected height command")
        }
        XCTAssertEqual(height.centimeters, 139.7, accuracy: 0.001)
    }

    func testParsesImplicitHeightFromPreferenceUnit() {
        XCTAssertEqual(
            DeskCommandParser.parseMoveToHeight("80", measurementSystem: .metric),
            .moveToHeight(DeskHeight(centimeters: 80))
        )

        let command = DeskCommandParser.parseMoveToHeight("40", measurementSystem: .imperial)
        guard case .moveToHeight(let height) = command else {
            return XCTFail("Expected height command")
        }
        XCTAssertEqual(height.centimeters, 101.6, accuracy: 0.001)
    }
}

