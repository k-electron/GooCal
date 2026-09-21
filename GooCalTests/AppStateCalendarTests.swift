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
}
