import Foundation
import IdasenDeskCore
import XCTest

final class AutoStandPlannerTests: XCTestCase {
    func testPlansStandBeforeTopOfHour() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 10, minute: 20)))

        let plan = AutoStandPlanner.plan(now: now, standMinutesPerHour: 10, calendar: calendar)

        let standMinute = calendar.component(.minute, from: plan.nextStand)
        let sitMinute = calendar.component(.minute, from: plan.nextSit)
        XCTAssertEqual(standMinute, 50)
        XCTAssertEqual(sitMinute, 0)
    }

    func testMovesPastStandStartToNextHour() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 10, minute: 55)))

        let plan = AutoStandPlanner.plan(now: now, standMinutesPerHour: 10, calendar: calendar)

        XCTAssertEqual(plan.nextStand.timeIntervalSince(now), 3600, accuracy: 0.001)
    }
}

