import Foundation
import IdasenDeskCore
import XCTest

final class IdasenBLEProtocolTests: XCTestCase {
    func testParsesHeightAndSpeedSample() {
        let data = Data([0x96, 0x08, 0x05, 0x00])
        let sample = IdasenBLEProtocol.parsePositionSample(from: data)

        XCTAssertEqual(sample?.height.centimeters ?? 0, 83.48, accuracy: 0.001)
        XCTAssertEqual(sample?.speed, 5)
    }

    func testParsesNegativeSpeedSample() {
        let data = Data([0x96, 0x08, 0xFF, 0xFF])
        let sample = IdasenBLEProtocol.parsePositionSample(from: data)

        XCTAssertEqual(sample?.speed, -1)
    }

    func testEncodesPrimitiveCommands() {
        XCTAssertEqual(IdasenBLEProtocol.commandData(for: .moveUp), Data([0x47, 0x00]))
        XCTAssertEqual(IdasenBLEProtocol.commandData(for: .moveDown), Data([0x46, 0x00]))
        XCTAssertEqual(IdasenBLEProtocol.commandData(for: .stop), Data([0xFF, 0x00]))
        XCTAssertNil(IdasenBLEProtocol.commandData(for: .moveToPreset(.sit)))
    }
}
