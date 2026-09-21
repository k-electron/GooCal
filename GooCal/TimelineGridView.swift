//
//  TimelineGridView.swift
//  GooCal
//

import SwiftUI

/// Background grid rendering vertical hour divisions and time ruler markings for the 24-hour canvas.
///
/// Anchors the temporal coordinate system by drawing horizontal hairline dividers at 40-point intervals
/// and displaying localized hour labels within the leading ruler column.
public struct TimelineGridView: View {
    public let rulerWidth: CGFloat
    public let totalHeight: CGFloat
    public let pointsPerHour: CGFloat
    public let calendar: Calendar

    /// Creates a timeline grid view.
    ///
    /// - Parameters:
    ///   - rulerWidth: Width in points allocated for the leading hour-label ruler column.
    ///   - totalHeight: Total canvas height spanning 24 hours (default 960 pt).
    ///   - pointsPerHour: Vertical spacing in points allocated per hour (default 40 pt).
    ///   - calendar: Calendar used for date-to-hour calculations.
    public init(
        rulerWidth: CGFloat = 50,
        totalHeight: CGFloat = 960,
        pointsPerHour: CGFloat = 40,
        calendar: Calendar = .current
    ) {
        self.rulerWidth = rulerWidth
        self.totalHeight = totalHeight
        self.pointsPerHour = pointsPerHour
        self.calendar = calendar
    }

    /// Formats an hour index (0..<24) into localized short hour text (e.g. "12 AM", "1 PM", or "13:00").
    public func formattedHour(for hour: Int) -> String {
        guard let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) else {
            return "\(hour):00"
        }
        return date.formatted(Date.FormatStyle().hour())
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Vertical boundary line separating ruler from event canvas
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 0.5, height: totalHeight)
                    .offset(x: rulerWidth)

                // 24 hour markings (00:00 through 23:00)
                ForEach(0..<24, id: \.self) { hour in
                    let y = CGFloat(hour) * pointsPerHour

                    // Hour label right-aligned in ruler column
                    Text(formattedHour(for: hour))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: rulerWidth - 8, alignment: .trailing)
                        .offset(x: 2, y: hour == 0 ? 2 : y - 7)

                    // Horizontal hairline divider spanning across the event canvas
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: max(0, geometry.size.width - rulerWidth), height: 0.5)
                        .offset(x: rulerWidth, y: y)
                }
            }
        }
        .frame(height: totalHeight)
    }
}

#Preview {
    ScrollView {
        TimelineGridView()
    }
    .frame(width: 320, height: 480)
}
