//
//  TimelineLayoutEngine.swift
//  GooCal
//

import Foundation
import CoreGraphics

/// Visual placement and geometry metadata for a calendar event rendered on the daily timeline.
public struct PlacedEvent: Identifiable, Sendable, Equatable {
    /// Event identifier, matching the underlying `CalendarEvent.id`.
    public let id: String

    /// Underlying domain calendar event.
    public let event: CalendarEvent

    /// Start date clamped to the active day boundary (`00:00:00`).
    public let effectiveStartDate: Date

    /// End date clamped to the active day boundary (`24:00:00`).
    public let effectiveEndDate: Date

    /// Indicates that the event started prior to 00:00 of the active day and continues into it.
    public let spansFromYesterday: Bool

    /// Indicates that the event continues past 23:59:59 into the subsequent day.
    public let spansIntoTomorrow: Bool

    /// Vertical coordinate offset in points from the 00:00 baseline.
    public let yOffset: CGFloat

    /// Rendered height in points, enforcing the minimum height threshold.
    public let height: CGFloat

    /// Zero-based horizontal column slot index (`0..<totalColumns`).
    public let columnIndex: Int

    /// Total number of concurrent visual columns in this event's cluster (1 to 4).
    public let totalColumns: Int

    /// Count of additional overlapping events that could not be displayed due to the 4-column limit.
    /// Non-zero only on the 4th column of a cluster with 5 or more overlapping events.
    public let overflowCount: Int

    /// Creates a placed event representation with geometry and column metadata.
    public init(
        id: String? = nil,
        event: CalendarEvent,
        effectiveStartDate: Date,
        effectiveEndDate: Date,
        spansFromYesterday: Bool,
        spansIntoTomorrow: Bool,
        yOffset: CGFloat,
        height: CGFloat,
        columnIndex: Int,
        totalColumns: Int,
        overflowCount: Int = 0
    ) {
        self.id = id ?? event.id
        self.event = event
        self.effectiveStartDate = effectiveStartDate
        self.effectiveEndDate = effectiveEndDate
        self.spansFromYesterday = spansFromYesterday
        self.spansIntoTomorrow = spansIntoTomorrow
        self.yOffset = yOffset
        self.height = height
        self.columnIndex = columnIndex
        self.totalColumns = totalColumns
        self.overflowCount = overflowCount
    }
}

/// Deterministic layout engine responsible for filtering, clamping, clustering, and column slotting of calendar events.
///
/// Executes a pure 4-stage pipeline:
/// 1. **Filtering**: Discards all-day events and declined invitations.
/// 2. **Clamping**: Binds multi-day events to active day `[00:00, 24:00]` boundaries and sets continuation flags.
/// 3. **Clustering**: Groups concurrent events into intersecting clusters.
/// 4. **Precedence Ranking & Slotting**: Sorts each cluster by precedence rules (Response > Availability > Role >
///    Start Time > Duration) and assigns visual column indices (up to 4 columns) with overflow computation.
public struct TimelineLayoutEngine: Sendable {
    /// Shared layout engine singleton configured with standard calendar.
    public static let shared = TimelineLayoutEngine()

    public let calendar: Calendar

    /// Creates a layout engine instance configured with the specified calendar.
    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Internal intermediate representation of an event after filtering and clamping.
    private struct ClampedEvent: Sendable {
        let event: CalendarEvent
        let effectiveStartDate: Date
        let effectiveEndDate: Date
        let spansFromYesterday: Bool
        let spansIntoTomorrow: Bool
    }

    /// Lays out events for the given date onto the vertical timeline canvas.
    ///
    /// - Parameters:
    ///   - events: Raw calendar events retrieved from the calendar service.
    ///   - date: Target active day to layout.
    ///   - coordinateConverter: Converter responsible for time-to-Y and duration-to-height mappings.
    /// - Returns: Positioned events with geometry and column slots ready for rendering.
    public func layoutEvents(
        _ events: [CalendarEvent],
        for date: Date,
        coordinateConverter: TimelineCoordinateConverter = .default
    ) -> [PlacedEvent] {
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return []
        }

        // 1 & 2. Filter & Clamp
        var clampedEvents: [ClampedEvent] = []

        for event in events {
            // Omit all-day events and declined invitations
            if event.isAllDay || event.participantStatus == .declined {
                continue
            }

            // Exclude events that do not intersect the active day
            if event.endDate <= dayStart || event.startDate >= dayEnd {
                continue
            }

            let spansFromYesterday = event.startDate < dayStart
            let spansIntoTomorrow = event.endDate > dayEnd
            let effectiveStartDate = spansFromYesterday ? dayStart : event.startDate
            let effectiveEndDate = spansIntoTomorrow ? dayEnd : event.endDate

            guard effectiveEndDate >= effectiveStartDate else { continue }

            clampedEvents.append(
                ClampedEvent(
                    event: event,
                    effectiveStartDate: effectiveStartDate,
                    effectiveEndDate: effectiveEndDate,
                    spansFromYesterday: spansFromYesterday,
                    spansIntoTomorrow: spansIntoTomorrow
                )
            )
        }

        guard !clampedEvents.isEmpty else { return [] }

        // Sort chronologically to form contiguous clusters
        clampedEvents.sort { lhs, rhs in
            if lhs.effectiveStartDate != rhs.effectiveStartDate {
                return lhs.effectiveStartDate < rhs.effectiveStartDate
            }
            if lhs.effectiveEndDate != rhs.effectiveEndDate {
                return lhs.effectiveEndDate > rhs.effectiveEndDate
            }
            return lhs.event.id < rhs.event.id
        }

