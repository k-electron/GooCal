//
//  TimelineCoordinateConverter.swift
//  GooCal
//

import Foundation
import CoreGraphics

/// Converts calendar timestamps and durations into vertical layout coordinates for the 24-hour timeline.
///
/// Operates on a fixed scale factor of 40 points per hour ($0.667\,\text{pt}/\text{minute}$), yielding
/// a total daily canvas height of 960 points. Brief meetings enforce a minimum visual height of 18 points
/// to preserve typography legibility in compact event cards.
public struct TimelineCoordinateConverter: Sendable, Equatable {
    /// Vertical scale factor in points per hour.
    public static let pointsPerHour: CGFloat = 40.0

    /// Minimum visual height in points enforced for brief events.
    public static let minimumEventHeight: CGFloat = 18.0

    /// Number of hours represented on the vertical timeline canvas.
    public static let hoursInDay: CGFloat = 24.0

    /// Total height of the 24-hour timeline canvas in points (960 pt).
    public static let totalCanvasHeight: CGFloat = 960.0

    /// Default singleton instance configured with current calendar and standard scale.
    public static let `default` = TimelineCoordinateConverter()

    public let pointsPerHour: CGFloat
    public let minimumEventHeight: CGFloat
    public let calendar: Calendar

    /// Total height of the 24-hour canvas for this converter instance.
    public var totalHeight: CGFloat {
        Self.hoursInDay * pointsPerHour
    }

    /// Points per second factor derived from pointsPerHour.
    public var pointsPerSecond: CGFloat {
        pointsPerHour / 3600.0
    }

    /// Creates a coordinate converter instance.
    ///
    /// - Parameters:
    ///   - pointsPerHour: Points allocated per hour on the canvas. Defaults to 40.
    ///   - minimumEventHeight: Minimum height in points for event blocks. Defaults to 18.
    ///   - calendar: Calendar used for start-of-day calculations. Defaults to current.
    public init(
        pointsPerHour: CGFloat = Self.pointsPerHour,
        minimumEventHeight: CGFloat = Self.minimumEventHeight,
        calendar: Calendar = .current
    ) {
        self.pointsPerHour = pointsPerHour
        self.minimumEventHeight = minimumEventHeight
        self.calendar = calendar
    }

    /// Computes the vertical Y-offset in points from 00:00:00 of the specified reference day.
    ///
    /// - Parameters:
    ///   - date: The target timestamp to position.
    ///   - referenceDate: The day whose start-of-day (00:00) represents Y = 0. If nil, `date` is used.
    /// - Returns: Vertical point offset from the start of the day.
    public func yOffset(for date: Date, relativeTo referenceDate: Date? = nil) -> CGFloat {
        let baseDate = referenceDate ?? date
        let startOfDay = calendar.startOfDay(for: baseDate)
        let elapsedSeconds = date.timeIntervalSince(startOfDay)
        return CGFloat(elapsedSeconds) * pointsPerSecond
    }

    /// Computes the proportional height in points for a given duration, enforcing the minimum height threshold.
    ///
    /// - Parameter duration: Elapsed time in seconds.
    /// - Returns: Height in points, guaranteed to be at least `minimumEventHeight`.
    public func height(for duration: TimeInterval) -> CGFloat {
        let raw = CGFloat(max(0.0, duration)) * pointsPerSecond
        return max(minimumEventHeight, raw)
    }

    /// Computes the unconstrained proportional height in points without applying minimum height threshold.
    public func rawHeight(for duration: TimeInterval) -> CGFloat {
        CGFloat(max(0.0, duration)) * pointsPerSecond
    }

    /// Computes the clamped scroll offset to anchor the given time at approximately 1/3rd from the viewport top.
    ///
    /// Anchoring current time at one-third from the top preserves visual context for recent past events
    /// while prioritizing visible canvas area for upcoming meetings throughout the day. Clamped within
    /// `[0, totalCanvasHeight - viewportHeight]`.
    ///
    /// - Parameters:
    ///   - date: The anchor time (typically current time).
    ///   - referenceDate: The active timeline day. If nil, `date` is used.
    ///   - viewportHeight: The visible height of the scroll viewport in points.
    /// - Returns: Clamped scroll offset in points.
    public func targetScrollOffset(
        for date: Date,
        relativeTo referenceDate: Date? = nil,
        viewportHeight: CGFloat
    ) -> CGFloat {
        let y = yOffset(for: date, relativeTo: referenceDate)
        let target = y - (viewportHeight / 3.0)
        let maxOffset = max(0.0, totalHeight - viewportHeight)
        return min(max(0.0, target), maxOffset)
    }

    /// Convenience overload matching `targetScrollOffset(for:viewportHeight:)`.
    public func targetScrollOffset(for date: Date, viewportHeight: CGFloat) -> CGFloat {
        targetScrollOffset(for: date, relativeTo: nil, viewportHeight: viewportHeight)
    }
}
