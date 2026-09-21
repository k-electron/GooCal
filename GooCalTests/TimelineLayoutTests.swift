//
//  TimelineLayoutTests.swift
//  GooCalTests
//

import Testing
import Foundation
import CoreGraphics
@testable import GooCal

@Suite("TimelineCoordinateConverter Behavioral Contracts & Scaling Invariants")
struct TimelineCoordinateConverterTests {

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    @Test("Coordinate converter respects 40 pt/hour scale and 960 pt 24-hour total height")
    func scaleAndTotalHeightInvariants() {
        let converter = TimelineCoordinateConverter(pointsPerHour: 40.0, minimumEventHeight: 18.0)

        #expect(converter.pointsPerHour == 40.0)
        #expect(converter.totalHeight == 960.0)

        // 1 hour (3600s) = 40 pt
        #expect(converter.height(for: 3600) == 40.0)
        // 1.5 hours (5400s) = 60 pt
        #expect(converter.height(for: 5400) == 60.0)
        // 30 min (1800s) = 20 pt (above 18 pt min)
        #expect(converter.height(for: 1800) == 20.0)
    }

    @Test("Brief events enforce minimum height threshold of 18 points for typography legibility")
    func minimumHeightThresholdEnforced() {
        let converter = TimelineCoordinateConverter(pointsPerHour: 40.0, minimumEventHeight: 18.0)

        // 15 min (900s) would be 10 pt -> clamped to 18 pt
        #expect(converter.height(for: 900) == 18.0)
        #expect(converter.rawHeight(for: 900) == 10.0)

        // 5 min (300s) would be 3.33 pt -> clamped to 18 pt
        #expect(converter.height(for: 300) == 18.0)

        // 0 seconds -> clamped to 18 pt
        #expect(converter.height(for: 0) == 18.0)
    }

    @Test("Y-offset maps timestamps to vertical points from start of day (00:00 = 0 pt, 10:00 = 400 pt, 24:00 = 960 pt)")
    func yOffsetMapsFromStartOfDay() {
        let cal = utcCalendar
        let converter = TimelineCoordinateConverter(calendar: cal)
        let dayStart = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 0, minute: 0, second: 0))!

        let midnight = dayStart
        let tenAM = cal.date(byAdding: .hour, value: 10, to: dayStart)!
        let noon = cal.date(byAdding: .hour, value: 12, to: dayStart)!
        let halfPastTwelve = cal.date(byAdding: .minute, value: 30, to: noon)!
        let nextMidnight = cal.date(byAdding: .hour, value: 24, to: dayStart)!

        #expect(converter.yOffset(for: midnight, relativeTo: dayStart) == 0.0)
        #expect(converter.yOffset(for: tenAM, relativeTo: dayStart) == 400.0)
        #expect(converter.yOffset(for: halfPastTwelve, relativeTo: dayStart) == 500.0)
        #expect(converter.yOffset(for: nextMidnight, relativeTo: dayStart) == 960.0)
    }

    @Test("Target scroll offset positions anchor time at one-third from top and clamps within canvas bounds")
    func targetScrollOffsetOneThirdRuleAndClamping() {
        let cal = utcCalendar
        let converter = TimelineCoordinateConverter(calendar: cal)
        let dayStart = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 0, minute: 0, second: 0))!
        let viewportHeight: CGFloat = 480.0 // Standard popover height

        // 12:00 is at Y = 480 pt. 1/3rd of 480 is 160. Target = 480 - 160 = 320 pt.
        let noon = cal.date(byAdding: .hour, value: 12, to: dayStart)!
        let offsetNoon = converter.targetScrollOffset(for: noon, relativeTo: dayStart, viewportHeight: viewportHeight)
        #expect(offsetNoon == 320.0)

        // 01:00 is at Y = 40 pt. Target = 40 - 160 = -120 pt -> clamped to 0 pt.
        let oneAM = cal.date(byAdding: .hour, value: 1, to: dayStart)!
        let offsetOneAM = converter.targetScrollOffset(for: oneAM, relativeTo: dayStart, viewportHeight: viewportHeight)
        #expect(offsetOneAM == 0.0)

        // 23:00 is at Y = 920 pt. Target = 920 - 160 = 760 pt -> clamped to (960 - 480 = 480 pt).
        let elevenPM = cal.date(byAdding: .hour, value: 23, to: dayStart)!
        let offsetElevenPM = converter.targetScrollOffset(for: elevenPM, relativeTo: dayStart, viewportHeight: viewportHeight)
        #expect(offsetElevenPM == 480.0)

        // Viewport larger than total canvas (e.g. 1000 pt) clamps max offset to 0 pt.
        let offsetOversized = converter.targetScrollOffset(for: noon, relativeTo: dayStart, viewportHeight: 1000.0)
        #expect(offsetOversized == 0.0)
    }
}

