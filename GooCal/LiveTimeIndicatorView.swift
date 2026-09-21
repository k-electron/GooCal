//
//  LiveTimeIndicatorView.swift
//  GooCal
//

import SwiftUI

/// Dynamic current-time indicator line and ruler time-badge for the active day canvas.
///
/// Backed by an isolated `TimelineView` with 60-second periodic cadence to update the horizontal marker
/// and capsule badge precisely on minute boundaries without invalidating the event layout hierarchy.
public struct LiveTimeIndicatorView: View {
    public let referenceDate: Date
    public let rulerWidth: CGFloat
    public let coordinateConverter: TimelineCoordinateConverter
    public let calendar: Calendar

    /// Creates a live time indicator.
    ///
    /// - Parameters:
    ///   - referenceDate: The calendar date being inspected on the timeline.
    ///   - rulerWidth: Width of the leading time ruler column. Defaults to 50 pt.
    ///   - coordinateConverter: Converter mapping timestamps to vertical point offsets.
    ///   - calendar: Calendar used for same-day evaluation and date component extraction.
    public init(
        referenceDate: Date = Date(),
        rulerWidth: CGFloat = 50,
        coordinateConverter: TimelineCoordinateConverter? = nil,
        calendar: Calendar = .current
    ) {
        self.referenceDate = referenceDate
        self.rulerWidth = rulerWidth
        self.calendar = calendar
        self.coordinateConverter = coordinateConverter ?? TimelineCoordinateConverter(calendar: calendar)
    }

    /// Evaluates whether the specified date shares the active calendar day with `referenceDate`.
    public func isVisible(at date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: referenceDate)
    }

    /// Calculates the vertical Y-offset in points for the given timestamp.
    public func yOffset(for date: Date) -> CGFloat {
        coordinateConverter.yOffset(for: date, relativeTo: referenceDate)
    }

    /// Formats the current time for display within the ruler capsule badge.
    public func formattedTime(for date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if isVisible(at: context.date) {
                let y = yOffset(for: context.date)

                GeometryReader { geometry in
                    let canvasWidth = max(0, geometry.size.width - rulerWidth)

                    ZStack(alignment: .topLeading) {
                        // 1.5pt red horizontal marker line across the event canvas
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: canvasWidth, height: 1.5)
                            .offset(x: rulerWidth, y: y - 0.75)

                        // Small red time capsule badge positioned on the ruler
                        Text(formattedTime(for: context.date))
                            .font(.system(size: 9, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                            .frame(width: rulerWidth - 4, alignment: .trailing)
                            .offset(x: 2, y: y - 8)
                    }
                }
            }
        }
    }
}

#Preview {
    ZStack {
        TimelineGridView()
        LiveTimeIndicatorView(referenceDate: Date())
    }
    .frame(width: 320, height: 480)
}
