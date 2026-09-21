//
//  CalendarAccessBannerView.swift
//  GooCal
//

import AppKit
import SwiftUI

/// Accessible informational view displayed when macOS calendar access is denied, restricted, or ungranted.
///
/// Communicates the necessity of calendar permissions with clear macOS system iconography,
/// plain-language explanations, and an actionable deep link button directing users
/// to the Calendar privacy settings pane in macOS System Settings.
public struct CalendarAccessBannerView: View {
    public let status: CalendarAuthorizationStatus
    public var onRequestAccess: (() -> Void)?

    /// Creates a calendar access banner view.
    ///
    /// - Parameters:
    ///   - status: The current calendar authorization status. Defaults to `.denied`.
    ///   - onRequestAccess: Optional closure invoked if an explicit permission prompt can be triggered.
    public init(
        status: CalendarAuthorizationStatus = .denied,
        onRequestAccess: (() -> Void)? = nil
    ) {
        self.status = status
        self.onRequestAccess = onRequestAccess
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 6) {
                Text(titleText)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text(explanationText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if status == .notDetermined, let onRequestAccess {
                Button("Allow Calendar Access") {
                    onRequestAccess()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            } else {
                Button {
                    openSystemSettings()
                } label: {
                    Label("Open System Settings", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    public var iconName: String {
        switch status {
        case .denied, .restricted:
            return "calendar.badge.exclamationmark"
        case .notDetermined:
            return "lock.shield"
        case .authorized:
            return "checkmark.circle"
        }
    }

    public var titleText: String {
        switch status {
        case .denied, .restricted:
            return "Calendar Access Required"
        case .notDetermined:
            return "Calendar Permission Needed"
        case .authorized:
            return "Calendar Connected"
        }
    }

    public var explanationText: String {
        switch status {
        case .denied, .restricted:
            return "GooCal requires access to your calendar to display your daily schedule and upcoming meetings. Please enable Calendar access in macOS System Settings."
        case .notDetermined:
            return "GooCal requires access to your calendar to display your timeline."
        case .authorized:
            return "Calendar events are synchronized."
        }
    }

    /// Deep-links to the Privacy & Security > Calendars section of macOS System Settings.
    public func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}

#Preview("Denied State") {
    CalendarAccessBannerView(status: .denied)
        .frame(width: 360, height: 480)
}

#Preview("Not Determined State") {
    CalendarAccessBannerView(status: .notDetermined)
        .frame(width: 360, height: 480)
}
