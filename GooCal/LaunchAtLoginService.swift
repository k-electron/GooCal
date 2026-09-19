//
//  LaunchAtLoginService.swift
//  GooCal
//

import Foundation
import ServiceManagement

/// Abstraction for managing macOS launch-at-login registration.
///
/// Decoupling from `ServiceManagement.SMAppService` allows deterministic unit testing
/// and fault injection without modifying system-level login items or requiring code signing entitlements.
public protocol LaunchAtLoginManaging: Sendable {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// Production implementation backed by Apple's `SMAppService.mainApp`.
///
/// Integrates with macOS 13+ Login Items settings. Marked `@unchecked Sendable`
/// because `SMAppService` is a thread-safe Objective-C framework class lacking explicit SDK concurrency annotations.
public final class SMAppServiceLaunchAtLoginManager: LaunchAtLoginManaging, @unchecked Sendable {
    private let appService: SMAppService

    public init(appService: SMAppService = .mainApp) {
        self.appService = appService
    }

    public var isEnabled: Bool {
        appService.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try appService.register()
        } else {
            try appService.unregister()
        }
    }
}

/// Default service container providing shared access to launch-at-login capabilities.
/// Supports constructor injection of any `LaunchAtLoginManaging` implementation.
public final class LaunchAtLoginService: LaunchAtLoginManaging, @unchecked Sendable {
    public static let shared = LaunchAtLoginService()

    private let manager: any LaunchAtLoginManaging

    public init(manager: any LaunchAtLoginManaging = SMAppServiceLaunchAtLoginManager()) {
        self.manager = manager
    }

    public var isEnabled: Bool {
        manager.isEnabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        try manager.setEnabled(enabled)
    }
}
