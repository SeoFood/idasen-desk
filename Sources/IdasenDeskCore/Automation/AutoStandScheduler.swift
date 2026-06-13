import CoreGraphics
import Foundation

public protocol IdleTimeProviding: Sendable {
    func secondsSinceLastUserEvent() -> TimeInterval
}

public struct SystemIdleTimeProvider: IdleTimeProviding {
    public init() {}

    public func secondsSinceLastUserEvent() -> TimeInterval {
        let anyEvent = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyEvent)
    }
}

public struct AutoStandPlan: Equatable, Sendable {
    public var nextStand: Date
    public var nextSit: Date
}

public enum AutoStandPlanner {
    public static func plan(now: Date, standMinutesPerHour: Int, calendar: Calendar = .current) -> AutoStandPlan {
        let nextSit = nextHour(after: now, calendar: calendar)
        let standDuration = TimeInterval(max(0, standMinutesPerHour) * 60)
        var nextStand = nextSit.addingTimeInterval(-standDuration)
        if nextStand < now {
            nextStand = now.addingTimeInterval(3600)
        }
        return AutoStandPlan(nextStand: nextStand, nextSit: nextSit)
    }

    private static func nextHour(after date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let hourStart = calendar.date(from: components) ?? date
        return calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? date.addingTimeInterval(3600)
    }
}

public final class AutoStandScheduler: @unchecked Sendable {
    public var onCommand: (@Sendable (DeskCommand) -> Void)?

    private let idleProvider: IdleTimeProviding
    private var standTimer: Timer?
    private var sitTimer: Timer?

    public init(idleProvider: IdleTimeProviding = SystemIdleTimeProvider()) {
        self.idleProvider = idleProvider
    }

    deinit {
        stop()
    }

    public func update(settings: AutomationSettings) {
        stop()
        guard settings.isEnabled else {
            return
        }

        let plan = AutoStandPlanner.plan(now: Date(), standMinutesPerHour: settings.standMinutesPerHour)
        let standTimer = Timer(fire: plan.nextStand, interval: 3600, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }
            if self.idleProvider.secondsSinceLastUserEvent() < settings.requiredActiveSeconds {
                self.onCommand?(.moveToPreset(.stand))
            }
        }
        let sitTimer = Timer(fire: plan.nextSit, interval: 3600, repeats: true) { [weak self] _ in
            self?.onCommand?(.moveToPreset(.sit))
        }

        standTimer.tolerance = 10
        sitTimer.tolerance = 10
        RunLoop.main.add(standTimer, forMode: .common)
        RunLoop.main.add(sitTimer, forMode: .common)
        self.standTimer = standTimer
        self.sitTimer = sitTimer
    }

    public func stop() {
        standTimer?.invalidate()
        sitTimer?.invalidate()
        standTimer = nil
        sitTimer = nil
    }
}

