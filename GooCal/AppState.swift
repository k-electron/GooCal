//
//  AppState.swift
//  GooCal
//

import SwiftUI
import Observation

/// Central state store for GooCal menu bar and settings presentation.
///
/// Marked `@MainActor` and `@Observable` to guarantee thread-safe UI binding updates
/// with fine-grained view invalidation under Swift concurrency.
@Observable
@MainActor
public final class AppState {
    public var menuBarTitle: String
    public var menuBarIconName: String
    public var isLaunchAtLoginEnabled: Bool
    public var statusMessage: String
    public private(set) var lastError: (any Error)?

    private let launchAtLoginManager: any LaunchAtLoginManaging

    /// Creates an application state instance.
    ///
    /// Accepts a custom `LaunchAtLoginManaging` to enable deterministic unit testing
    /// without mutating system-wide login items.
    public init(
        launchAtLoginManager: any LaunchAtLoginManaging = SMAppServiceLaunchAtLoginManager(),
        menuBarTitle: String = "GooCal: No Upcoming Meetings",
        menuBarIconName: String = "calendar",
        statusMessage: String = "No upcoming meetings"
    ) {
        self.launchAtLoginManager = launchAtLoginManager
        self.menuBarTitle = menuBarTitle
        self.menuBarIconName = menuBarIconName
        self.statusMessage = statusMessage
        self.isLaunchAtLoginEnabled = launchAtLoginManager.isEnabled
        self.lastError = nil
    }

    /// Two-way SwiftUI binding bridging toggle controls directly to managed login registration.
    public var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { self.isLaunchAtLoginEnabled },
            set: { self.setLaunchAtLogin(enabled: $0) }
        )
    }

    /// Synchronizes login item registration with macOS ServiceManagement.
    ///
    /// If registration or unregistration throws (e.g. system authorization failure),
    /// the error is captured, user status is updated, and `isLaunchAtLoginEnabled`
    /// stays synchronized with the manager's actual state to prevent misleading UI indicators.
    public func setLaunchAtLogin(enabled: Bool) {
        do {
            try launchAtLoginManager.setEnabled(enabled)
            isLaunchAtLoginEnabled = launchAtLoginManager.isEnabled
            statusMessage = enabled ? "Launch at login enabled" : "Launch at login disabled"
            lastError = nil
        } catch {
            isLaunchAtLoginEnabled = launchAtLoginManager.isEnabled
            statusMessage = "Failed to update launch at login: \(error.localizedDescription)"
            lastError = error
        }
    }
}
