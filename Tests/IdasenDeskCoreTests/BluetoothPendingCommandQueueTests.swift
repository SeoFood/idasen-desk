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

    func testCommandHealthTimesOutRetryableCommandWithoutPositionSample() {
        var tracker = BluetoothCommandHealthTracker()
        let start = Date(timeIntervalSince1970: 10)

        tracker.recordCommand(.moveUp, at: start)

        XCTAssertTrue(tracker.isAwaitingPositionSample)
        XCTAssertNil(tracker.timedOutCommand(at: start.addingTimeInterval(1.9), timeout: 2.0))
        XCTAssertEqual(tracker.timedOutCommand(at: start.addingTimeInterval(2.0), timeout: 2.0), .moveUp)
        XCTAssertFalse(tracker.isAwaitingPositionSample)
    }

    func testCommandHealthClearsWhenPositionSampleArrives() {
        var tracker = BluetoothCommandHealthTracker()
        let start = Date(timeIntervalSince1970: 10)

        tracker.recordCommand(.moveDown, at: start)
        tracker.recordPositionSample(at: start.addingTimeInterval(0.5))

        XCTAssertFalse(tracker.isAwaitingPositionSample)
        XCTAssertNil(tracker.timedOutCommand(at: start.addingTimeInterval(3), timeout: 2.0))
        XCTAssertEqual(tracker.lastPositionSampleAt, start.addingTimeInterval(0.5))
    }

    func testCommandHealthIgnoresNonRetryableCommands() {
        var tracker = BluetoothCommandHealthTracker()
        let start = Date(timeIntervalSince1970: 10)

        tracker.recordCommand(.moveUp, at: start)
        tracker.recordCommand(.stop, at: start.addingTimeInterval(0.1))

        XCTAssertFalse(tracker.isAwaitingPositionSample)
        XCTAssertNil(tracker.timedOutCommand(at: start.addingTimeInterval(3), timeout: 2.0))
    }
}