        // 3. Cluster overlapping intervals
        var clusters: [[ClampedEvent]] = []
        var currentCluster: [ClampedEvent] = []
        var currentClusterEnd: Date = .distantPast

        for clamped in clampedEvents {
            if currentCluster.isEmpty {
                currentCluster.append(clamped)
                currentClusterEnd = clamped.effectiveEndDate
            } else {
                let overlaps = clamped.effectiveStartDate < currentClusterEnd ||
                    (clamped.effectiveStartDate == currentClusterEnd && clamped.effectiveStartDate == currentCluster.first!.effectiveStartDate)

                if overlaps {
                    currentCluster.append(clamped)
                    if clamped.effectiveEndDate > currentClusterEnd {
                        currentClusterEnd = clamped.effectiveEndDate
                    }
                } else {
                    clusters.append(currentCluster)
                    currentCluster = [clamped]
                    currentClusterEnd = clamped.effectiveEndDate
                }
            }
        }

        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }

        // 4. Precedence sort and column slotting
        var placedEvents: [PlacedEvent] = []

        for cluster in clusters {
            let sortedCluster = cluster.sorted { comparePrecedence($0.event, $1.event) }
            let clusterCount = sortedCluster.count
            let totalColumns = min(4, clusterCount)
            let visibleCount = min(4, clusterCount)

            for columnIndex in 0..<visibleCount {
                let clamped = sortedCluster[columnIndex]
                let y = coordinateConverter.yOffset(for: clamped.effectiveStartDate, relativeTo: dayStart)
                let duration = clamped.effectiveEndDate.timeIntervalSince(clamped.effectiveStartDate)
                let height = coordinateConverter.height(for: duration)

                let overflowCount = (columnIndex == 3 && clusterCount >= 5) ? (clusterCount - 4) : 0

                let placed = PlacedEvent(
                    id: clamped.event.id,
                    event: clamped.event,
                    effectiveStartDate: clamped.effectiveStartDate,
                    effectiveEndDate: clamped.effectiveEndDate,
                    spansFromYesterday: clamped.spansFromYesterday,
                    spansIntoTomorrow: clamped.spansIntoTomorrow,
                    yOffset: y,
                    height: height,
                    columnIndex: columnIndex,
                    totalColumns: totalColumns,
                    overflowCount: overflowCount
                )
                placedEvents.append(placed)
            }
        }

        return placedEvents
    }

    /// Convenience static method using a default engine instance.
    public static func layoutEvents(
        _ events: [CalendarEvent],
        for date: Date,
        coordinateConverter: TimelineCoordinateConverter = .default,
        calendar: Calendar = .current
    ) -> [PlacedEvent] {
        TimelineLayoutEngine(calendar: calendar).layoutEvents(
            events,
            for: date,
            coordinateConverter: coordinateConverter
        )
    }

    /// Convenience static method matching OpenSpec design.
    public static func layout(
        events: [CalendarEvent],
        for date: Date,
        coordinateConverter: TimelineCoordinateConverter = .default,
        calendar: Calendar = .current
    ) -> [PlacedEvent] {
        layoutEvents(events, for: date, coordinateConverter: coordinateConverter, calendar: calendar)
    }

    /// Convenience instance method matching OpenSpec design.
    public func layout(
        events: [CalendarEvent],
        for date: Date,
        coordinateConverter: TimelineCoordinateConverter = .default
    ) -> [PlacedEvent] {
        layoutEvents(events, for: date, coordinateConverter: coordinateConverter)
    }

    // MARK: - Precedence Comparator

    /// Evaluates relative ranking between two concurrent events.
    ///
    /// Precedence order:
    /// 1. Response status: `.accepted` > `.tentative` > `.pending` > `.unknown` > `.declined`
    /// 2. Availability status: `.busy` > `.unavailable` > `.tentative` > `.free`
    /// 3. Role: Organizer (`true`) > Attendee (`false`)
    /// 4. Start Time: Earlier `startDate` > later
    /// 5. Duration: Shorter `duration` > longer
    /// 6. Identifier: Deterministic tie-breaker
    private func comparePrecedence(_ lhs: CalendarEvent, _ rhs: CalendarEvent) -> Bool {
        // 1. Response
        let r1 = responsePrecedence(lhs.participantStatus)
        let r2 = responsePrecedence(rhs.participantStatus)
        if r1 != r2 {
            return r1 > r2
        }

        // 2. Availability
        let a1 = availabilityPrecedence(lhs.availabilityStatus)
        let a2 = availabilityPrecedence(rhs.availabilityStatus)
        if a1 != a2 {
            return a1 > a2
        }

        // 3. Role
        if lhs.isOrganizer != rhs.isOrganizer {
            return lhs.isOrganizer && !rhs.isOrganizer
        }

        // 4. Start Time (earlier before later)
        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }

        // 5. Duration (shorter before longer)
        if lhs.duration != rhs.duration {
            return lhs.duration < rhs.duration
        }

        // 6. Deterministic tie-breaker
        return lhs.id < rhs.id
    }

    private func responsePrecedence(_ status: ParticipantStatus) -> Int {
        switch status {
        case .accepted: return 4
        case .tentative: return 3
        case .pending: return 2
        case .unknown: return 1
        case .declined: return 0
        }
    }

    private func availabilityPrecedence(_ status: AvailabilityStatus) -> Int {
        switch status {
        case .busy: return 3
        case .unavailable: return 2
        case .tentative: return 1
        case .free: return 0
        }
    }
}
