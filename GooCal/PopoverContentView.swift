//
//  PopoverContentView.swift
//  GooCal
//

import AppKit
import SwiftUI

/// Main popover view displayed upon clicking the menu bar extra.
///
/// Features a date header with single-day forward/backward and today navigation,
/// a continuous 24-hour vertical timeline view with event cards and live time indicator,
/// and a fixed footer hosting application preferences and termination controls.
public struct PopoverContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Fixed Header
            headerView

            Divider()

            // Main Content Area
            mainContentView

            Divider()

            // Fixed Footer
            footerView
        }
        .frame(width: 360)
        .task {
            await appState.refreshEvents()
        }
    }

    // MARK: - Header

    private var isToday: Bool {
        Calendar.current.isDateInToday(appState.selectedDate)
    }

    private var formattedDateTitle: String {
        let calendar = Calendar.current
        let monthDay = appState.selectedDate.formatted(.dateTime.month().day())
        if calendar.isDateInToday(appState.selectedDate) {
            return "Today, \(monthDay)"
        } else if calendar.isDateInTomorrow(appState.selectedDate) {
            return "Tomorrow, \(monthDay)"
        } else if calendar.isDateInYesterday(appState.selectedDate) {
            return "Yesterday, \(monthDay)"
        } else {
            return appState.selectedDate.formatted(.dateTime.weekday(.wide).month().day())
        }
    }

    private var eventSummaryText: String {
        let count = appState.events.count
        let eventWord = count == 1 ? "event" : "events"
        return isToday ? "\(count) \(eventWord) today" : "\(count) \(eventWord)"
    }

    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formattedDateTitle)
                    .font(.headline)
                    .lineLimit(1)

                Text(eventSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                if !isToday {
                    Button("Today") {
                        Task {
                            await appState.setSelectedDate(Date())
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    Task {
                        if let prev = Calendar.current.date(byAdding: .day, value: -1, to: appState.selectedDate) {
                            await appState.setSelectedDate(prev)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Previous Day")
                .accessibilityLabel("Previous Day")

                Button {
                    Task {
                        if let next = Calendar.current.date(byAdding: .day, value: 1, to: appState.selectedDate) {
                            await appState.setSelectedDate(next)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Next Day")
                .accessibilityLabel("Next Day")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Main Content Area

    @ViewBuilder
    private var mainContentView: some View {
        if appState.calendarAuthorizationStatus == .denied || appState.calendarAuthorizationStatus == .restricted {
            CalendarAccessBannerView(status: appState.calendarAuthorizationStatus)
                .frame(height: 480)
        } else {
            DailyTimelineView(
                events: appState.events,
                selectedDate: appState.selectedDate,
                viewportHeight: 480,
                authorizationStatus: appState.calendarAuthorizationStatus
            )
            .frame(height: 480)
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                openSettings()
                // Accessory apps (LSUIElement) do not take active focus when presenting secondary windows,
                // requiring explicit activation so the settings window surfaces in front of other applications.
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Settings...", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

#Preview {
    PopoverContentView()
        .environment(AppState())
}
