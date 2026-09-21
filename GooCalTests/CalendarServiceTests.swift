//
//  CalendarServiceTests.swift
//  GooCalTests
//

import Testing
import Foundation
import EventKit
@testable import GooCal

@Suite("CalendarServiceManaging Behavioral Contracts & Error Propagation")
struct CalendarServiceTests {

    private struct TestError: Error, Equatable {
        let message: String
    }

    @Test("Mock service reports configured authorization status across all lifecycle phases")
    func authorizationStatusReflectsInjectedState() {
        for status in CalendarAuthorizationStatus.allCases {
            let mock = MockCalendarService(authorizationStatus: status)
            #expect(mock.authorizationStatus() == status)
        }
    }

    @Test("Successful access request transitions authorization status to authorized and tracks invocations")
    func requestAccessSuccessUpdatesAuthorizationAndCount() async throws {
        let mock = MockCalendarService(
            authorizationStatus: .notDetermined,
            requestAccessResult: .success(true)
        )

        #expect(mock.authorizationStatus() == .notDetermined)
        #expect(mock.requestAccessCallCount == 0)

        let granted = try await mock.requestAccess()

        #expect(granted)
        #expect(mock.requestAccessCallCount == 1)
        #expect(mock.authorizationStatus() == .authorized)
    }

    @Test("Denied access request preserves non-authorized status and returns false")
    func requestAccessDeniedPreservesStatus() async throws {
        let mock = MockCalendarService(
            authorizationStatus: .notDetermined,
            requestAccessResult: .success(false)
        )

        let granted = try await mock.requestAccess()

        #expect(!granted)
        #expect(mock.requestAccessCallCount == 1)
        #expect(mock.authorizationStatus() == .notDetermined)
    }

    @Test("Access request error propagation surfaces underlying system or security failures")
    func requestAccessErrorPropagates() async {
        let expectedError = TestError(message: "System TCC daemon communication fault")
        let mock = MockCalendarService(
            authorizationStatus: .notDetermined,
            requestAccessResult: .failure(expectedError)
        )

        await #expect(throws: TestError.self) {
            try await mock.requestAccess()
        }

        #expect(mock.requestAccessCallCount == 1)
    }

    @Test("Events query returns injected event fixtures and records target query date")
    func eventsQueryReturnsFixturesAndRecordsDate() async throws {
        let now = Date()
        let sampleEvent = CalendarEvent(
            id: "sync-1",
            title: "Sprint Planning",
            startDate: now,
            endDate: now.addingTimeInterval(3600),
            participantStatus: .accepted,
            availabilityStatus: .busy,
            isOrganizer: true
        )

        let mock = MockCalendarService(eventsResult: .success([sampleEvent]))

        let targetDate = Date(timeIntervalSince1970: 1_700_000_000)
        let results = try await mock.events(for: targetDate)

        #expect(results.count == 1)
        #expect(results.first == sampleEvent)
        #expect(mock.requestedDates == [targetDate])
    }

    @Test("Events query failure propagates error directly to caller")
    func eventsQueryPropagatesErrors() async {
        let expectedError = TestError(message: "Calendar database is locked")
        let mock = MockCalendarService(eventsResult: .failure(expectedError))

        let targetDate = Date()
        await #expect(throws: TestError.self) {
            try await mock.events(for: targetDate)
        }

        #expect(mock.requestedDates == [targetDate])
    }

    @Test("MockCalendarService safely handles concurrent access across detached asynchronous tasks")
    func concurrentAccessMaintainsDataIntegrity() async throws {
        let mock = MockCalendarService(
            authorizationStatus: .authorized,
            requestAccessResult: .success(true),
            eventsResult: .success([])
        )

        let iterations = 50
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<iterations {
                group.addTask {
                    let testDate = Date(timeIntervalSince1970: Double(index * 100))
                    _ = try? await mock.events(for: testDate)
                    _ = try? await mock.requestAccess()
                    _ = mock.authorizationStatus()
                }
            }
        }

        #expect(mock.requestAccessCallCount == iterations)
        #expect(mock.requestedDates.count == iterations)
    }

    @Test("EventKit mapping converts EKEvent properties to CalendarEvent domain model with color and status defaults")
    func eventKitMappingNormalizesProperties() {
        let store = EKEventStore()
        let ekEvent = EKEvent(eventStore: store)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(3600)

        ekEvent.title = "Weekly Review"
        ekEvent.startDate = start
        ekEvent.endDate = end
        ekEvent.isAllDay = false

        let mapped = EventKitCalendarService.map(ekEvent: ekEvent)

        #expect(mapped.title == "Weekly Review")
        #expect(mapped.startDate == start)
        #expect(mapped.endDate == end)
        #expect(!mapped.isAllDay)
        #expect(mapped.availabilityStatus == .busy)
        #expect(mapped.calendarColor == EventKitCalendarService.defaultCalendarColor)
        #expect(mapped.isOrganizer)
        #expect(mapped.participantStatus == .accepted)
    }

    @Test("EventKit availability mapping accurately converts each EKEventAvailability status")
    func availabilityStatusMappingConvertsAllVariants() {
        let testCases: [(EKEventAvailability, AvailabilityStatus)] = [
            (.busy, .busy),
            (.free, .free),
            (.tentative, .tentative),
            (.unavailable, .unavailable),
            (.notSupported, .busy)
        ]

        for (ekStatus, expectedStatus) in testCases {
            let mapped = EventKitCalendarService.mapAvailability(ekStatus)
            #expect(mapped == expectedStatus)
        }
    }

    @Test("EventKit participant status mapping accurately converts each EKParticipantStatus")
    func participantStatusMappingConvertsAllVariants() {
        let testCases: [(EKParticipantStatus, ParticipantStatus)] = [
            (.accepted, .accepted),
            (.tentative, .tentative),
            (.pending, .pending),
            (.declined, .declined),
            (.unknown, .unknown),
            (.delegated, .unknown),
            (.completed, .unknown),
            (.inProcess, .unknown)
        ]

        for (ekStatus, expectedStatus) in testCases {
            let mapped = EventKitCalendarService.mapParticipantStatus(ekStatus)
            #expect(mapped == expectedStatus)
        }
    }

    @Test("isCurrentUserForScheduling returns false when no attendees or organizer are configured")
    func isCurrentUserForSchedulingWithoutAttendeesOrOrganizer() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        #expect(!event.isCurrentUserForScheduling)
    }
}
