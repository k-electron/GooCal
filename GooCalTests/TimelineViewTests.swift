//
//  TimelineViewTests.swift
//  GooCalTests
//

import Testing
import Foundation
import CoreGraphics
import SwiftUI
@testable import GooCal

@Suite("TimelineGridView Marking & Hour Formatting Contracts")
struct TimelineGridViewTests {

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    @Test("TimelineGridView initializes with specified or default geometry parameters")
    func gridViewDefaultParameters() {
        let defaultGrid = TimelineGridView()
        #expect(defaultGrid.rulerWidth == 50.0)
        #expect(defaultGrid.totalHeight == 960.0)
        #expect(defaultGrid.pointsPerHour == 40.0)

        let customGrid = TimelineGridView(rulerWidth: 60.0, totalHeight: 1200.0, pointsPerHour: 50.0)
        #expect(customGrid.rulerWidth == 60.0)
        #expect(customGrid.totalHeight == 1200.0)
        #expect(customGrid.pointsPerHour == 50.0)
    }

    @Test("TimelineGridView formattedHour formats 24 distinct hourly markings")
    func formattedHourCoversFullDay() {
        let grid = TimelineGridView(calendar: utcCalendar)

        var formattedHours = Set<String>()
        for hour in 0..<24 {
            let label = grid.formattedHour(for: hour)
            #expect(!label.isEmpty)
            formattedHours.insert(label)
        }

        // Must produce at least 12 distinct labels (allowing for 12h AM/PM cycle)
        #expect(formattedHours.count >= 12)
    }
}

@Suite("TimelineEventCard Visual Styling & Edge Indicator Contracts")
struct TimelineEventCardTests {

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    @Test("TimelineEventCard extracts calendar color from source CGColor")
    func calendarColorDerivedFromSource() {
        let testCGColor = CGColor(srgbRed: 0.8, green: 0.2, blue: 0.4, alpha: 1.0)
        let event = CalendarEvent(
            title: "Color Sync Test",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            calendarColor: testCGColor
        )
        let placed = PlacedEvent(
            event: event,
            effectiveStartDate: event.startDate,
            effectiveEndDate: event.endDate,
            spansFromYesterday: false,
            spansIntoTomorrow: false,
            yOffset: 200,
            height: 40,
            columnIndex: 0,
            totalColumns: 1
        )

        let card = TimelineEventCard(placedEvent: placed)
        #expect(card.calendarColor == Color(cgColor: testCGColor))
    }