@Suite("TimelineLayoutEngine Event Filtering & Multi-Day Clamping Contracts")
struct TimelineLayoutFilteringAndClampingTests {

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    @Test("Filtering excludes all-day events and declined invitations while preserving accepted and tentative")
    func filteringAllDayAndDeclinedEvents() {
        let cal = utcCalendar
        let engine = TimelineLayoutEngine(calendar: cal)
        let activeDay = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 10, minute: 0, second: 0))!
        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 10, minute: 0, second: 0))!
        let end = cal.date(byAdding: .hour, value: 1, to: start)!

        let allDayEvent = CalendarEvent(id: "all-day", title: "Holiday", startDate: start, endDate: end, isAllDay: true)
        let declinedEvent = CalendarEvent(id: "declined", title: "Skipped", startDate: start, endDate: end, participantStatus: .declined)
        let acceptedEvent = CalendarEvent(id: "accepted", title: "Sprint Planning", startDate: start, endDate: end, participantStatus: .accepted)
        let tentativeEvent = CalendarEvent(id: "tentative", title: "Discussion", startDate: start, endDate: end, participantStatus: .tentative)
        let pendingEvent = CalendarEvent(id: "pending", title: "Pending Inv", startDate: start, endDate: end, participantStatus: .pending)
        let unknownEvent = CalendarEvent(id: "unknown", title: "Self created", startDate: start, endDate: end, participantStatus: .unknown)

        let placed = engine.layoutEvents([allDayEvent, declinedEvent, acceptedEvent, tentativeEvent, pendingEvent, unknownEvent], for: activeDay)

        let placedIDs = Set(placed.map(\.id))
        #expect(!placedIDs.contains("all-day"))
        #expect(!placedIDs.contains("declined"))
        #expect(placedIDs.contains("accepted"))
        #expect(placedIDs.contains("tentative"))
        #expect(placedIDs.contains("pending"))
        #expect(placedIDs.contains("unknown"))
    }

    @Test("Events strictly outside active day boundaries are omitted")
    func filteringEventsOutsideActiveDay() {
        let cal = utcCalendar
        let engine = TimelineLayoutEngine(calendar: cal)
        let activeDay = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 12, minute: 0, second: 0))!

        let yesterdayStart = cal.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 10, minute: 0, second: 0))!
        let yesterdayEnd = cal.date(byAdding: .hour, value: 1, to: yesterdayStart)!
        let yesterdayEvent = CalendarEvent(id: "yesterday", title: "Past", startDate: yesterdayStart, endDate: yesterdayEnd)

        let tomorrowStart = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 10, minute: 0, second: 0))!
        let tomorrowEnd = cal.date(byAdding: .hour, value: 1, to: tomorrowStart)!
        let tomorrowEvent = CalendarEvent(id: "tomorrow", title: "Future", startDate: tomorrowStart, endDate: tomorrowEnd)

        let placed = engine.layoutEvents([yesterdayEvent, tomorrowEvent], for: activeDay)
        #expect(placed.isEmpty)
    }

    @Test("Multi-day event crossing midnight from yesterday is clamped to 00:00 with continuation flag")
    func multiDayClampingFromYesterday() {
        let cal = utcCalendar
        let engine = TimelineLayoutEngine(calendar: cal)
        let activeDay = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 12, minute: 0, second: 0))!
        let dayStart = cal.startOfDay(for: activeDay)

        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 22, minute: 0, second: 0))!
        let end = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 2, minute: 0, second: 0))!
        let overnightEvent = CalendarEvent(id: "overnight", title: "Hackathon Late Night", startDate: start, endDate: end)

        let placed = engine.layoutEvents([overnightEvent], for: activeDay, coordinateConverter: TimelineCoordinateConverter(calendar: cal))

        #expect(placed.count == 1)
        let item = placed[0]
        #expect(item.spansFromYesterday == true)
        #expect(item.spansIntoTomorrow == false)
        #expect(item.effectiveStartDate == dayStart)
        #expect(item.effectiveEndDate == end)
        #expect(item.yOffset == 0.0)
        #expect(item.height == 80.0) // 2 hours * 40 pt
    }

    @Test("Multi-day event crossing midnight into tomorrow is clamped to 24:00 with continuation flag")
    func multiDayClampingIntoTomorrow() {
        let cal = utcCalendar
        let engine = TimelineLayoutEngine(calendar: cal)
        let activeDay = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 12, minute: 0, second: 0))!
        let dayStart = cal.startOfDay(for: activeDay)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!

        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 22, minute: 0, second: 0))!
        let end = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 2, minute: 0, second: 0))!
        let lateNightEvent = CalendarEvent(id: "late-night", title: "Release Deployment", startDate: start, endDate: end)

        let placed = engine.layoutEvents([lateNightEvent], for: activeDay, coordinateConverter: TimelineCoordinateConverter(calendar: cal))

        #expect(placed.count == 1)
        let item = placed[0]
        #expect(item.spansFromYesterday == false)
        #expect(item.spansIntoTomorrow == true)
        #expect(item.effectiveStartDate == start)
        #expect(item.effectiveEndDate == dayEnd)
        #expect(item.yOffset == 880.0) // 22h * 40 pt
        #expect(item.height == 80.0)  // 2 hours remaining today * 40 pt
    }

    @Test("Multi-day event spanning the entire 24-hour day sets both continuation flags and fills canvas")
    func multiDayClampingEntireDay() {
        let cal = utcCalendar
        let engine = TimelineLayoutEngine(calendar: cal)
        let activeDay = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 12, minute: 0, second: 0))!
        let dayStart = cal.startOfDay(for: activeDay)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!

        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 12, minute: 0, second: 0))!
        let end = cal.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 12, minute: 0, second: 0))!
        let conferenceEvent = CalendarEvent(id: "conference", title: "WWDC", startDate: start, endDate: end)

        let placed = engine.layoutEvents([conferenceEvent], for: activeDay, coordinateConverter: TimelineCoordinateConverter(calendar: cal))

        #expect(placed.count == 1)
        let item = placed[0]
        #expect(item.spansFromYesterday == true)
        #expect(item.spansIntoTomorrow == true)
        #expect(item.effectiveStartDate == dayStart)
        #expect(item.effectiveEndDate == dayEnd)
        #expect(item.yOffset == 0.0)
        #expect(item.height == 960.0)
    }
}

