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

    private final class SpyEventStore: EKEventStore, @unchecked Sendable {
        private let lock = NSLock()
        private var _refreshSourcesCount = 0

        var refreshSourcesCount: Int {
            lock.withLock { _refreshSourcesCount }
        }

        override func refreshSourcesIfNecessary() {
            lock.withLock { _refreshSourcesCount += 1 }
        }
    }

    private actor ChangeTracker {
        private(set) var count = 0

        func record() {
            count += 1
        }

        func waitForCount(_ target: Int, maxAttempts: Int = 100) async -> Bool {
            for _ in 0..<maxAttempts {
                if count >= target { return true }
                try? await Task.sleep(for: .milliseconds(20))
            }
            return count >= target
        }
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

    // MARK: - Phase 2: refreshSources & storeChanges Behavioral Contracts

    @Test("MockCalendarService refreshSources tracks invocations and handles success")
    func mockRefreshSourcesSuccessAndCallTracking() async throws {
        let mock = MockCalendarService()
        #expect(mock.refreshSourcesCallCount == 0)

        try await mock.refreshSources()
        #expect(mock.refreshSourcesCallCount == 1)

        try await mock.refreshSources()
        #expect(mock.refreshSourcesCallCount == 2)
    }

    @Test("MockCalendarService refreshSources propagates configured errors and increments call count")
    func mockRefreshSourcesErrorPropagation() async {
        let expectedError = TestError(message: "CalDAV server unreachable")
        let mock = MockCalendarService(refreshSourcesResult: .failure(expectedError))

        #expect(mock.refreshSourcesCallCount == 0)

        await #expect(throws: TestError.self) {
            try await mock.refreshSources()
        }

        #expect(mock.refreshSourcesCallCount == 1)

        mock.setRefreshSourcesResult(.success(()))
        do {
            try await mock.refreshSources()
            #expect(mock.refreshSourcesCallCount == 2)
        } catch {
            Issue.record("Expected refreshSources to succeed after clearing error")
        }
    }

    @Test("EventKitCalendarService refreshSources triggers refreshSourcesIfNecessary on eventStore")
    func eventKitRefreshSourcesDelegatesToStore() async throws {
        let spyStore = SpyEventStore()
        let service = EventKitCalendarService(eventStore: spyStore)

        #expect(spyStore.refreshSourcesCount == 0)
        try await service.refreshSources()
        #expect(spyStore.refreshSourcesCount == 1)
    }

    @Test("MockCalendarService storeChanges stream receives emitted change events asynchronously")
    func mockStoreChangesReceivesEmittedEvents() async throws {
        let mock = MockCalendarService()
        let tracker = ChangeTracker()

        let stream = mock.storeChanges
        let task = Task {
            for await _ in stream {
                await tracker.record()
            }
        }

        #expect(await tracker.count == 0)

        mock.emitStoreChange()
        let firstReached = await tracker.waitForCount(1)
        #expect(firstReached)
        #expect(await tracker.count == 1)

        mock.emitStoreChange()
        mock.emitStoreChange()
        let allReached = await tracker.waitForCount(3)
        #expect(allReached)
        #expect(await tracker.count == 3)

        task.cancel()
    }

    @Test("MockCalendarService storeChanges delivers change events to multiple concurrent subscribers")
    func mockStoreChangesMultipleSubscribers() async throws {
        let mock = MockCalendarService()
        let trackerA = ChangeTracker()
        let trackerB = ChangeTracker()

        let taskA = Task {
            for await _ in mock.storeChanges {
                await trackerA.record()
            }
        }

        let taskB = Task {
            for await _ in mock.storeChanges {
                await trackerB.record()
            }
        }

        // Wait for both streams to register continuations
        for _ in 0..<50 {
            if mock.activeStoreChangeSubscriberCount == 2 { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(mock.activeStoreChangeSubscriberCount == 2)

        mock.emitStoreChange()
        let reachedA = await trackerA.waitForCount(1)
        let reachedB = await trackerB.waitForCount(1)

        #expect(reachedA)
        #expect(reachedB)
        #expect(await trackerA.count == 1)
        #expect(await trackerB.count == 1)

        taskA.cancel()
        taskB.cancel()
    }

    @Test("MockCalendarService storeChanges stream cleans up continuation when consumer task cancels")
    func mockStoreChangesCleansUpOnCancellation() async throws {
        let mock = MockCalendarService()
        #expect(mock.activeStoreChangeSubscriberCount == 0)

        let task = Task {
            for await _ in mock.storeChanges {
                // Keep stream active
            }
        }

        // Allow task to initialize stream and register continuation
        for _ in 0..<50 {
            if mock.activeStoreChangeSubscriberCount == 1 { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(mock.activeStoreChangeSubscriberCount == 1)

        task.cancel()

        // Wait for cancellation handler to unregister continuation
        for _ in 0..<50 {
            if mock.activeStoreChangeSubscriberCount == 0 { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(mock.activeStoreChangeSubscriberCount == 0)
    }

    @Test("EventKitCalendarService storeChanges observes system notification and delivers change events")
    func eventKitStoreChangesObservesNotification() async throws {
        let notificationCenter = NotificationCenter()
        let service = EventKitCalendarService(notificationCenter: notificationCenter)
        let tracker = ChangeTracker()

        let task = Task {
            for await _ in service.storeChanges {
                await tracker.record()
            }
        }

        // Wait for async stream observation task to connect and process first notification
        for _ in 0..<30 {
            notificationCenter.post(name: .EKEventStoreChanged, object: nil)
            if await tracker.waitForCount(1, maxAttempts: 3) { break }
            try? await Task.sleep(for: .milliseconds(20))
        }

        let firstReached = await tracker.waitForCount(1)
        #expect(firstReached)
        let currentCount = await tracker.count
        #expect(currentCount >= 1)

        notificationCenter.post(name: .EKEventStoreChanged, object: nil)
        let secondReached = await tracker.waitForCount(currentCount + 1)
        #expect(secondReached)
        #expect(await tracker.count == currentCount + 1)

        task.cancel()
    }

    @Test("EventKitCalendarService storeChanges cleans up task and continuation on task cancellation")
    func eventKitStoreChangesCancellationTermination() async throws {
        let notificationCenter = NotificationCenter()
        let service = EventKitCalendarService(notificationCenter: notificationCenter)
        let tracker = ChangeTracker()

        let task = Task {
            for await _ in service.storeChanges {
                await tracker.record()
            }
        }

        for _ in 0..<30 {
            notificationCenter.post(name: .EKEventStoreChanged, object: nil)
            if await tracker.waitForCount(1, maxAttempts: 3) { break }
            try? await Task.sleep(for: .milliseconds(20))
        }

        let firstReached = await tracker.waitForCount(1)
        #expect(firstReached)
        let countBeforeCancel = await tracker.count
        #expect(countBeforeCancel >= 1)

        task.cancel()
        _ = await task.result

        // Posting after cancellation should not increment tracker
        notificationCenter.post(name: .EKEventStoreChanged, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await tracker.count == countBeforeCancel)
    }

    @Test("CalendarService concurrent operations maintain safety across queries, refreshes, and stream notifications")
    func concurrentQueriesRefreshesAndStreamEmissions() async throws {
        let mock = MockCalendarService()
        let tracker = ChangeTracker()
        let iterations = 30

        let observationTask = Task {
            for await _ in mock.storeChanges {
                await tracker.record()
            }
        }

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    let testDate = Date(timeIntervalSince1970: Double(i * 100))
                    _ = try? await mock.events(for: testDate)
                    _ = try? await mock.refreshSources()
                    mock.emitStoreChange()
                }
            }
        }

        let reached = await tracker.waitForCount(iterations)
        #expect(reached)
        #expect(await tracker.count >= iterations)
        #expect(mock.refreshSourcesCallCount == iterations)
        #expect(mock.requestedDates.count == iterations)

        observationTask.cancel()
    }
}
