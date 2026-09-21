//
//  CalendarEventTests.swift
//  GooCalTests
//

import Testing
import Foundation
import CoreGraphics
@testable import GooCal

@Suite("CalendarEvent Model Invariants & Behavioral Contracts")
struct CalendarEventTests {

    @Test("Inverted date range is clamped to start date, enforcing non-negative duration invariant")
    func invertedDateRangeEnforcesNonNegativeDuration() {
        let referenceStart = Date(timeIntervalSince1970: 1_700_000_000)
        let invertedEnd = referenceStart.addingTimeInterval(-3600) // 1 hour prior

        let event = CalendarEvent(
            title: "Out of order meeting",
            startDate: referenceStart,
            endDate: invertedEnd
        )

        #expect(event.endDate == referenceStart)
        #expect(event.duration == 0)
    }

    @Test("Duration accurately computes elapsed seconds between start and end timestamps")
    func durationComputesElapsedSeconds() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let halfHourLater = start.addingTimeInterval(1800)
        let twoHoursLater = start.addingTimeInterval(7200)

        let halfHourEvent = CalendarEvent(title: "Quick Sync", startDate: start, endDate: halfHourLater)
        let twoHourEvent = CalendarEvent(title: "Architecture Review", startDate: start, endDate: twoHoursLater)

        #expect(halfHourEvent.duration == 1800)
        #expect(twoHourEvent.duration == 7200)
    }

    @Test("Value equality respects identical attributes including CGColor")
    func equalityEvaluatesAllAttributesIncludingColor() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(3600)
        let blueColor = CGColor(srgbRed: 0.1, green: 0.4, blue: 0.9, alpha: 1.0)
        let redColor = CGColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1.0)

        let event1 = CalendarEvent(
            id: "event-1",
            title: "Design Critique",
            startDate: start,
            endDate: end,
            isAllDay: false,
            calendarColor: blueColor,
            participantStatus: .accepted,
            availabilityStatus: .busy,
            isOrganizer: true
        )

        let event1Duplicate = CalendarEvent(
            id: "event-1",
            title: "Design Critique",
            startDate: start,
            endDate: end,
            isAllDay: false,
            calendarColor: blueColor,
            participantStatus: .accepted,
            availabilityStatus: .busy,
            isOrganizer: true
        )

        let eventWithDifferentColor = CalendarEvent(
            id: "event-1",
            title: "Design Critique",
            startDate: start,
            endDate: end,
            isAllDay: false,
            calendarColor: redColor,
            participantStatus: .accepted,
            availabilityStatus: .busy,
            isOrganizer: true
        )

        let eventWithDifferentStatus = CalendarEvent(
            id: "event-1",
            title: "Design Critique",
            startDate: start,
            endDate: end,
            isAllDay: false,
            calendarColor: blueColor,
            participantStatus: .tentative,
            availabilityStatus: .busy,
            isOrganizer: true
        )

        #expect(event1 == event1Duplicate)
        #expect(event1 != eventWithDifferentColor)
        #expect(event1 != eventWithDifferentStatus)
    }

    @Test("Availability alias matches availabilityStatus property")
    func availabilityAliasReflectsStatus() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(1800)

        for status in AvailabilityStatus.allCases {
            let event = CalendarEvent(
                title: "Availability check",
                startDate: start,
                endDate: end,
                availabilityStatus: status
            )
            #expect(event.availability == status)
            #expect(event.availabilityStatus == status)
        }
    }

    @Test("CalendarEvent transfers deterministically across asynchronous concurrency boundaries")
    func eventTransfersAcrossAsyncConcurrencyBoundary() async {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let original = CalendarEvent(
            id: "async-test",
            title: "Cross-actor event",
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            participantStatus: .accepted,
            availabilityStatus: .busy,
            isOrganizer: false
        )

        let retrieved = await Task.detached { () -> CalendarEvent in
            return original
        }.value

        #expect(retrieved == original)
    }
}
