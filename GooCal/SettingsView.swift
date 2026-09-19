//
//  SettingsView.swift
//  GooCal
//

import SwiftUI

/// Preferences window content for configuring application-level behavior.
///
/// Interacts with `AppState` two-way bindings to coordinate persistence and system service registration.
public struct SettingsView: View {
    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: appState.launchAtLoginBinding)
                Text("Registers GooCal with macOS Login Items to launch automatically on login.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let lastError = appState.lastError {
                    Label(lastError.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("General")
            }
        }
        .formStyle(.grouped)
        .frame(width: 350, height: 180)
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
}
