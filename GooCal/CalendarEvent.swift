//
//  CalendarEvent.swift
//  GooCal
//

import Foundation
import CoreGraphics

/// Participation response status of an attendee for a calendar event.
///
/// Encapsulates whether the user has accepted, declined, tentatively acknowledged,
/// or has not yet responded to an invitation. Used by timeline layout engine to filter
/// out declined events and rank concurrent event columns by precedence.
public enum ParticipantStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case accepted
    case tentative
    case pending
    case declined
    case unknown
}

/// Calendar availability state indicating how an event impacts free/busy scheduling.
///
/// Mirrored from EventKit availability semantics to enable timeline precedence ranking
/// (busy commitments take precedence over free/placeholder blocks during column slotting).
public enum AvailabilityStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case busy
    case free
    case tentative
    case unavailable
}

/// Immutable, thread-safe domain representation of a calendar event.
///
/// Designed as a pure `Sendable` value type to decouple presentation and layout engines
/// from EventKit's mutable, reference-typed `EKEvent` objects. Preserves the native
/// macOS calendar color as a `CGColor` for faithful system-matching timeline styling.
public struct CalendarEvent: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let isAllDay: Bool
    public let calendarColor: CGColor
    public let participantStatus: ParticipantStatus
    public let availabilityStatus: AvailabilityStatus
    public let isOrganizer: Bool

    /// Convenience alias for availability status.
    public var availability: AvailabilityStatus {
        availabilityStatus
    }

    /// Calculated duration in seconds.
    ///
    /// Invariant: Because `endDate` is guaranteed to be greater than or equal to `startDate`,
    /// duration is always non-negative.
    public var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    /// Creates a domain calendar event.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for the event. Defaults to a new UUID string.
    ///   - title: Human-readable title of the meeting or appointment.
    ///   - startDate: Scheduled start timestamp.
    ///   - endDate: Scheduled completion timestamp. If earlier than `startDate`, it is clamped to `startDate`.
    ///   - isAllDay: Flag indicating whether this is an all-day or multi-day spanning banner event.
    ///   - calendarColor: The CoreGraphics color assigned to the event's source calendar in macOS Calendar.
    ///   - participantStatus: The current user's invitation response status. Defaults to `.unknown`.
    ///   - availabilityStatus: Impact on user free/busy availability. Defaults to `.busy`.
    ///   - isOrganizer: Flag indicating whether the current user is the organizer of the event.
    public init(
        id: String = UUID().uuidString,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool = false,
        calendarColor: CGColor = CGColor(srgbRed: 0.2, green: 0.5, blue: 1.0, alpha: 1.0),
        participantStatus: ParticipantStatus = .unknown,
        availabilityStatus: AvailabilityStatus = .busy,
        isOrganizer: Bool = false
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = max(startDate, endDate)
        self.isAllDay = isAllDay
        self.calendarColor = calendarColor
        self.participantStatus = participantStatus
        self.availabilityStatus = availabilityStatus
        self.isOrganizer = isOrganizer
    }

    public static func == (lhs: CalendarEvent, rhs: CalendarEvent) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.startDate == rhs.startDate &&
        lhs.endDate == rhs.endDate &&
        lhs.isAllDay == rhs.isAllDay &&
        lhs.calendarColor == rhs.calendarColor &&
        lhs.participantStatus == rhs.participantStatus &&
        lhs.availabilityStatus == rhs.availabilityStatus &&
        lhs.isOrganizer == rhs.isOrganizer
    }
}
