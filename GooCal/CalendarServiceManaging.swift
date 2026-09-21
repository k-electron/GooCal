//
//  CalendarServiceManaging.swift
//  GooCal
//

import Foundation

/// System authorization status for calendar data access.
///
/// Abstracted from EventKit authorization statuses to decouple app business logic
/// and unit testing from macOS system permission dialogs and privacy frameworks.
public enum CalendarAuthorizationStatus: String, Sendable, Equatable, Hashable, CaseIterable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

/// Abstract contract managing calendar event querying and system authorization.
///
/// Adheres to Swift 6 concurrency (`Sendable`) allowing service instances to be shared
/// across actor boundaries (e.g. background event polling and `@MainActor` state stores).
public protocol CalendarServiceManaging: Sendable {
    /// Returns the current system authorization state for calendar events.
    func authorizationStatus() -> CalendarAuthorizationStatus

    /// Requests full access permission from macOS to read calendar events.
    ///
    /// - Returns: `true` if access was granted, `false` if denied.
    func requestAccess() async throws -> Bool

    /// Fetches all calendar events occurring on the specified date.
    ///
    /// Queries the 24-hour interval encompassing the given date in the user's local calendar.
    /// - Parameter date: The reference date identifying the 24-hour window to query.
    /// - Returns: Array of `CalendarEvent` models occurring within that 24-hour span.
    func events(for date: Date) async throws -> [CalendarEvent]

    /// Requests that macOS refresh calendar sources if necessary (e.g. pulling remote accounts).
    func refreshSources() async throws

    /// An asynchronous stream of notifications indicating that the calendar database has changed.
    var storeChanges: AsyncStream<Void> { get }
}
