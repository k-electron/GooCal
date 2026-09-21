//
//  DailyTimelineView.swift
//  GooCal
//

import SwiftUI

/// Main 24-hour vertical daily timeline view for GooCal.
///
/// Combines the 24-hour background time grid, clustered and precedence-ranked event cards,
/// dynamic minute-cadence live time indicator, and automated viewport positioning that anchors
/// the current time at approximately one-third from the viewport top on appearance.
public struct DailyTimelineView: View {
    public let events: [CalendarEvent]
    public let selectedDate: Date
    public let viewportHeight: CGFloat
    public let rulerWidth: CGFloat
    public let coordinateConverter: TimelineCoordinateConverter
    public let calendar: Calendar
    public let authorizationStatus: CalendarAuthorizationStatus

    /// Creates a daily timeline view.
    ///
    /// - Parameters:
    ///   - events: Calendar events to lay out and render.
    ///   - selectedDate: The active calendar day being displayed. Defaults to current date.
    ///   - viewportHeight: Visible height of the scrolling viewport in points. Defaults to 480 pt.
    ///   - rulerWidth: Width in points for the time ruler. Defaults to 50 pt.
    ///   - coordinateConverter: Converter responsible for time-to-coordinate mapping. Defaults to `.default`.
    ///   - calendar: Calendar used for date operations. Defaults to `.current`.
    ///   - authorizationStatus: Current system calendar authorization status. Defaults to `.authorized`.
    public init(
        events: [CalendarEvent],
        selectedDate: Date = Date(),
        viewportHeight: CGFloat = 480,
        rulerWidth: CGFloat = 50,
        coordinateConverter: TimelineCoordinateConverter? = nil,
        calendar: Calendar = .current,
        authorizationStatus: CalendarAuthorizationStatus = .authorized
    ) {
        self.events = events
        self.selectedDate = selectedDate
        self.viewportHeight = viewportHeight
        self.rulerWidth = rulerWidth
        self.calendar = calendar
        self.authorizationStatus = authorizationStatus
        self.coordinateConverter = coordinateConverter ?? TimelineCoordinateConverter(calendar: calendar)
    }

    /// Placed event cards computed via `TimelineLayoutEngine`.
    public var placedEvents: [PlacedEvent] {
        if calendar == TimelineLayoutEngine.shared.calendar {
            return TimelineLayoutEngine.shared.layoutEvents(
                events,
                for: selectedDate,
                coordinateConverter: coordinateConverter
            )
        } else {
            return TimelineLayoutEngine(calendar: calendar).layoutEvents(
                events,
                for: selectedDate,
                coordinateConverter: coordinateConverter
            )
        }
    }

    /// Calculates the vertical scroll target offset anchoring current time at one-third of the viewport.
    public var targetScrollOffset: CGFloat {
        targetScrollOffset(for: Date.now)
    }

    /// Calculates the target scroll offset for a specific anchor date.
    public func targetScrollOffset(for date: Date) -> CGFloat {
        coordinateConverter.targetScrollOffset(
            for: date,
            relativeTo: selectedDate,
            viewportHeight: viewportHeight
        )
    }

    public var body: some View {
        if authorizationStatus == .denied || authorizationStatus == .restricted {
            CalendarAccessBannerView(status: authorizationStatus)
                .frame(height: viewportHeight)
        } else {
            ScrollView([.vertical], showsIndicators: true) {
                ScrollViewReader { proxy in
                ZStack(alignment: .topLeading) {
                    // Background 24-hour time grid and ruler labels
                    TimelineGridView(
                        rulerWidth: rulerWidth,
                        totalHeight: coordinateConverter.totalHeight,
                        pointsPerHour: coordinateConverter.pointsPerHour,
                        calendar: calendar
                    )

                    // Invisible scroll target view anchored to one-third viewport offset
                    Color.clear
                        .frame(width: 1, height: 1)
                        .offset(y: targetScrollOffset)
                        .id("target_scroll_anchor")

                    // Placed event cards positioned across parallel columns
                    GeometryReader { geometry in
                        let canvasWidth = max(0, geometry.size.width - rulerWidth)

                        ForEach(placedEvents) { placed in
                            let columnWidth = canvasWidth / CGFloat(placed.totalColumns)
                            let x = rulerWidth + CGFloat(placed.columnIndex) * columnWidth
                            let cardWidth = max(0, columnWidth - (placed.totalColumns > 1 ? 2.0 : 4.0))

                            TimelineEventCard(placedEvent: placed)
                                .frame(width: cardWidth, height: placed.height)
                                .offset(x: x, y: placed.yOffset)
                        }
                    }

                    // Live current-time marker line and capsule badge
                    LiveTimeIndicatorView(
                        referenceDate: selectedDate,
                        rulerWidth: rulerWidth,
                        coordinateConverter: coordinateConverter,
                        calendar: calendar
                    )
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: coordinateConverter.totalHeight)
                .task(id: selectedDate) {
                    // Initial immediate scroll positioning
                    proxy.scrollTo("target_scroll_anchor", anchor: .top)

                    // Asynchronous dispatch to accommodate initial window and popover frame stabilization.
                    // Automatically cancelled if the view is dismissed or selectedDate changes.
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo("target_scroll_anchor", anchor: .top)
                }
            }
        }
    }
}
}

#Preview {
    let now = Date()
    let sampleEvents = [
        CalendarEvent(
            title: "Design Review",
            startDate: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: now)!,
            endDate: Calendar.current.date(bySettingHour: 11, minute: 0, second: 0, of: now)!
        ),
        CalendarEvent(
            title: "Architecture Sync",
            startDate: Calendar.current.date(bySettingHour: 10, minute: 30, second: 0, of: now)!,
            endDate: Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: now)!
        )
    ]

    DailyTimelineView(events: sampleEvents, selectedDate: now)
        .frame(width: 320, height: 480)
}
