import Foundation
import os

public final class EventBroadcaster<Event: Sendable>: @unchecked Sendable {
    private let continuations = OSAllocatedUnfairLock(initialState: [UUID: AsyncStream<Event>.Continuation]())

    public init() {}

    public func stream() -> AsyncStream<Event> {
        AsyncStream { continuation in
            let id = UUID()
            continuations.withLock { storage in
                storage[id] = continuation
            }
            continuation.onTermination = { [weak self] _ in
                self?.continuations.withLock { storage in
                    storage[id] = nil
                }
            }
        }
    }

    public func yield(_ event: Event) {
        let currentContinuations = continuations.withLock { Array($0.values) }
        for continuation in currentContinuations {
            continuation.yield(event)
        }
    }
}