@Suite("TimelineLayoutEngine Overlap Partitioning & Precedence Ordering")
struct TimelineLayoutOverlapAndPrecedenceTests {

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    @Test("Isolated single event occupies full width with column 0 and totalColumns 1")
    func singleEventOccupiesSingleColumn() {
        let cal = utcCalendar
        let engine = TimelineLayoutEngine(calendar: cal)
        let activeDay = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 10, minute: 0, second: 0))!
        let start = activeDay
        let end = cal.date(byAdding: .hour, value: 1, to: start)!

        let event = CalendarEvent(id: "single", title: "Design Review", startDate: start, endDate: end)
        let placed = engine.layoutEvents([event], for: activeDay)

        #expect(placed.count == 1)
        #expect(placed[0].columnIndex == 0)
        #expect(placed[0].totalColumns == 1)
        #expect(placed[0].overflowCount == 0)
    }

    @Test("Two overlapping events partition into two columns (columnIndex 0 and 1, totalColumns 2)")
    func twoOverlappingEventsPartitionCorrectly() {
        let cal = utcCalendar
        let engine = TimelineLayoutEngine(calendar: cal)
        let activeDay = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 10, minute: 0, second: 0))!
        let start1 = activeDay
        let end1 = cal.date(byAdding: .hour, value: 1, to: start1)!
        let start2 = cal.date(byAdding: .minute, value: 30, to: start1)!
        let end2 = cal.date(byAdding: .hour, value: 1, to: start2)!

        let event1 = CalendarEvent(id: "e1", title: "Meeting 1", startDate: start1, endDate: end1, participantStatus: .accepted)
        let event2 = CalendarEvent(id: "e2", title: "Meeting 2", startDate: start2, endDate: end2, participantStatus: .tentative)

        let placed = engine.layoutEvents([event1, event2], for: activeDay)

        #expect(placed.count == 2)
        #expect(placed[0].id == "e1")
        #expect(placed[0].columnIndex == 0)
        #expect(placed[0].totalColumns == 2)
        #expect(placed[0].overflowCount == 0)

        #expect(placed[1].id == "e2")
        #expect(placed[1].columnIndex == 1)
        #expect(placed[1].totalColumns == 2)
        #expect(placed[1].overflowCount == 0)
    }

    @Test("Three overlapping events partition into three columns (columnIndex 0, 1, 2, totalColumns 3)")
    func threeOverlappingEventsPartitionCorrectly() {
        let cal = utcCalendar
        let engine = TimelineLayoutEngine(calendar: cal)
        let activeDay = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 10, minute: 0, second: 0))!
        let start = activeDay
        let end = cal.date(byAdding: .hour, value: 1, to: start)!

        let e1 = CalendarEvent(id: "e1", title: "M1", startDate: start, endDate: end, participantStatus: .accepted)
        let e2 = CalendarEvent(id: "e2", title: "M2", startDate: start, endDate: end, participantStatus: .tentative)
        let e3 = CalendarEvent(id: "e3", title: "M3", startDate: start, endDate: end, participantStatus: .pending)

        let placed = engine.layoutEvents([e1, e2, e3], for: activeDay)

        #expect(placed.count == 3)
        #expect(placed.map(\.columnIndex) == [0, 1, 2])
        #expect(placed.allSatisfy { $0.totalColumns == 3 })
        #expect(placed.allSatisfy { $0.overflowCount == 0 })
    }

    @Test("Four overlapping events partition into four columns (columnIndex 0, 1, 2, 3, totalColumns 4)")
    func fourOverlappingEventsPartitionCorrectly() {
        let cal = utcCalendar
        let engine = TimelineLayoutEngine(calendar: cal)
        let activeDay = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 10, minute: 0, second: 0))!
        let start = activeDay
        let end = cal.date(byAdding: .hour, value: 1, to: start)!

        let e1 = CalendarEvent(id: "e1", title: "M1", startDate: start, endDate: end, participantStatus: .accepted, availabilityStatus: .busy)
        let e2 = CalendarEvent(id: "e2", title: "M2", startDate: start, endDate: end, participantStatus: .accepted, availabilityStatus: .free)
        let e3 = CalendarEvent(id: "e3", title: "M3", startDate: start, endDate: end, participantStatus: .tentative)
        let e4 = CalendarEvent(id: "e4", title: "M4", startDate: start, endDate: end, participantStatus: .pending)

        let placed = engine.layoutEvents([e1, e2, e3, e4], for: activeDay)

        #expect(placed.count == 4)
        #expect(placed.map(\.columnIndex) == [0, 1, 2, 3])
        #expect(placed.allSatisfy { $0.totalColumns == 4 })
        #expect(placed.allSatisfy { $0.overflowCount == 0 })
    }

    @Test("Five overlapping events allocate 4 visual columns and assign overflowCount = 1 to the 4th slot")
    func fiveOverlappingEventsEmitOverflowCountOnFourthSlot() {
        let cal = utcCalendar
        let engine = TimelineLayoutEngine(calendar: cal)
        let activeDay = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 10, minute: 0, second: 0))!
        let start = activeDay
        let end = cal.date(byAdding: .hour, value: 1, to: start)!

        // 5 overlapping events with descending precedence
        let e1 = CalendarEvent(id: "e1", title: "Accepted Busy", startDate: start, endDate: end, participantStatus: .accepted, availabilityStatus: .busy)
        let e2 = CalendarEvent(id: "e2", title: "Accepted Free", startDate: start, endDate: end, participantStatus: .accepted, availabilityStatus: .free)
        let e3 = CalendarEvent(id: "e3", title: "Tentative", startDate: start, endDate: end, participantStatus: .tentative)
        let e4 = CalendarEvent(id: "e4", title: "Pending", startDate: start, endDate: end, participantStatus: .pending)
        let e5 = CalendarEvent(id: "e5", title: "Unknown", startDate: start, endDate: end, participantStatus: .unknown)

        let placed = engine.layoutEvents([e5, e4, e3, e2, e1], for: activeDay)

        // Only the top 4 events are placed into visual columns
        #expect(placed.count == 4)
        #expect(placed.map(\.columnIndex) == [0, 1, 2, 3])
        #expect(placed.allSatisfy { $0.totalColumns == 4 })

        // Columns 0, 1, 2 have zero overflow
        #expect(placed[0].id == "e1")
        #expect(placed[0].overflowCount == 0)

        #expect(placed[1].id == "e2")
        #expect(placed[1].overflowCount == 0)

        #expect(placed[2].id == "e3")
        #expect(placed[2].overflowCount == 0)

        // Column 3 has overflowCount = 5 - 4 = 1
        #expect(placed[3].id == "e4")
        #expect(placed[3].overflowCount == 1)
    }

    @Test("Seven overlapping events assign overflowCount = 3 to 4th slot")
    func sevenOverlappingEventsEmitOverflowCountThree() {
        let cal = utcCalendar
        let engine = TimelineLayoutEngine(calendar: cal)
        let activeDay = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 14, minute: 0, second: 0))!
        let start = activeDay
        let end = cal.date(byAdding: .hour, value: 1, to: start)!

        let events = (0..<7).map { i in
            CalendarEvent(
                id: "event-\(i)",
                title: "Overlapping \(i)",
                startDate: start,
                endDate: end,
                participantStatus: i == 0 ? .accepted : (i == 1 ? .tentative : .pending)
            )
        }

        let placed = engine.layoutEvents(events, for: activeDay)

        #expect(placed.count == 4)
        #expect(placed[3].columnIndex == 3)
        #expect(placed[3].overflowCount == 3) // 7 - 4 = 3
    }

    @Test("Disjoint non-overlapping events across the day retain independent full-width columns")
    func disjointEventsRetainIndependentFullWidthColumns() {
        let cal = utcCalendar
        let engine = TimelineLayoutEngine(calendar: cal)
        let activeDay = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 9, minute: 0, second: 0))!

        let morningStart = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 9, minute: 0, second: 0))!
        let morningEnd = cal.date(byAdding: .hour, value: 1, to: morningStart)!
        let morningEvent = CalendarEvent(id: "morning", title: "Daily Standup", startDate: morningStart, endDate: morningEnd)

        let afternoonStart = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 14, minute: 0, second: 0))!
        let afternoonEnd = cal.date(byAdding: .hour, value: 1, to: afternoonStart)!
        let afternoonEvent = CalendarEvent(id: "afternoon", title: "1-on-1", startDate: afternoonStart, endDate: afternoonEnd)

        let placed = engine.layoutEvents([morningEvent, afternoonEvent], for: activeDay)

        #expect(placed.count == 2)
        #expect(placed[0].id == "morning")
        #expect(placed[0].columnIndex == 0)
        #expect(placed[0].totalColumns == 1)

        #expect(placed[1].id == "afternoon")
        #expect(placed[1].columnIndex == 0)
        #expect(placed[1].totalColumns == 1)
    }

    // MARK: - Precedence Rule Tests

    @Test("Precedence Rule 1: Accepted response ranks over tentative, pending, and unknown")
    func precedenceResponseAcceptedOverTentative() {
        let cal = utcCalendar
        let engine = TimelineLayoutEngine(calendar: cal)
        let activeDay = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 10, minute: 0, second: 0))!
        let start = activeDay
        let end = cal.date(byAdding: .hour, value: 1, to: start)!

        let tentative = CalendarEvent(id: "tentative", title: "Tentative Meeting", startDate: start, endDate: end, participantStatus: .tentative)
        let accepted = CalendarEvent(id: "accepted", title: "Accepted Meeting", startDate: start, endDate: end, participantStatus: .accepted)

        let placed = engine.layoutEvents([tentative, accepted], for: activeDay)

        #expect(placed[0].id == "accepted")
        #expect(placed[0].columnIndex == 0)
        #expect(placed[1].id == "tentative")
        #expect(placed[1].columnIndex == 1)
    }

    @Test("Precedence Rule 2: Busy availability ranks over free and tentative availability")
    func precedenceAvailabilityBusyOverFree() {
        let cal = utcCalendar
        let engine = TimelineLayoutEngine(calendar: cal)
        let activeDay = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 10, minute: 0, second: 0))!
        let start = activeDay
        let end = cal.date(byAdding: .hour, value: 1, to: start)!

        let free = CalendarEvent(id: "free", title: "Hold Slot", startDate: start, endDate: end, participantStatus: .accepted, availabilityStatus: .free)
        let busy = CalendarEvent(id: "busy", title: "Customer Call", startDate: start, endDate: end, participantStatus: .accepted, availabilityStatus: .busy)

        let placed = engine.layoutEvents([free, busy], for: activeDay)

        #expect(placed[0].id == "busy")
        #expect(placed[0].columnIndex == 0)
        #expect(placed[1].id == "free")
        #expect(placed[1].columnIndex == 1)
    }

    @Test("Precedence Rule 3: Organizer role ranks over attendee role")
    func precedenceRoleOrganizerOverAttendee() {
        let cal = utcCalendar
        let engine = TimelineLayoutEngine(calendar: cal)
        let activeDay = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 10, minute: 0, second: 0))!
        let start = activeDay
        let end = cal.date(byAdding: .hour, value: 1, to: start)!

        let attendee = CalendarEvent(id: "attendee", title: "All Hands", startDate: start, endDate: end, participantStatus: .accepted, availabilityStatus: .busy, isOrganizer: false)
        let organizer = CalendarEvent(id: "organizer", title: "Architecture Review", startDate: start, endDate: end, participantStatus: .accepted, availabilityStatus: .busy, isOrganizer: true)

        let placed = engine.layoutEvents([attendee, organizer], for: activeDay)

        #expect(placed[0].id == "organizer")
        #expect(placed[0].columnIndex == 0)
        #expect(placed[1].id == "attendee")
        #expect(placed[1].columnIndex == 1)
    }

    @Test("Precedence Rule 4: Earlier start time ranks over later start time")
    func precedenceStartTimeEarlierOverLater() {
        let cal = utcCalendar
        let engine = TimelineLayoutEngine(calendar: cal)
        let activeDay = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 10, minute: 0, second: 0))!

        let startEarly = activeDay
        let endEarly = cal.date(byAdding: .hour, value: 2, to: startEarly)!

        let startLater = cal.date(byAdding: .minute, value: 30, to: startEarly)!
        let endLater = cal.date(byAdding: .hour, value: 1, to: startLater)!

        let laterEvent = CalendarEvent(id: "later", title: "Later Meeting", startDate: startLater, endDate: endLater, participantStatus: .accepted)
        let earlyEvent = CalendarEvent(id: "early", title: "Early Meeting", startDate: startEarly, endDate: endEarly, participantStatus: .accepted)

        let placed = engine.layoutEvents([laterEvent, earlyEvent], for: activeDay)

        #expect(placed[0].id == "early")
        #expect(placed[0].columnIndex == 0)
        #expect(placed[1].id == "later")
        #expect(placed[1].columnIndex == 1)
    }

    @Test("Precedence Rule 5: Shorter duration ranks over longer duration when other attributes match")
    func precedenceDurationShorterOverLonger() {
        let cal = utcCalendar
        let engine = TimelineLayoutEngine(calendar: cal)
        let activeDay = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 10, minute: 0, second: 0))!
        let start = activeDay

        let longEnd = cal.date(byAdding: .hour, value: 2, to: start)!
        let shortEnd = cal.date(byAdding: .minute, value: 30, to: start)!

        let longEvent = CalendarEvent(id: "long", title: "2hr Workshop", startDate: start, endDate: longEnd, participantStatus: .accepted)
        let shortEvent = CalendarEvent(id: "short", title: "30min Standup", startDate: start, endDate: shortEnd, participantStatus: .accepted)

        let placed = engine.layoutEvents([longEvent, shortEvent], for: activeDay)

        #expect(placed[0].id == "short")
        #expect(placed[0].columnIndex == 0)
        #expect(placed[1].id == "long")
        #expect(placed[1].columnIndex == 1)
    }
}

