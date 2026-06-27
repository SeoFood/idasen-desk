@testable import IdasenDeskCore
import XCTest

final class BluetoothPendingCommandQueueTests: XCTestCase {
    func testQueuesLatestDirectionalCommandForReconnect() {
        var queue = BluetoothPendingCommandQueue()

        queue.enqueue(.moveUp)
        queue.enqueue(.moveDown)

        XCTAssertEqual(queue.command, .moveDown)
        XCTAssertEqual(queue.take(), .moveDown)
        XCTAssertNil(queue.command)
    }

    func testStopClearsPendingReconnectCommand() {
        var queue = BluetoothPendingCommandQueue()

        queue.enqueue(.moveUp)
        queue.enqueue(.stop)

        XCTAssertNil(queue.command)
        XCTAssertNil(queue.take())
    }

    func testTargetCommandsAreNotRetriedAtBluetoothLayer() {
        var queue = BluetoothPendingCommandQueue()

        queue.enqueue(.moveToHeight(DeskHeight(centimeters: 110)))
        queue.enqueue(.moveToPreset(.stand))

        XCTAssertNil(queue.command)
    }
}
