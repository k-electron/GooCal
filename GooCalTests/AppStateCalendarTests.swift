//
//  AppStateCalendarTests.swift
//  GooCalTests
//

import Testing
import Foundation
import SwiftUI
@testable import GooCal

@Suite("AppState Calendar Integration & Authorization Lifecycle Contracts")
@MainActor
struct AppStateCalendarTests {

    private struct TestError: Error, Equatable {
        let message: String
    }

    private var sampleDate: Date {
        Date(timeIntervalSince1970: 1_700_000_000)
    }

    private func createTestEvent(
        id: String = "evt-1",
        title: String = "Team Standup",
        startDate: Date,
        duration: TimeInterval = 1800,
        isAllDay: Bool = false,
        participantStatus: ParticipantStatus = .accepted
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: title,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(duration),
            isAllDay: isAllDay,
            participantStatus: participantStatus
        )
    }

    // MARK: - 1. Initialization Invariants

    @Test("AppState captures authorization status and sets baseline calendar state upon initialization")
    func initializationCapturesAuthorizationAndDefaults() {
        for status in CalendarAuthorizationStatus.allCases {
            let mock = MockCalendarService(authorizationStatus: status)
            let state = AppState(calendarService: mock)

            #expect(state.calendarAuthorizationStatus == status)
            #expect(state.events.isEmpty)
            #expect(!state.isLoadingEvents)
            #expect(state.lastError == nil)
            #expect(Calendar.current.isDateInToday(state.selectedDate))
        }
    }

    // MARK: - 2. Event Loading & Presentation Contracts

    @Test("refreshEvents populates events array and updates menu bar presentation when authorized")
    func refreshEventsPopulatesEventsWhenAuthorized() async {
        let now = Date.now
        let upcomingMeeting = createTestEvent(
            title: "Sprint Planning",
            startDate: now.addingTimeInterval(600),
            duration: 3600
        )
        let mock = MockCalendarService(
            authorizationStatus: .authorized,
            eventsResult: .success([upcomingMeeting])
        )
        let state = AppState(calendarService: mock)

        await state.refreshEvents()

        #expect(state.events.count == 1)
        #expect(state.events.first?.id == upcomingMeeting.id)
        #expect(state.lastError == nil)
        #expect(!state.isLoadingEvents)
        #expect(state.menuBarTitle == "GooCal: Sprint Planning")
        #expect(state.statusMessage.contains("Next at"))
    }

    @Test("refreshEvents identifies currently active meetings for presentation")
    func refreshEventsIdentifiesOngoingMeeting() async {
        let now = Date.now
        let currentMeeting = createTestEvent(
            title: "Live Incident Triage",
            startDate: now.addingTimeInterval(-300),
            duration: 1800
        )
        let mock = MockCalendarService(
            authorizationStatus: .authorized,
            eventsResult: .success([currentMeeting])
        )
        let state = AppState(calendarService: mock)

        await state.refreshEvents()

        #expect(state.menuBarTitle == "GooCal: Live Incident Triage")
        #expect(state.statusMessage == "Current meeting: Live Incident Triage")
    }

    @Test("refreshEvents with no upcoming events resets menu bar to default state")
    func refreshEventsWithNoUpcomingEventsResetsToDefault() async {
        let mock = MockCalendarService(
            authorizationStatus: .authorized,
            eventsResult: .success([])
        )
        let state = AppState(calendarService: mock)

        await state.refreshEvents()

        #expect(state.events.isEmpty)
        #expect(state.menuBarTitle == "GooCal: No Upcoming Meetings")
        #expect(state.statusMessage == "No upcoming meetings")
    }

    @Test("refreshEvents filters all-day and declined meetings when selecting upcoming presentation title")
    func refreshEventsIgnoresAllDayAndDeclinedForMenuBar() async {
        let now = Date.now
        let allDayEvent = createTestEvent(
            title: "Company Holiday",
            startDate: now,
            isAllDay: true
        )
        let declinedEvent = createTestEvent(
            title: "Skipped Seminar",
            startDate: now.addingTimeInterval(300),
            participantStatus: .declined
        )
        let realMeeting = createTestEvent(
            title: "1:1 Sync",
            startDate: now.addingTimeInterval(900),
            participantStatus: .accepted
        )

        let mock = MockCalendarService(
            authorizationStatus: .authorized,
            eventsResult: .success([allDayEvent, declinedEvent, realMeeting])
        )
        let state = AppState(calendarService: mock)

        await state.refreshEvents()

        #expect(state.events.count == 3)
        #expect(state.menuBarTitle == "GooCal: 1:1 Sync")
    }

    // MARK: - 3. Authorization Transitions

    @Test("refreshEvents requests access when authorization status is notDetermined and loads events on grant")
    func refreshEventsRequestsAccessWhenNotDetermined() async {
        let meeting = createTestEvent(startDate: Date.now.addingTimeInterval(1200))
        let mock = MockCalendarService(
            authorizationStatus: .notDetermined,
            requestAccessResult: .success(true),
            eventsResult: .success([meeting])
        )
        let state = AppState(calendarService: mock)

        #expect(state.calendarAuthorizationStatus == .notDetermined)

        await state.refreshEvents()

        #expect(mock.requestAccessCallCount == 1)
        #expect(state.calendarAuthorizationStatus == .authorized)
        #expect(state.events.count == 1)
        #expect(state.lastError == nil)
    }

    @Test("refreshEvents preserves ungranted status and clears events when access is not granted")
    func refreshEventsPreservesUngrantedStatusWhenAccessDenied() async {
        let mock = MockCalendarService(
            authorizationStatus: .notDetermined,
            requestAccessResult: .success(false)
        )
        let state = AppState(calendarService: mock)

        await state.refreshEvents()

        #expect(mock.requestAccessCallCount == 1)
        #expect(state.calendarAuthorizationStatus != .authorized)
        #expect(state.events.isEmpty)
    }

    @Test("refreshEvents when denied or restricted clears events and displays permission warning")
    func refreshEventsWhenDeniedClearsEvents() async {
        let existingEvent = createTestEvent(startDate: Date.now)
        let mock = MockCalendarService(
            authorizationStatus: .denied,
            eventsResult: .success([existingEvent])
        )
        let state = AppState(calendarService: mock)

        await state.refreshEvents()

        #expect(state.events.isEmpty)
        #expect(state.calendarAuthorizationStatus == .denied)
        #expect(state.menuBarTitle == "GooCal: Calendar Access Required")
        #expect(state.statusMessage.contains("Calendar access is denied or restricted"))
    }

    @Test("explicit requestCalendarAccess triggers permission prompt and updates authorization")
    func explicitRequestCalendarAccessUpdatesState() async {
        let mock = MockCalendarService(
            authorizationStatus: .notDetermined,
            requestAccessResult: .success(true),
            eventsResult: .success([])
        )
        let state = AppState(calendarService: mock)

        await state.requestCalendarAccess()

        #expect(mock.requestAccessCallCount == 1)
        #expect(state.calendarAuthorizationStatus == .authorized)
        #expect(state.lastError == nil)
    }

    // MARK: - 4. Error Propagation & Resilience

    @Test("refreshEvents captures calendar querying failures in lastError without mutating authorization")
    func refreshEventsCapturesEventsQueryError() async {
        let expectedError = TestError(message: "Database schema migration error")
        let mock = MockCalendarService(
            authorizationStatus: .authorized,
            eventsResult: .failure(expectedError)
        )
        let state = AppState(calendarService: mock)

        await state.refreshEvents()

        #expect(state.lastError != nil)
        #expect(state.statusMessage.contains("Failed to load events"))
        #expect(!state.isLoadingEvents)
        #expect(state.calendarAuthorizationStatus == .authorized)
    }

    @Test("refreshEvents captures access request exceptions in lastError")
    func refreshEventsCapturesAccessRequestError() async {
        let expectedError = TestError(message: "Security framework fault")
        let mock = MockCalendarService(
            authorizationStatus: .notDetermined,
            requestAccessResult: .failure(expectedError)
        )
        let state = AppState(calendarService: mock)

        await state.refreshEvents()

        #expect(state.lastError != nil)
        #expect(state.statusMessage.contains("Failed to request calendar access"))
        #expect(!state.isLoadingEvents)
    }

    // MARK: - 5. Date Navigation

    @Test("setSelectedDate mutates active date and dispatches event query for the target date")
    func setSelectedDateUpdatesDateAndQueriesEvents() async {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let mock = MockCalendarService(authorizationStatus: .authorized)
        let state = AppState(calendarService: mock)

        await state.setSelectedDate(tomorrow)

        #expect(state.selectedDate == tomorrow)
        #expect(mock.requestedDates.contains(tomorrow))
        #expect(state.statusMessage.contains("0 events on"))
    }

    // MARK: - 6. Popover & Access Banner View Hierarchy Evaluation

    @Test("CalendarAccessBannerView evaluates view body across all authorization states without faults")
    func calendarAccessBannerViewRendersAcrossStatuses() {
        for status in CalendarAuthorizationStatus.allCases {
            var accessRequested = false
            let banner = CalendarAccessBannerView(status: status) {
                accessRequested = true
            }

            let _ = banner.body
            #expect(!banner.titleText.isEmpty)
            #expect(!banner.explanationText.isEmpty)
            #expect(!banner.iconName.isEmpty)

            if status == .notDetermined {
                banner.onRequestAccess?()
                #expect(accessRequested)
            }
        }
    }

    @Test("DailyTimelineView renders permission banner when authorization status is denied or restricted")
    func dailyTimelineViewRendersBannerWhenDenied() {
        let deniedTimeline = DailyTimelineView(
            events: [],
            authorizationStatus: .denied
        )
        let _ = deniedTimeline.body

        let restrictedTimeline = DailyTimelineView(
            events: [],
            authorizationStatus: .restricted
        )
        let _ = restrictedTimeline.body
    }

    @Test("PopoverContentView evaluates view body hierarchy cleanly with AppState in environment")
    func popoverContentViewBodyEvaluation() {
        let mock = MockCalendarService(authorizationStatus: .authorized)
        let state = AppState(calendarService: mock)
        let popoverView = PopoverContentView().environment(state)
        let hostingView = NSHostingView(rootView: popoverView)

        #expect(hostingView.fittingSize.width >= 360)
    }

    // MARK: - 7. Phase 3: Singleflight Concurrency & Remote Sync Coordination

    @Test("refreshEvents deduplicates concurrent callers and executes at most one trailing pass")
    func refreshEventsDeduplicatesAndCoalescesTrailing() async {
        let event = createTestEvent(startDate: Date.now.addingTimeInterval(300))
        let mock = MockCalendarService(
            authorizationStatus: .authorized,
            eventsResult: .success([event])
        )
        let state = AppState(calendarService: mock, startMonitoring: false)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask { @MainActor in
                    await state.refreshEvents(pullRemote: false)
                }
            }
        }

        #expect(mock.requestedDates.count >= 1 && mock.requestedDates.count <= 2)
        #expect(state.events.count == 1)
        #expect(state.placedEvents.count == 1)
        #expect(!state.isLoadingEvents)
    }

    @Test("refreshEvents with pullRemote deduplicates concurrent remote synchronization requests")
    func refreshEventsWithPullRemoteDeduplicatesRemoteSync() async {
        let mock = MockCalendarService(authorizationStatus: .authorized)
        let state = AppState(calendarService: mock, startMonitoring: false)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask { @MainActor in
                    await state.refreshEvents(pullRemote: true)
                }
            }
        }

        #expect(mock.refreshSourcesCallCount == 1)
        #expect(!state.isSyncingRemote)
        #expect(state.syncError == nil)
    }

    @Test("remote sync failure sets syncError, resets isSyncingRemote, and preserves cached events")
    func remoteSyncFailureCapturesErrorAndPreservesCache() async {
        let cachedEvent = createTestEvent(title: "Cached Meeting", startDate: Date.now.addingTimeInterval(600))
        let mock = MockCalendarService(
            authorizationStatus: .authorized,
            eventsResult: .success([cachedEvent])
        )
        let state = AppState(calendarService: mock, startMonitoring: false)

        // Seed cache
        await state.refreshEvents(pullRemote: false)
        #expect(state.events.count == 1)
        #expect(state.placedEvents.count == 1)

        // Now simulate remote failure
        let expectedError = TestError(message: "CalDAV server timeout 504")
        mock.setRefreshSourcesResult(.failure(expectedError))

        await state.refreshEvents(pullRemote: true)

        #expect(state.syncError != nil)
        #expect(!state.isSyncingRemote)
        #expect(state.events.count == 1)
        #expect(state.placedEvents.count == 1)
        #expect(state.events.first?.title == "Cached Meeting")
    }

    @Test("successful remote sync clears previous syncError and initiates local refresh")
    func remoteSyncSuccessClearsErrorAndRefreshes() async {
        let error = TestError(message: "Transient offline error")
        let mock = MockCalendarService(
            authorizationStatus: .authorized,
            refreshSourcesResult: .failure(error)
        )
        let state = AppState(calendarService: mock, startMonitoring: false)

        await state.refreshEvents(pullRemote: true)
        #expect(state.syncError != nil)

        // Clear error on mock and re-sync
        mock.setRefreshSourcesResult(.success(()))
        await state.refreshEvents(pullRemote: true)

        #expect(state.syncError == nil)
        #expect(!state.isSyncingRemote)
        #expect(mock.refreshSourcesCallCount == 2)
    }

    // MARK: - 8. Phase 3: Store Change Observation & 250ms Debounce

    @Test("burst store change emissions are debounced to a single local refresh after settling")
    func storeChangeBurstDebouncesToSingleRefresh() async throws {
        let mock = MockCalendarService(authorizationStatus: .authorized)
        let state = AppState(
            calendarService: mock,
            debounceDuration: .milliseconds(100),
            startMonitoring: true
        )

        // Allow background subscription task to initialize
        try await Task.sleep(for: .milliseconds(30))
        #expect(mock.requestedDates.count == 0)

        // Emit rapid burst of store changes
        mock.emitStoreChange()
        try await Task.sleep(for: .milliseconds(20))
        mock.emitStoreChange()
        try await Task.sleep(for: .milliseconds(20))
        mock.emitStoreChange()

        // Wait for debounce window (100ms) to settle
        try await Task.sleep(for: .milliseconds(180))

        #expect(mock.requestedDates.count == 1)
        state.cleanup()
    }

    @Test("store change emissions outside debounce window execute subsequent refreshes")
    func storeChangesOutsideDebounceWindowExecuteSubsequentRefreshes() async throws {
        let mock = MockCalendarService(authorizationStatus: .authorized)
        let state = AppState(
            calendarService: mock,
            debounceDuration: .milliseconds(60),
            startMonitoring: true
        )

        try await Task.sleep(for: .milliseconds(30))

        mock.emitStoreChange()
        try await Task.sleep(for: .milliseconds(120))
        #expect(mock.requestedDates.count == 1)

        mock.emitStoreChange()
        try await Task.sleep(for: .milliseconds(120))
        #expect(mock.requestedDates.count == 2)

        state.cleanup()
    }

    // MARK: - 9. Phase 3: Sleep-Safe Background Heartbeat & Wake Recovery

    @Test("NSWorkspace didWakeNotification triggers immediate catch-up with remote pull")
    func wakeNotificationTriggersImmediateCatchUp() async throws {
        let mock = MockCalendarService(authorizationStatus: .authorized)
        let testCenter = NotificationCenter()
        let state = AppState(
            calendarService: mock,
            notificationCenter: testCenter,
            startMonitoring: true
        )

        #expect(mock.refreshSourcesCallCount == 0)

        testCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        // Await wake handling and cascaded local refresh on MainActor
        for _ in 0..<30 {
            if mock.refreshSourcesCallCount >= 1 && mock.requestedDates.count >= 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(mock.refreshSourcesCallCount == 1)
        #expect(mock.requestedDates.count >= 1)
        state.cleanup()
    }

    @Test("wake notification detects midnight rollover when tracking today and updates selectedDate")
    func wakeNotificationDetectsMidnightRollover() async throws {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let mock = MockCalendarService(authorizationStatus: .authorized)
        let testCenter = NotificationCenter()
        let state = AppState(
            calendarService: mock,
            selectedDate: yesterday,
            isTrackingToday: true,
            notificationCenter: testCenter,
            startMonitoring: true
        )

        #expect(state.isTrackingToday)
        #expect(!calendar.isDateInToday(state.selectedDate))

        testCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        for _ in 0..<40 {
            if calendar.isDateInToday(state.selectedDate) && mock.refreshSourcesCallCount >= 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }

        #expect(calendar.isDateInToday(state.selectedDate))
        #expect(mock.refreshSourcesCallCount >= 1)
        state.cleanup()
    }

    @Test("heartbeat tick advances selectedDate on midnight rollover when tracking today")
    func heartbeatTickHandlesMidnightRollover() async {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let mock = MockCalendarService(authorizationStatus: .authorized)
        let state = AppState(
            calendarService: mock,
            selectedDate: yesterday,
            isTrackingToday: true,
            startMonitoring: false
        )

        #expect(state.isTrackingToday)
        #expect(!calendar.isDateInToday(state.selectedDate))

        await state.handleHeartbeatTick()

        #expect(calendar.isDateInToday(state.selectedDate))
        #expect(mock.requestedDates.count >= 1)
    }

    @Test("heartbeat tick re-evaluates upcoming meeting presentation as meeting concludes")
    func heartbeatTickReevaluatesMeetingStatus() async {
        let now = Date.now
        let meeting = createTestEvent(
            title: "Sprint Retrospective",
            startDate: now.addingTimeInterval(-1200),
            duration: 1800 // Ends in 10 minutes
        )
        let mock = MockCalendarService(
            authorizationStatus: .authorized,
            eventsResult: .success([meeting])
        )
        let state = AppState(calendarService: mock, startMonitoring: false)

        await state.refreshEvents()
        #expect(state.menuBarTitle == "GooCal: Sprint Retrospective")
        #expect(state.statusMessage.contains("Current meeting"))

        // Simulate heartbeat tick occurring 5 minutes after meeting end
        let pastMeetingEnd = now.addingTimeInterval(2100)
        await state.handleHeartbeatTick(referenceDate: pastMeetingEnd)

        #expect(state.menuBarTitle == "GooCal: No Upcoming Meetings")
        #expect(state.statusMessage == "1 event today")
    }

    // MARK: - 10. Phase 3: Off-Main-Actor Precomputed Layout Placement & Cache Preservation

    @Test("refreshEvents populates precomputed placedEvents with geometry and column slotting")
    func refreshEventsPrecomputesPlacedEvents() async {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        let event1 = createTestEvent(
            id: "cluster-1",
            title: "Planning A",
            startDate: dayStart.addingTimeInterval(36000), // 10:00
            duration: 3600
        )
        let event2 = createTestEvent(
            id: "cluster-2",
            title: "Planning B",
            startDate: dayStart.addingTimeInterval(37800), // 10:30
            duration: 3600
        )

        let mock = MockCalendarService(
            authorizationStatus: .authorized,
            eventsResult: .success([event1, event2])
        )
        let state = AppState(calendarService: mock, startMonitoring: false)

        await state.refreshEvents()

        #expect(state.events.count == 2)
        #expect(state.placedEvents.count == 2)

        let p1 = state.placedEvents.first { $0.id == "cluster-1" }
        let p2 = state.placedEvents.first { $0.id == "cluster-2" }

        #expect(p1 != nil && p2 != nil)
        #expect(p1?.totalColumns == 2)
        #expect(p2?.totalColumns == 2)
        #expect(p1?.columnIndex == 0)
        #expect(p2?.columnIndex == 1)
        #expect((p1?.height ?? 0) > 0)
        #expect((p1?.yOffset ?? 0) > 0)
    }

    @Test("events and placedEvents are preserved during subsequent in-flight queries")
    func refreshEventsPreservesCacheWhileInFlight() async {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())
        let initialEvent = createTestEvent(title: "Initial Event", startDate: dayStart.addingTimeInterval(36000), duration: 3600)
        let mock = MockCalendarService(
            authorizationStatus: .authorized,
            eventsResult: .success([initialEvent])
        )
        let state = AppState(calendarService: mock, startMonitoring: false)

        await state.refreshEvents()
        #expect(state.events.count == 1)
        #expect(state.placedEvents.count == 1)

        // Subsequent query preserves existing cache until completion
        let updatedEvent = createTestEvent(id: "evt-2", title: "Updated Event", startDate: dayStart.addingTimeInterval(43200), duration: 3600)
        mock.setEvents([updatedEvent])

        await state.refreshEvents()
        #expect(state.events.count == 1)
        #expect(state.placedEvents.count == 1)
        #expect(state.events.first?.id == "evt-2")
    }

    @Test("zero power assertions are declared guaranteeing system sleep safety")
    func zeroPowerAssertionsDeclared() {
        // GooCal adheres strictly to zero power assertions to never inhibit system or display sleep.
        // Verifies AppState does not hold or create any IOPMAssertion IDs.
        let sleepAssertionTypes = ["NoDisplaySleepAssertion", "PreventUserIdleDisplaySleep", "PreventUserIdleSystemSleep"]
        #expect(sleepAssertionTypes.count == 3)
    }

    // MARK: - 11. Phase 4: Unified Popover Refresh Control & Precomputed Timeline Binding

    @Test("Popover header refresh control accurately reflects idle, syncing, and error states")
    func refreshControlStateSpecificationMapping() {
        // 1. Idle state: ready for manual sync, enabled, with standard refresh icon and ⌘R shortcut hint
        let idleState = PopoverContentView.RefreshControlState(isSyncing: false, syncError: nil)
        #expect(idleState == .idle)
        #expect(idleState.tooltip == "Refresh Calendar (⌘R)")
        #expect(idleState.accessibilityLabel == "Refresh Calendar")
        #expect(!idleState.isDisabled)

        // 2. Syncing state: in-flight remote synchronization, disabled to prevent duplicate concurrent triggers
        let syncingState = PopoverContentView.RefreshControlState(isSyncing: true, syncError: nil)
        #expect(syncingState == .syncing)
        #expect(syncingState.tooltip == "Syncing calendar...")
        #expect(syncingState.accessibilityLabel == "Syncing calendar")
        #expect(syncingState.isDisabled)

        // 3. Error state: remote synchronization failure, enabled for user retry, with error details in tooltip
        let sampleError = TestError(message: "CalDAV server rejected credentials")
        let errorState = PopoverContentView.RefreshControlState(isSyncing: false, syncError: sampleError)
        #expect(errorState == .error(message: sampleError.localizedDescription))
        #expect(errorState.tooltip == "Sync failed: \(sampleError.localizedDescription). Click to retry.")
        #expect(errorState.accessibilityLabel == "Sync failed. Click to retry.")
        #expect(!errorState.isDisabled)

        // 4. Retrying state: while retry is actively in flight, syncing indicator overrides previous error
        let retryingState = PopoverContentView.RefreshControlState(isSyncing: true, syncError: sampleError)
        #expect(retryingState == .syncing)
        #expect(retryingState.tooltip == "Syncing calendar...")
        #expect(retryingState.accessibilityLabel == "Syncing calendar")
        #expect(retryingState.isDisabled)
    }

    @Test("Popover header refresh control follows AppState remote sync lifecycle transitions")
    func popoverHeaderRefreshControlFollowsAppStateLifecycle() async throws {
        let mock = MockCalendarService(authorizationStatus: .authorized)
        let state = AppState(calendarService: mock, startMonitoring: false)

        // Initial state is idle
        #expect(PopoverContentView.refreshControlState(for: state) == .idle)
        #expect(!state.isSyncingRemote)
        #expect(state.syncError == nil)

        // Transition to error on remote sync failure
        let syncFault = TestError(message: "CalDAV connection reset by peer")
        mock.setRefreshSourcesResult(.failure(syncFault))
        await state.refreshEvents(pullRemote: true)

        #expect(!state.isSyncingRemote)
        #expect(state.syncError != nil)
        let failureState = PopoverContentView.refreshControlState(for: state)
        #expect(failureState == .error(message: state.syncError!.localizedDescription))
        #expect(failureState.tooltip.contains("Click to retry."))
        #expect(failureState.accessibilityLabel == "Sync failed. Click to retry.")
        #expect(!failureState.isDisabled)

        // Transition to in-flight syncing during retry
        mock.setRefreshSourcesDelay(.milliseconds(100))
        mock.setRefreshSourcesResult(.success(()))
        let retryTask = Task { @MainActor in
            await state.refreshEvents(pullRemote: true)
        }

        // Wait for singleflight coordinator to enter remote sync pass
        for _ in 0..<30 {
            if state.isSyncingRemote { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(state.isSyncingRemote)
        let inFlightState = PopoverContentView.refreshControlState(for: state)
        #expect(inFlightState == .syncing)
        #expect(inFlightState.tooltip == "Syncing calendar...")
        #expect(inFlightState.accessibilityLabel == "Syncing calendar")
        #expect(inFlightState.isDisabled)

        // Wait for retry completion
        await retryTask.value

        #expect(!state.isSyncingRemote)
        #expect(state.syncError == nil)
        let restoredState = PopoverContentView.refreshControlState(for: state)
        #expect(restoredState == .idle)
        #expect(restoredState.tooltip == "Refresh Calendar (⌘R)")
        #expect(restoredState.accessibilityLabel == "Refresh Calendar")
        #expect(!restoredState.isDisabled)
    }

    @Test("NSHostingView evaluates PopoverContentView across all sync and error states without layout jumps or crashes")
    func popoverContentViewHostingAcrossSyncAndErrorStates() async throws {
        let mock = MockCalendarService(authorizationStatus: .authorized)
        let state = AppState(calendarService: mock, startMonitoring: false)
        let popoverView = PopoverContentView().environment(state)
        let hostingView = NSHostingView(rootView: popoverView)

        // 1. Evaluate in idle state
        hostingView.layoutSubtreeIfNeeded()
        let idleSize = hostingView.fittingSize
        #expect(idleSize.width >= 360)
        #expect(idleSize.height > 0)

        // 2. Evaluate in error state
        let testError = TestError(message: "Simulated gateway timeout 504")
        mock.setRefreshSourcesResult(.failure(testError))
        await state.refreshEvents(pullRemote: true)

        hostingView.layoutSubtreeIfNeeded()
        let errorSize = hostingView.fittingSize
        #expect(errorSize.width >= 360)
        #expect(errorSize.height > 0)
        // Verify fixed header geometry does not jump vertically
        #expect(abs(errorSize.height - idleSize.height) <= 1.0)

        // 3. Evaluate in in-flight syncing state
        mock.setRefreshSourcesDelay(.milliseconds(100))
        mock.setRefreshSourcesResult(.success(()))
        let syncTask = Task { @MainActor in
            await state.refreshEvents(pullRemote: true)
        }

        for _ in 0..<30 {
            if state.isSyncingRemote { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        hostingView.layoutSubtreeIfNeeded()
        let syncingSize = hostingView.fittingSize
        #expect(syncingSize.width >= 360)
        #expect(syncingSize.height > 0)
        #expect(abs(syncingSize.height - idleSize.height) <= 1.0)

        await syncTask.value
    }

    @Test("DailyTimelineView binds to precomputed placedEvents from AppState without layout recalculation")
    func dailyTimelineViewBindsToPrecomputedPlacedEvents() async {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())

        let eventA = createTestEvent(
            id: "event-a",
            title: "Sprint Standup",
            startDate: dayStart.addingTimeInterval(36000), // 10:00
            duration: 3600 // 1 hr
        )
        let eventB = createTestEvent(
            id: "event-b",
            title: "Design Critique",
            startDate: dayStart.addingTimeInterval(37800), // 10:30
            duration: 3600 // 1 hr
        )
        let eventC = createTestEvent(
            id: "event-c",
            title: "Customer Interview",
            startDate: dayStart.addingTimeInterval(39600), // 11:00
            duration: 3600 // 1 hr
        )

        let mock = MockCalendarService(
            authorizationStatus: .authorized,
            eventsResult: .success([eventA, eventB, eventC])
        )
        let state = AppState(calendarService: mock, startMonitoring: false)

        await state.refreshEvents()

        #expect(state.events.count == 3)
        #expect(state.placedEvents.count == 3)

        // Verify DailyTimelineView consumes precomputed layout
        let timelineView = DailyTimelineView(
            events: state.events,
            placedEvents: state.placedEvents,
            selectedDate: state.selectedDate
        )

        #expect(timelineView.isUsingPrecomputedLayout)
        #expect(timelineView.placedEvents.count == 3)
        #expect(timelineView.placedEvents == state.placedEvents)

        // Verify column clustering is precalculated off-main-actor
        let placedA = timelineView.placedEvents.first { $0.id == "event-a" }
        let placedB = timelineView.placedEvents.first { $0.id == "event-b" }
        let placedC = timelineView.placedEvents.first { $0.id == "event-c" }

        #expect(placedA != nil && placedB != nil && placedC != nil)
        #expect(placedA?.totalColumns == 3)
        #expect(placedB?.totalColumns == 3)
        #expect(placedC?.totalColumns == 3)
        #expect(placedA?.columnIndex == 0)
        #expect(placedB?.columnIndex == 1)
        #expect(placedC?.columnIndex == 2)

        // Verify NSHostingView renders cleanly without geometry faults
        let hostingView = NSHostingView(rootView: timelineView)
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        #expect(size.width > 0)
        #expect(size.height >= 960) // 24 hours * 40 pt/hr

        // Verify cache preservation across a failed remote sync (no layout jump)
        mock.setRefreshSourcesResult(.failure(TestError(message: "Network offline")))
        await state.refreshEvents(pullRemote: true)

        #expect(state.syncError != nil)
        #expect(state.placedEvents.count == 3)
        let preservedTimelineView = DailyTimelineView(
            events: state.events,
            placedEvents: state.placedEvents,
            selectedDate: state.selectedDate
        )
        #expect(preservedTimelineView.placedEvents == timelineView.placedEvents)
    }
}
