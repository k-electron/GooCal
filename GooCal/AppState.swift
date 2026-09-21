//
//  AppState.swift
//  GooCal
//

import SwiftUI
import Observation

/// Central state store for GooCal menu bar and settings presentation.
///
/// Marked `@MainActor` and `@Observable` to guarantee thread-safe UI binding updates
/// with fine-grained view invalidation under Swift concurrency.
@Observable
@MainActor
public final class AppState {
    public var menuBarTitle: String
    public var menuBarIconName: String
    public var isLaunchAtLoginEnabled: Bool
    public var statusMessage: String
    public private(set) var lastError: (any Error)?

    public private(set) var events: [CalendarEvent] = []
    public private(set) var calendarAuthorizationStatus: CalendarAuthorizationStatus
    public var selectedDate: Date = Date()
    public private(set) var isLoadingEvents: Bool = false

    public let calendarService: any CalendarServiceManaging
    private let launchAtLoginManager: any LaunchAtLoginManaging

    /// Creates an application state instance.
    ///
    /// Accepts custom `LaunchAtLoginManaging` and `CalendarServiceManaging` to enable
    /// deterministic unit testing without mutating system-wide login items or relying on live TCC permissions.
    public init(
        launchAtLoginManager: any LaunchAtLoginManaging = SMAppServiceLaunchAtLoginManager(),
        calendarService: any CalendarServiceManaging = EventKitCalendarService(),
        menuBarTitle: String = "GooCal: No Upcoming Meetings",
        menuBarIconName: String = "calendar",
        statusMessage: String = "No upcoming meetings",
        selectedDate: Date = Date()
    ) {
        self.launchAtLoginManager = launchAtLoginManager
        self.calendarService = calendarService
        self.menuBarTitle = menuBarTitle
        self.menuBarIconName = menuBarIconName
        self.statusMessage = statusMessage
        self.selectedDate = selectedDate
        self.isLaunchAtLoginEnabled = launchAtLoginManager.isEnabled
        self.calendarAuthorizationStatus = calendarService.authorizationStatus()
        self.events = []
        self.isLoadingEvents = false
        self.lastError = nil
    }

    /// Two-way SwiftUI binding bridging toggle controls directly to managed login registration.
    public var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { self.isLaunchAtLoginEnabled },
            set: { self.setLaunchAtLogin(enabled: $0) }
        )
    }

    /// Synchronizes login item registration with macOS ServiceManagement.
    ///
    /// If registration or unregistration throws (e.g. system authorization failure),
    /// the error is captured, user status is updated, and `isLaunchAtLoginEnabled`
    /// stays synchronized with the manager's actual state to prevent misleading UI indicators.
    public func setLaunchAtLogin(enabled: Bool) {
        do {
            try launchAtLoginManager.setEnabled(enabled)
            isLaunchAtLoginEnabled = launchAtLoginManager.isEnabled
            statusMessage = enabled ? "Launch at login enabled" : "Launch at login disabled"
            lastError = nil
        } catch {
            isLaunchAtLoginEnabled = launchAtLoginManager.isEnabled
            statusMessage = "Failed to update launch at login: \(error.localizedDescription)"
            lastError = error
        }
    }

    /// Explicitly requests calendar access and triggers an events refresh.
    public func requestCalendarAccess() async {
        do {
            _ = try await calendarService.requestAccess()
            await refreshEvents()
        } catch {
            self.lastError = error
            self.calendarAuthorizationStatus = calendarService.authorizationStatus()
            self.statusMessage = "Failed to request calendar access: \(error.localizedDescription)"
        }
    }

    /// Updates the selected active date and queries calendar events for the new 24-hour day.
    public func setSelectedDate(_ date: Date) async {
        self.selectedDate = date
        await refreshEvents()
    }

    /// Refreshes calendar authorization and queries calendar events for the active date.
    public func refreshEvents() async {
        isLoadingEvents = true
        defer { isLoadingEvents = false }

        calendarAuthorizationStatus = calendarService.authorizationStatus()
        if calendarAuthorizationStatus == .notDetermined {
            do {
                _ = try await calendarService.requestAccess()
                calendarAuthorizationStatus = calendarService.authorizationStatus()
            } catch {
                self.lastError = error
                self.statusMessage = "Failed to request calendar access: \(error.localizedDescription)"
                return
            }
        }

        switch calendarAuthorizationStatus {
        case .authorized:
            do {
                let fetchedEvents = try await calendarService.events(for: selectedDate)
                self.events = fetchedEvents
                self.lastError = nil
                updatePresentationForLoadedEvents(with: fetchedEvents)
            } catch {
                self.lastError = error
                self.statusMessage = "Failed to load events: \(error.localizedDescription)"
            }

        case .denied, .restricted:
            self.events = []
            self.menuBarTitle = "GooCal: Calendar Access Required"
            self.statusMessage = "Calendar access is denied or restricted"

        case .notDetermined:
            self.events = []
        }
    }

    /// Updates menu bar title and status message based on queried events and current time context.
    private func updatePresentationForLoadedEvents(with events: [CalendarEvent]) {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(selectedDate)
        let activeEvents = events.filter { !$0.isAllDay && $0.participantStatus != .declined }

        if isToday {
            let now = Date.now
            let upcoming = activeEvents
                .filter { $0.endDate > now }
                .sorted { $0.startDate < $1.startDate }

            if let nextEvent = upcoming.first {
                menuBarTitle = "GooCal: \(nextEvent.title)"
                if nextEvent.startDate <= now {
                    statusMessage = "Current meeting: \(nextEvent.title)"
                } else {
                    let timeStr = nextEvent.startDate.formatted(date: .omitted, time: .shortened)
                    statusMessage = "Next at \(timeStr): \(nextEvent.title)"
                }
            } else {
                menuBarTitle = "GooCal: No Upcoming Meetings"
                statusMessage = events.isEmpty ? "No upcoming meetings" : "\(events.count) event\(events.count == 1 ? "" : "s") today"
            }
        } else {
            let count = events.count
            let dateStr = selectedDate.formatted(.dateTime.month().day())
            statusMessage = "\(count) event\(count == 1 ? "" : "s") on \(dateStr)"
        }
    }
}