@Suite("TimelineLayoutEngine Invariants & Defensive Bounds")
struct TimelineLayoutInvariantsTests {

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    @Test("Layout invariants hold across diverse and extreme calendar event configurations")
    func layoutInvariantsAcrossDiverseEvents() {
        let cal = utcCalendar
        let engine = TimelineLayoutEngine(calendar: cal)
        let activeDay = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 12, minute: 0, second: 0))!

        // Generate 15 varied events (concurrent, short, long, overnight, zero-length)
        var events: [CalendarEvent] = []
        for i in 0..<15 {
            let startHour = 8 + (i % 12)
            let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: startHour, minute: (i * 7) % 60, second: 0))!
            let durationSeconds = Double(((i * 13) % 90) * 60)
            let end = start.addingTimeInterval(durationSeconds)

            events.append(
                CalendarEvent(
                    id: "evt-\(i)",
                    title: "Event \(i)",
                    startDate: start,
                    endDate: end,
                    participantStatus: ParticipantStatus.allCases[i % ParticipantStatus.allCases.count],
                    availabilityStatus: AvailabilityStatus.allCases[i % AvailabilityStatus.allCases.count],
                    isOrganizer: i.isMultiple(of: 2)
                )
            )
        }

        let placed = engine.layoutEvents(events, for: activeDay)

        for item in placed {
            // Invariant: Column index strictly in 0..<4
            #expect(item.columnIndex >= 0)
            #expect(item.columnIndex < 4)

            // Invariant: Total columns in 1...4
            #expect(item.totalColumns >= 1)
            #expect(item.totalColumns <= 4)
            #expect(item.columnIndex < item.totalColumns)

            // Invariant: Minimum visual height 18 pt enforced
            #expect(item.height >= 18.0)

            // Invariant: Non-negative vertical coordinates
            #expect(item.yOffset >= 0.0)

            // Invariant: Overflow count is non-negative and restricted to column 3
            #expect(item.overflowCount >= 0)
            if item.overflowCount > 0 {
                #expect(item.columnIndex == 3)
            }
        }
    }
}
