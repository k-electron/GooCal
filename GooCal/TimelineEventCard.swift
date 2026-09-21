//
//  TimelineEventCard.swift
//  GooCal
//

import SwiftUI

/// Visual card presentation for a placed calendar event on the daily timeline.
///
/// Implements macOS Calendar visual conventions with a prominent leading color bar,
/// translucent background tint, high-contrast typography, multi-day continuation edge styling,
/// and overflow count indicators for dense overlaps.
public struct TimelineEventCard: View {
    public let placedEvent: PlacedEvent

    /// Creates an event card for the specified placed event.
    public init(placedEvent: PlacedEvent) {
        self.placedEvent = placedEvent
    }

    /// Color derived directly from the source macOS Calendar.
    public var calendarColor: Color {
        Color(cgColor: placedEvent.event.calendarColor)
    }

    /// Formatted time range string (e.g. "10:00 AM – 11:30 AM").
    public var formattedTimeRange: String {
        let start = placedEvent.event.startDate.formatted(date: .omitted, time: .shortened)
        let end = placedEvent.event.endDate.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    /// Shape defining the card boundaries and corner radii.
    ///
    /// Flattens the top edge if continuing from yesterday, and flattens the bottom edge
    /// if continuing into tomorrow, visually reinforcing temporal continuity across midnight.
    public var cardShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: placedEvent.spansFromYesterday ? 0 : 4,
            bottomLeadingRadius: placedEvent.spansIntoTomorrow ? 0 : 4,
            bottomTrailingRadius: placedEvent.spansIntoTomorrow ? 0 : 4,
            topTrailingRadius: placedEvent.spansFromYesterday ? 0 : 4
        )
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Prominent 3pt leading vertical indicator bar
            Rectangle()
                .fill(calendarColor)
                .frame(width: 3)

            // Content container
            VStack(alignment: .leading, spacing: 1) {
                // Header / title row with optional continuation up arrow
                HStack(alignment: .center, spacing: 3) {
                    if placedEvent.spansFromYesterday {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }

                    Text(placedEvent.event.title.isEmpty ? "No Title" : placedEvent.event.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if placedEvent.height < 32 && placedEvent.overflowCount > 0 {
                        Spacer(minLength: 0)
                        Text("+\(placedEvent.overflowCount) more")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.12), in: Capsule())
                    }

                    if placedEvent.height < 32 && placedEvent.spansIntoTomorrow {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }

                // Time range displayed when height accommodates two lines
                if placedEvent.height >= 32 {
                    Text(formattedTimeRange)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Footer row for overflow pill badge and multi-day continuation down arrow
                if placedEvent.height >= 32 && (placedEvent.overflowCount > 0 || placedEvent.spansIntoTomorrow) {
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        if placedEvent.overflowCount > 0 {
                            Text("+\(placedEvent.overflowCount) more")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.12), in: Capsule())
                        }

                        Spacer(minLength: 0)

                        if placedEvent.spansIntoTomorrow {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, placedEvent.height <= 20 ? 1 : 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: placedEvent.height)
        .background(cardShape.fill(calendarColor.opacity(0.18)))
        .overlay(cardShape.strokeBorder(calendarColor.opacity(0.3), lineWidth: 1))
        .clipShape(cardShape)
    }
}

#Preview {
    let sampleEvent = CalendarEvent(
        title: "Sprint Planning",
        startDate: Date(),
        endDate: Date().addingTimeInterval(3600)
    )
    let placed = PlacedEvent(
        event: sampleEvent,
        effectiveStartDate: Date(),
        effectiveEndDate: Date().addingTimeInterval(3600),
        spansFromYesterday: false,
        spansIntoTomorrow: false,
        yOffset: 400,
        height: 60,
        columnIndex: 0,
        totalColumns: 1
    )
    return TimelineEventCard(placedEvent: placed)
        .frame(width: 200)
        .padding()
}
