//
//  GooCalTests.swift
//  GooCalTests
//

import Testing
import Foundation
import SwiftUI
@testable import GooCal

@Suite("App State & Launch At Login Lifecycle")
@MainActor
struct GooCalTests {

    private final class MockLaunchAtLoginManager: LaunchAtLoginManaging, @unchecked Sendable {
        var isEnabled: Bool
        var shouldThrowError: Bool
        var thrownError: Error

        init(
            isEnabled: Bool = false,
            shouldThrowError: Bool = false,
            thrownError: Error = NSError(
                domain: "GooCalTests",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Simulated registration error"]
            )
        ) {
            self.isEnabled = isEnabled
            self.shouldThrowError = shouldThrowError
            self.thrownError = thrownError
        }

        func setEnabled(_ enabled: Bool) throws {
            if shouldThrowError {
                throw thrownError
            }
            isEnabled = enabled
        }
    }

    @Test("AppState reflects external manager's current state and menu bar defaults on initialization")
    func initializationReflectsManagerAndDefaults() {
        let disabledManager = MockLaunchAtLoginManager(isEnabled: false)
        let stateDisabled = AppState(launchAtLoginManager: disabledManager)

        #expect(!stateDisabled.isLaunchAtLoginEnabled)
        #expect(stateDisabled.menuBarTitle == "GooCal: No Upcoming Meetings")
        #expect(stateDisabled.menuBarIconName == "calendar")
        #expect(stateDisabled.statusMessage == "No upcoming meetings")
        #expect(stateDisabled.lastError == nil)

        let enabledManager = MockLaunchAtLoginManager(isEnabled: true)
        let stateEnabled = AppState(launchAtLoginManager: enabledManager)

        #expect(stateEnabled.isLaunchAtLoginEnabled)
    }

    @Test("Toggling launch-at-login propagates through manager and keeps UI state synchronized")
    func togglePropagatesAndSynchronizesState() {
        let manager = MockLaunchAtLoginManager(isEnabled: false)
        let state = AppState(launchAtLoginManager: manager)

        state.setLaunchAtLogin(enabled: true)
        #expect(manager.isEnabled)
        #expect(state.isLaunchAtLoginEnabled)
        #expect(state.lastError == nil)

        state.setLaunchAtLogin(enabled: false)
        #expect(!manager.isEnabled)
        #expect(!state.isLaunchAtLoginEnabled)
        #expect(state.lastError == nil)

        state.launchAtLoginBinding.wrappedValue = true
        #expect(manager.isEnabled)
        #expect(state.isLaunchAtLoginEnabled)
    }

    @Test("Registration failures maintain consistent state with manager and capture error outcome")
    func failurePreservesConsistencyAndCapturesError() {
        let failureError = NSError(
            domain: "TestDomain",
            code: 100,
            userInfo: [NSLocalizedDescriptionKey: "Access denied by system policy"]
        )

        let manager = MockLaunchAtLoginManager(
            isEnabled: false,
            shouldThrowError: true,
            thrownError: failureError
        )
        let state = AppState(launchAtLoginManager: manager)

        state.setLaunchAtLogin(enabled: true)

        #expect(!state.isLaunchAtLoginEnabled)
        #expect(state.lastError != nil)
        #expect(state.statusMessage.contains("Access denied by system policy"))

        let enabledFailingManager = MockLaunchAtLoginManager(
            isEnabled: true,
            shouldThrowError: true,
            thrownError: failureError
        )
        let stateEnabled = AppState(launchAtLoginManager: enabledFailingManager)

        stateEnabled.setLaunchAtLogin(enabled: false)

        #expect(stateEnabled.isLaunchAtLoginEnabled)
        #expect(stateEnabled.lastError != nil)
        #expect(stateEnabled.statusMessage.contains("Access denied by system policy"))
    }

    @Test("LaunchAtLoginService forwards inspection and mutation requests to configured manager")
    func serviceDelegatesToUnderlyingManager() throws {
        let mock = MockLaunchAtLoginManager(isEnabled: false)
        let service = LaunchAtLoginService(manager: mock)

        #expect(!service.isEnabled)

        try service.setEnabled(true)
        #expect(mock.isEnabled)
        #expect(service.isEnabled)
    }
}
