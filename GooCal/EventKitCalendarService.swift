//
//  EventKitCalendarService.swift
//  GooCal
//

import Foundation
import EventKit
import CoreGraphics

extension EKEvent {
    /// Indicates whether the current user is an attendee or organizer for this event.
    public var isCurrentUserForScheduling: Bool {
        if attendees?.contains(where: { $0.isCurrentUser }) == true {
            return true
        }
        return organizer?.isCurrentUser ?? false
    }
}

/// Production implementation of `CalendarServiceManaging` backed by Apple's EventKit framework.
///
/// Queries local and synchronized calendar accounts using macOS 14+ full-access permissions,
/// extracting native `CGColor` properties and normalizing `EKEvent` structures into immutable
/// `CalendarEvent` domain models.
public final class EventKitCalendarService: CalendarServiceManaging, @unchecked Sendable {
    private let eventStore: EKEventStore
    private let notificationCenter: NotificationCenter

    /// Fallback color used if a calendar does not report a valid `CGColor`.
    public static let defaultCalendarColor = CGColor(srgbRed: 0.2, green: 0.5, blue: 1.0, alpha: 1.0)

    /// Initializes the service with an optional injected `EKEventStore`.
    ///
    /// - Parameter eventStore: The event store managing access to the macOS calendar database.
    public init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
        self.notificationCenter = .default
    }

    /// Initializes the service with an injected `EKEventStore` and `NotificationCenter`.
    ///
    /// - Parameters:
    ///   - eventStore: The event store managing access to the macOS calendar database.
    ///   - notificationCenter: The notification center observing system notifications.
    public init(
        eventStore: EKEventStore = EKEventStore(),
        notificationCenter: NotificationCenter
    ) {
        self.eventStore = eventStore
        self.notificationCenter = notificationCenter
    }

    /// Queries the current authorization status for calendar events from EventKit.
    public func authorizationStatus() -> CalendarAuthorizationStatus {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .notDetermined:
            return .notDetermined
        case .fullAccess, .authorized:
            return .authorized
        case .restricted:
            return .restricted
        case .denied, .writeOnly:
            return .denied
        @unknown default:
            return .notDetermined
        }
    }

    /// Requests full calendar access from macOS using the macOS 14+ `requestFullAccessToEvents` API.
    public func requestAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToEvents()
    }

    /// Fetches all calendar events occurring on the 24-hour day of the specified date.
    ///
    /// - Parameter date: Reference date identifying the 24-hour day in the user's current calendar.
    /// - Returns: Array of `CalendarEvent` models overlapping that day.
    public func events(for date: Date) async throws -> [CalendarEvent] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let ekEvents = eventStore.events(matching: predicate)
        return ekEvents.map(Self.map(ekEvent:))
    }

    /// Requests that macOS refresh calendar sources if necessary, pulling any changes
    /// that may have occurred on remote servers without blocking the user interface.
    public func refreshSources() async throws {
        eventStore.refreshSourcesIfNecessary()
    }

    /// An asynchronous stream of notifications indicating that the calendar database has changed.
    ///
    /// Observes `EKEventStoreChanged` notifications. Cleans up the underlying notification
    /// observation task when the stream terminates or the caller cancels iteration.
    public var storeChanges: AsyncStream<Void> {
        let center = self.notificationCenter
        return AsyncStream { continuation in
            let task = Task {
                for await _ in center.notifications(named: .EKEventStoreChanged) {
                    guard !Task.isCancelled else { break }
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Maps EventKit availability enum to domain AvailabilityStatus.
    public static func mapAvailability(_ availability: EKEventAvailability) -> AvailabilityStatus {
        switch availability {
        case .busy:
            return .busy
        case .free:
            return .free
        case .tentative:
            return .tentative
        case .unavailable:
            return .unavailable
        case .notSupported:
            return .busy
        @unknown default:
            return .busy
        }
    }

    /// Maps EventKit participant status enum to domain ParticipantStatus.
    public static func mapParticipantStatus(_ status: EKParticipantStatus) -> ParticipantStatus {
        switch status {
        case .accepted:
            return .accepted
        case .tentative:
            return .tentative
        case .pending:
            return .pending
        case .declined:
            return .declined
        case .unknown, .delegated, .completed, .inProcess:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    /// Maps an EventKit `EKEvent` instance into a thread-safe `CalendarEvent` value model.
    ///
    /// Extracts calendar color from `EKCalendar.cgColor`, availability, and determines participant
    /// response status using `attendees` and `isCurrentUserForScheduling`.
    public static func map(ekEvent: EKEvent) -> CalendarEvent {
        let title = ekEvent.title ?? ""
        let startDate = ekEvent.startDate ?? Date()
        let endDate = ekEvent.endDate ?? startDate
        let isAllDay = ekEvent.isAllDay

        let calendarColor = ekEvent.calendar?.cgColor ?? defaultCalendarColor
        let availability = mapAvailability(ekEvent.availability)

        let isOrganizer = ekEvent.organizer?.isCurrentUser ?? (ekEvent.attendees == nil || ekEvent.attendees?.isEmpty == true)

        let participantStatus: ParticipantStatus
        if let currentAttendee = ekEvent.attendees?.first(where: { $0.isCurrentUser }) {
            participantStatus = mapParticipantStatus(currentAttendee.participantStatus)
        } else if ekEvent.isCurrentUserForScheduling || isOrganizer {
            participantStatus = .accepted
        } else {
            participantStatus = .unknown
        }

        return CalendarEvent(
            id: ekEvent.eventIdentifier ?? UUID().uuidString,
            title: title,
            startDate: startDate,
            endDate: endDate,
            isAllDay: isAllDay,
            calendarColor: calendarColor,
            participantStatus: participantStatus,
            availabilityStatus: availability,
            isOrganizer: isOrganizer
        )
    }
}
