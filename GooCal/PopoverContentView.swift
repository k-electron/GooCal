//
//  PopoverContentView.swift
//  GooCal
//

import AppKit
import SwiftUI

/// Main popover view displayed upon clicking the menu bar extra.
///
/// Serves as the primary lightweight interface for an accessory app, displaying
/// current event status and facilitating navigation to configuration scenes.
public struct PopoverContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(appState.menuBarTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(appState.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            Divider()

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
        }
        .padding(14)
        .frame(width: 300)
    }
}

#Preview {
    PopoverContentView()
        .environment(AppState())
}