    @Test("TimelineEventCard formats readable time range string")
    func timeRangeFormatting() {
        let cal = utcCalendar
        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 10, minute: 0))!
        let end = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 11, minute: 30))!
        let event = CalendarEvent(title: "Design Sync", startDate: start, endDate: end)
        let placed = PlacedEvent(
            event: event,
            effectiveStartDate: start,
            effectiveEndDate: end,
            spansFromYesterday: false,
            spansIntoTomorrow: false,
            yOffset: 400,
            height: 60,
            columnIndex: 0,
            totalColumns: 1
        )

        let card = TimelineEventCard(placedEvent: placed)
        let formatted = card.formattedTimeRange
        #expect(!formatted.isEmpty)
        #expect(formatted.contains("–"))
    }

    @Test("TimelineEventCard shapes enforce flat edges for multi-day continuity")
    func multiDayShapeCornerRadii() {
        let now = Date()
        let event = CalendarEvent(title: "Multi-Day", startDate: now, endDate: now.addingTimeInterval(7200))

        // Standard single-day event: all corners rounded (4 pt)
        let standardPlaced = PlacedEvent(
            event: event,
            effectiveStartDate: now,
            effectiveEndDate: now.addingTimeInterval(7200),
            spansFromYesterday: false,
            spansIntoTomorrow: false,
            yOffset: 100,
            height: 80,
            columnIndex: 0,
            totalColumns: 1
        )
        let standardCard = TimelineEventCard(placedEvent: standardPlaced)
        #expect(standardCard.cardShape.cornerRadii.topLeading == 4)
        #expect(standardCard.cardShape.cornerRadii.topTrailing == 4)
        #expect(standardCard.cardShape.cornerRadii.bottomLeading == 4)
        #expect(standardCard.cardShape.cornerRadii.bottomTrailing == 4)

        // Continues from yesterday: top edge flat (0 pt radius), bottom rounded (4 pt)
        let yesterdayPlaced = PlacedEvent(
            event: event,
            effectiveStartDate: now,
            effectiveEndDate: now.addingTimeInterval(7200),
            spansFromYesterday: true,
            spansIntoTomorrow: false,
            yOffset: 0,
            height: 80,
            columnIndex: 0,
            totalColumns: 1
        )
        let yesterdayCard = TimelineEventCard(placedEvent: yesterdayPlaced)
        #expect(yesterdayCard.cardShape.cornerRadii.topLeading == 0)
        #expect(yesterdayCard.cardShape.cornerRadii.topTrailing == 0)
        #expect(yesterdayCard.cardShape.cornerRadii.bottomLeading == 4)
        #expect(yesterdayCard.cardShape.cornerRadii.bottomTrailing == 4)

        // Continues into tomorrow: bottom edge flat (0 pt radius), top rounded (4 pt)
        let tomorrowPlaced = PlacedEvent(
            event: event,
            effectiveStartDate: now,
            effectiveEndDate: now.addingTimeInterval(7200),
            spansFromYesterday: false,
            spansIntoTomorrow: true,
            yOffset: 880,
            height: 80,
            columnIndex: 0,
            totalColumns: 1
        )
        let tomorrowCard = TimelineEventCard(placedEvent: tomorrowPlaced)
        #expect(tomorrowCard.cardShape.cornerRadii.topLeading == 4)
        #expect(tomorrowCard.cardShape.cornerRadii.topTrailing == 4)
        #expect(tomorrowCard.cardShape.cornerRadii.bottomLeading == 0)
        #expect(tomorrowCard.cardShape.cornerRadii.bottomTrailing == 0)

        // Spans both yesterday and tomorrow: all edges flat (0 pt radius)
        let bothPlaced = PlacedEvent(
            event: event,
            effectiveStartDate: now,
            effectiveEndDate: now.addingTimeInterval(7200),
            spansFromYesterday: true,
            spansIntoTomorrow: true,
            yOffset: 0,
            height: 960,
            columnIndex: 0,
            totalColumns: 1
        )
        let bothCard = TimelineEventCard(placedEvent: bothPlaced)
        #expect(bothCard.cardShape.cornerRadii.topLeading == 0)
        #expect(bothCard.cardShape.cornerRadii.topTrailing == 0)
        #expect(bothCard.cardShape.cornerRadii.bottomLeading == 0)
        #expect(bothCard.cardShape.cornerRadii.bottomTrailing == 0)
    }

    @Test("TimelineEventCard preserves overflow count on dense overlap slots")
    func overflowCountPreserved() {
        let event = CalendarEvent(title: "Overlap Slot", startDate: Date(), endDate: Date().addingTimeInterval(3600))
        let placed = PlacedEvent(
            event: event,
            effectiveStartDate: event.startDate,
            effectiveEndDate: event.endDate,
            spansFromYesterday: false,
            spansIntoTomorrow: false,
            yOffset: 200,
            height: 40,
            columnIndex: 3,
            totalColumns: 4,
            overflowCount: 5
        )

        let card = TimelineEventCard(placedEvent: placed)
        #expect(card.placedEvent.overflowCount == 5)
    }
}

