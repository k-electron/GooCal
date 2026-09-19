//
//  GooCalApp.swift
//  GooCal
//

import SwiftUI

/// Main entry point for the GooCal menu bar accessory application.
///
/// Operates without a Dock presence (`LSUIElement`), delegating user interactions
/// to a menu bar extra with a window-style popover and an independent Settings scene.
@main
struct GooCalApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            PopoverContentView()
                .environment(appState)
        } label: {
            HStack {
                Image(systemName: appState.menuBarIconName)
                Text(appState.menuBarTitle)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
