//
//  MockCalendarService.swift
//  GooCal
//

import Foundation

/// Deterministic mock implementation of `CalendarServiceManaging` for unit tests and SwiftUI previews.
///
/// Provides configurable responses for authorization checks, permission requests,
/// and event fetching. Synchronized internally using `NSLock` to guarantee safe concurrent
/// access across actor boundaries without race conditions.
public final class MockCalendarService: CalendarServiceManaging, @unchecked Sendable {
    private let lock = NSLock()

    private var _status: CalendarAuthorizationStatus
    private var _requestAccessResult: Result<Bool, any Error>
    private var _eventsResult: Result<[CalendarEvent], any Error>
    private var _requestAccessCallCount: Int = 0
    private var _requestedDates: [Date] = []

    /// Creates a mock service with customizable initial return values.
    ///
    /// - Parameters:
    ///   - authorizationStatus: Initial authorization state returned by `authorizationStatus()`.
    ///   - requestAccessResult: Result returned or thrown when `requestAccess()` is invoked.
    ///   - eventsResult: Result returned or thrown when `events(for:)` is invoked.
    public init(
        authorizationStatus: CalendarAuthorizationStatus = .authorized,
        requestAccessResult: Result<Bool, any Error> = .success(true),
        eventsResult: Result<[CalendarEvent], any Error> = .success([])
    ) {
        self._status = authorizationStatus
        self._requestAccessResult = requestAccessResult
        self._eventsResult = eventsResult
    }

    public func authorizationStatus() -> CalendarAuthorizationStatus {
        lock.withLock { _status }
    }

    public func setAuthorizationStatus(_ status: CalendarAuthorizationStatus) {
        lock.withLock { _status = status }
    }

    public var requestAccessCallCount: Int {
        lock.withLock { _requestAccessCallCount }
    }

    public var requestedDates: [Date] {
        lock.withLock { _requestedDates }
    }

    public func setRequestAccessResult(_ result: Result<Bool, any Error>) {
        lock.withLock { _requestAccessResult = result }
    }

    public func setEventsResult(_ result: Result<[CalendarEvent], any Error>) {
        lock.withLock { _eventsResult = result }
    }

    public func setEvents(_ events: [CalendarEvent]) {
        setEventsResult(.success(events))
    }

    public func requestAccess() async throws -> Bool {
        try lock.withLock {
            _requestAccessCallCount += 1
            switch _requestAccessResult {
            case .success(let granted):
                if granted {
                    _status = .authorized
                }
                return granted
            case .failure(let error):
                throw error
            }
        }
    }

    public func events(for date: Date) async throws -> [CalendarEvent] {
        try lock.withLock {
            _requestedDates.append(date)
            switch _eventsResult {
            case .success(let events):
                return events
            case .failure(let error):
                throw error
            }
        }
    }
}