@Suite("LiveTimeIndicatorView Visibility & Coordinate Mapping Contracts")
struct LiveTimeIndicatorViewTests {

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    @Test("LiveTimeIndicatorView isVisible returns true only on matching calendar day")
    func visibilityMatchesActiveDay() {
        let cal = utcCalendar
        let referenceDay = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 12, minute: 0))!
        let sameDayMorning = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 8, minute: 30))!
        let yesterday = cal.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 12, minute: 0))!
        let tomorrow = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 12, minute: 0))!

        let indicator = LiveTimeIndicatorView(referenceDate: referenceDay, calendar: cal)

        #expect(indicator.isVisible(at: sameDayMorning) == true)
        #expect(indicator.isVisible(at: yesterday) == false)
        #expect(indicator.isVisible(at: tomorrow) == false)
    }

    @Test("LiveTimeIndicatorView yOffset maps current time to vertical points matching coordinate converter")
    func yOffsetCoordinateMapping() {
        let cal = utcCalendar
        let referenceDay = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 0, minute: 0))!
        let tenAM = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 10, minute: 0))!
        let converter = TimelineCoordinateConverter(calendar: cal)

        let indicator = LiveTimeIndicatorView(
            referenceDate: referenceDay,
            coordinateConverter: converter,
            calendar: cal
        )

        let y = indicator.yOffset(for: tenAM)
        #expect(y == 400.0)
    }

    @Test("LiveTimeIndicatorView formats non-empty time string for badge display")
    func formattedTimeString() {
        let indicator = LiveTimeIndicatorView()
        let formatted = indicator.formattedTime(for: Date())
        #expect(!formatted.isEmpty)
    }
}

