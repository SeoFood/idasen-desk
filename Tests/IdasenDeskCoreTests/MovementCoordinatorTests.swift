import Foundation
import IdasenDeskCore
import os
import XCTest

final class MovementCoordinatorTests: XCTestCase {
    func testMovesUpTowardHigherTargetAndStopsAtTarget() async {
        let transport = RecordingTransport()
        let dateProvider = TestDateProvider(Date(timeIntervalSince1970: 0))
        let coordinator = MovementCoordinator(
            transport: transport,
            configuration: MovementConfiguration(minCommandInterval: 0.1, stallTimeout: 10),
            now: dateProvider.now
        )

        await coordinator.handleSnapshot(snapshot(height: 70))
        await coordinator.move(to: DeskHeight(centimeters: 80))
        XCTAssertEqual(transport.commands, [.moveUp])

        dateProvider.advance(by: 1)
        await coordinator.handleSnapshot(snapshot(height: 80))
        XCTAssertEqual(transport.commands, [.moveUp, .stop])
    }

    func testStopsOnMovementTimeout() async {
        let transport = RecordingTransport()
        let dateProvider = TestDateProvider(Date(timeIntervalSince1970: 0))
        let coordinator = MovementCoordinator(
            transport: transport,
            configuration: MovementConfiguration(minCommandInterval: 0.1, movementTimeout: 2, stallTimeout: 10),
            now: dateProvider.now
        )

        await coordinator.handleSnapshot(snapshot(height: 70))
        await coordinator.move(to: DeskHeight(centimeters: 100))
        dateProvider.advance(by: 3)
        await coordinator.handleSnapshot(snapshot(height: 70.2))

        XCTAssertEqual(transport.commands.last, .stop)
    }

    func testStopsOnStall() async {
        let transport = RecordingTransport()
        let dateProvider = TestDateProvider(Date(timeIntervalSince1970: 0))
        let coordinator = MovementCoordinator(
            transport: transport,
            configuration: MovementConfiguration(minCommandInterval: 0.1, movementTimeout: 30, stallTimeout: 1),
            now: dateProvider.now
        )

        await coordinator.handleSnapshot(snapshot(height: 70))
        await coordinator.move(to: DeskHeight(centimeters: 90))
        dateProvider.advance(by: 2)
        await coordinator.handleSnapshot(snapshot(height: 70.1))

        XCTAssertEqual(transport.commands.last, .stop)
    }

    func testContinuesSendingCommandsTowardTargetWithoutNewSnapshot() async {
        let transport = RecordingTransport()
        let dateProvider = TestDateProvider(Date(timeIntervalSince1970: 0))
        let coordinator = MovementCoordinator(
            transport: transport,
            configuration: MovementConfiguration(minCommandInterval: 0.01, movementTimeout: 30, stallTimeout: 10),
            now: dateProvider.now
        )

        await coordinator.handleSnapshot(snapshot(height: 70))
        await coordinator.move(to: DeskHeight(centimeters: 90))

        dateProvider.advance(by: 0.02)
        try? await Task.sleep(nanoseconds: 25_000_000)

        XCTAssertEqual(transport.commands, [.moveUp, .moveUp])
        await coordinator.stop()
    }

    func testManualMoveRepeatsUntilStopped() async {
        let transport = RecordingTransport()
        let dateProvider = TestDateProvider(Date(timeIntervalSince1970: 0))
        let coordinator = MovementCoordinator(
            transport: transport,
            configuration: MovementConfiguration(minCommandInterval: 0.01),
            now: dateProvider.now
        )

        await coordinator.moveUp()
        dateProvider.advance(by: 0.02)
        try? await Task.sleep(nanoseconds: 25_000_000)
        await coordinator.stop()
        let commandCountAfterStop = transport.commands.count

        dateProvider.advance(by: 0.02)
        try? await Task.sleep(nanoseconds: 25_000_000)

        XCTAssertEqual(transport.commands.prefix(2), [.moveUp, .moveUp])
        XCTAssertEqual(transport.commands[commandCountAfterStop - 1], .stop)
        XCTAssertEqual(transport.commands.count, commandCountAfterStop)
    }

    func testTargetMoveWithoutSnapshotStopsOnTimeout() async {
        let transport = RecordingTransport()
        let dateProvider = TestDateProvider(Date(timeIntervalSince1970: 0))
        let coordinator = MovementCoordinator(
            transport: transport,
            configuration: MovementConfiguration(minCommandInterval: 0.01, movementTimeout: 0.01, stallTimeout: 10),
            now: dateProvider.now
        )

        await coordinator.move(to: DeskHeight(centimeters: 90))
        dateProvider.advance(by: 0.02)
        try? await Task.sleep(nanoseconds: 25_000_000)

        XCTAssertEqual(transport.commands, [.stop])
    }

    private func snapshot(height: Double) -> DeskSnapshot {
        DeskSnapshot(
            id: DeskID(rawValue: "desk"),
            name: "Desk",
            currentHeight: DeskHeight(centimeters: height),
            connectionState: .connected
        )
    }
}

private final class RecordingTransport: DeskCommandTransport, @unchecked Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: [DeskCommand]())

    var commands: [DeskCommand] {
        storage.withLock { $0 }
    }

    func send(_ command: DeskCommand) async {
        storage.withLock { $0.append(command) }
    }
}

private final class TestDateProvider: @unchecked Sendable {
    private let storage: OSAllocatedUnfairLock<Date>

    init(_ date: Date) {
        storage = OSAllocatedUnfairLock(initialState: date)
    }

    func now() -> Date {
        storage.withLock { $0 }
    }

    func advance(by interval: TimeInterval) {
        storage.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}
