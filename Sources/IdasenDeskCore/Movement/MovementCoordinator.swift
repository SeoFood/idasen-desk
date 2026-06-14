import Foundation

public protocol DeskCommandTransport: Sendable {
    func send(_ command: DeskCommand) async
}

public struct MovementConfiguration: Sendable, Equatable {
    public var distanceOffset: Double
    public var minCommandInterval: TimeInterval
    public var minMovementDelta: Double
    public var movementTimeout: TimeInterval
    public var stallTimeout: TimeInterval

    public init(
        distanceOffset: Double = 0.5,
        minCommandInterval: TimeInterval = 0.5,
        minMovementDelta: Double = 0.5,
        movementTimeout: TimeInterval = 45,
        stallTimeout: TimeInterval = 6
    ) {
        self.distanceOffset = distanceOffset
        self.minCommandInterval = minCommandInterval
        self.minMovementDelta = minMovementDelta
        self.movementTimeout = movementTimeout
        self.stallTimeout = stallTimeout
    }
}

public actor MovementCoordinator {
    private let transport: DeskCommandTransport
    private let configuration: MovementConfiguration
    private let now: @Sendable () -> Date

    private var targetHeight: DeskHeight?
    private var latestSnapshot: DeskSnapshot?
    private var lastCommandDate: Date?
    private var movementStartedAt: Date?
    private var lastMovementAt: Date?
    private var previousHeight: DeskHeight?
    private var currentDirection: MovementDirection = .none
    private var commandLoopTask: Task<Void, Never>?

    public init(
        transport: DeskCommandTransport,
        configuration: MovementConfiguration = MovementConfiguration(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.transport = transport
        self.configuration = configuration
        self.now = now
    }

    public func move(to height: DeskHeight) async {
        cancelCommandLoop()
        targetHeight = height
        movementStartedAt = now()
        lastMovementAt = now()
        lastCommandDate = nil
        previousHeight = latestSnapshot?.currentHeight
        currentDirection = .none
        startCommandLoop()
        await evaluateMovement()
    }

    public func moveUp() async {
        cancelCommandLoop()
        targetHeight = nil
        previousHeight = nil
        currentDirection = .up
        lastCommandDate = nil
        startCommandLoop()
        await sendCommand(for: .up, at: now())
    }

    public func moveDown() async {
        cancelCommandLoop()
        targetHeight = nil
        previousHeight = nil
        currentDirection = .down
        lastCommandDate = nil
        startCommandLoop()
        await sendCommand(for: .down, at: now())
    }

    public func stop() async {
        cancelCommandLoop()
        targetHeight = nil
        previousHeight = nil
        currentDirection = .none
        await transport.send(.stop)
    }

    public func handleSnapshot(_ snapshot: DeskSnapshot) async {
        latestSnapshot = snapshot
        await evaluateMovement()
    }

    private func evaluateMovement() async {
        let currentDate = now()
        if hasTimedOut(at: currentDate) {
            await stop()
            return
        }

        guard let targetHeight, let height = latestSnapshot?.currentHeight else {
            return
        }

        if abs(height.centimeters - targetHeight.centimeters) <= configuration.distanceOffset {
            await stop()
            return
        }

        updateMovementProgress(height: height, at: currentDate)
        if hasStalled(at: currentDate) {
            await stop()
            return
        }

        guard canSendCommand(at: currentDate) else {
            return
        }

        if targetHeight > height {
            await sendCommand(for: .up, at: currentDate)
        } else {
            await sendCommand(for: .down, at: currentDate)
        }
    }

    private func startCommandLoop() {
        commandLoopTask = Task { [configuration] in
            while !Task.isCancelled {
                let delay = UInt64(configuration.minCommandInterval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else {
                    return
                }
                await self.tickCommandLoop()
            }
        }
    }

    private func cancelCommandLoop() {
        commandLoopTask?.cancel()
        commandLoopTask = nil
    }

    private func tickCommandLoop() async {
        if targetHeight != nil {
            await evaluateMovement()
            return
        }

        let currentDate = now()
        guard canSendCommand(at: currentDate) else {
            return
        }

        switch currentDirection {
        case .up:
            await sendCommand(for: .up, at: currentDate)
        case .down:
            await sendCommand(for: .down, at: currentDate)
        case .none:
            cancelCommandLoop()
        }
    }

    private func sendCommand(for direction: MovementDirection, at date: Date) async {
        currentDirection = direction
        lastCommandDate = date

        switch direction {
        case .up:
            await transport.send(.moveUp)
        case .down:
            await transport.send(.moveDown)
        case .none:
            break
        }
    }

    private func hasTimedOut(at date: Date) -> Bool {
        guard let movementStartedAt else {
            return false
        }
        return date.timeIntervalSince(movementStartedAt) > configuration.movementTimeout
    }

    private func hasStalled(at date: Date) -> Bool {
        guard currentDirection != .none, let lastMovementAt else {
            return false
        }
        return date.timeIntervalSince(lastMovementAt) > configuration.stallTimeout
    }

    private func canSendCommand(at date: Date) -> Bool {
        guard let lastCommandDate else {
            return true
        }
        return date.timeIntervalSince(lastCommandDate) >= configuration.minCommandInterval
    }

    private func updateMovementProgress(height: DeskHeight, at date: Date) {
        defer { previousHeight = height }

        guard let previousHeight else {
            lastMovementAt = date
            return
        }

        if abs(height.centimeters - previousHeight.centimeters) >= configuration.minMovementDelta {
            lastMovementAt = date
        }
    }
}

private enum MovementDirection {
    case up
    case down
    case none
}