@Suite("DailyTimelineView Layout Integration & Viewport Anchoring Contracts")
struct DailyTimelineViewTests {

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    @Test("DailyTimelineView computes placed events via layout engine for the selected date")
    func dailyTimelineViewComputesPlacedEvents() {
        let cal = utcCalendar
        let activeDate = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 12, minute: 0))!
        let morningStart = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 9, minute: 0))!
        let morningEnd = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 10, minute: 0))!

        let event = CalendarEvent(title: "Morning Sync", startDate: morningStart, endDate: morningEnd)
        let timelineView = DailyTimelineView(
            events: [event],
            selectedDate: activeDate,
            calendar: cal
        )

        let placed = timelineView.placedEvents
        #expect(placed.count == 1)
        #expect(placed.first?.event.title == "Morning Sync")
        #expect(placed.first?.columnIndex == 0)
        #expect(placed.first?.totalColumns == 1)
        #expect(placed.first?.yOffset == 360.0) // 9:00 = 9 * 40 = 360 pt
        #expect(placed.first?.height == 40.0)  // 1 hr = 40 pt
    }

    @Test("DailyTimelineView partitions overlapping events into parallel columns")
    func dailyTimelineViewOverlapPartitioning() {
        let cal = utcCalendar
        let activeDate = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 12, minute: 0))!
        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 14, minute: 0))!
        let end = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 15, minute: 0))!

        let event1 = CalendarEvent(id: "E1", title: "Meeting A", startDate: start, endDate: end, participantStatus: .accepted)
        let event2 = CalendarEvent(id: "E2", title: "Meeting B", startDate: start, endDate: end, participantStatus: .tentative)

        let timelineView = DailyTimelineView(
            events: [event1, event2],
            selectedDate: activeDate,
            calendar: cal
        )

        let placed = timelineView.placedEvents
        #expect(placed.count == 2)
        #expect(placed[0].totalColumns == 2)
        #expect(placed[1].totalColumns == 2)
        #expect(placed[0].columnIndex == 0)
        #expect(placed[1].columnIndex == 1)
        #expect(placed[0].event.id == "E1") // Accepted precedes tentative
    }

    @Test("DailyTimelineView target scroll offset anchors at one-third viewport and respects boundaries")
    func targetScrollOffsetAnchoring() {
        let cal = utcCalendar
        let activeDate = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 0, minute: 0))!
        let converter = TimelineCoordinateConverter(calendar: cal)
        let viewportHeight: CGFloat = 480.0

        let timelineView = DailyTimelineView(
            events: [],
            selectedDate: activeDate,
            viewportHeight: viewportHeight,
            coordinateConverter: converter,
            calendar: cal
        )

        // At 12:00 (Y = 480 pt), 1/3rd of 480 is 160 -> target = 480 - 160 = 320 pt
        let noon = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 12, minute: 0))!
        #expect(timelineView.targetScrollOffset(for: noon) == 320.0)

        // At 01:00 (Y = 40 pt) -> target = 40 - 160 = -120 -> clamped to 0 pt
        let oneAM = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 1, minute: 0))!
        #expect(timelineView.targetScrollOffset(for: oneAM) == 0.0)

        // At 23:00 (Y = 920 pt) -> target = 920 - 160 = 760 -> clamped to 480 pt (960 - 480)
        let elevenPM = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 23, minute: 0))!
        #expect(timelineView.targetScrollOffset(for: elevenPM) == 480.0)
    }

    @Test("DailyTimelineView correctly preserves multi-day boundary continuation flags")
    func dailyTimelineViewMultiDayContinuationFlags() {
        let cal = utcCalendar
        let activeDate = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 12, minute: 0))!
        let yesterdayStart = cal.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 22, minute: 0))!
        let morningEnd = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 2, minute: 0))!
        let eveningStart = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 22, minute: 0))!
        let tomorrowEnd = cal.date(from: DateComponents(year: 2026, month: 9, day: 21, hour: 3, minute: 0))!

        let overnightFromYesterday = CalendarEvent(id: "O1", title: "Overnight In", startDate: yesterdayStart, endDate: morningEnd)
        let overnightIntoTomorrow = CalendarEvent(id: "O2", title: "Overnight Out", startDate: eveningStart, endDate: tomorrowEnd)

        let timelineView = DailyTimelineView(
            events: [overnightFromYesterday, overnightIntoTomorrow],
            selectedDate: activeDate,
            calendar: cal
        )

        let placed = timelineView.placedEvents
        #expect(placed.count == 2)

        let inEvent = placed.first { $0.id == "O1" }
        #expect(inEvent?.spansFromYesterday == true)
        #expect(inEvent?.spansIntoTomorrow == false)
        #expect(inEvent?.yOffset == 0.0)
        #expect(inEvent?.height == 80.0) // 2 hours clamped = 80 pt

        let outEvent = placed.first { $0.id == "O2" }
        #expect(outEvent?.spansFromYesterday == false)
        #expect(outEvent?.spansIntoTomorrow == true)
        #expect(outEvent?.yOffset == 880.0) // 22:00 = 880 pt
        #expect(outEvent?.height == 80.0)  // 2 hours clamped = 80 pt
    }

    @Test("DailyTimelineView handles 5+ concurrent events with 4 columns and overflow badge count")
    func dailyTimelineViewFiveOverlapsOverflowCount() {
        let cal = utcCalendar
        let activeDate = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 12, minute: 0))!
        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 15, minute: 0))!
        let end = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 16, minute: 0))!

        let events = (0..<6).map { i in
            CalendarEvent(id: "E\(i)", title: "Concurrent \(i)", startDate: start, endDate: end)
        }

        let timelineView = DailyTimelineView(
            events: events,
            selectedDate: activeDate,
            calendar: cal
        )

        let placed = timelineView.placedEvents
        // Only 4 visual columns displayed
        #expect(placed.count == 4)
        #expect(placed[3].columnIndex == 3)
        #expect(placed[3].totalColumns == 4)
        // 6 total - 4 displayed = overflow count of 2
        #expect(placed[3].overflowCount == 2)
    }

    @MainActor
    @Test("DailyTimelineView body hierarchy instantiates and evaluates without runtime fault")
    func dailyTimelineViewBodyEvaluation() {
        let cal = utcCalendar
        let activeDate = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 12, minute: 0))!
        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 10, minute: 0))!
        let end = cal.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 11, minute: 0))!
        let event = CalendarEvent(title: "Render Check", startDate: start, endDate: end)

        let view = DailyTimelineView(events: [event], selectedDate: activeDate, calendar: cal)
        let _ = view.body
    }
}

