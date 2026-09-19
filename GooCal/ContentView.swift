//
//  ContentView.swift
//  GooCal
//

import SwiftUI

/// Compatibility alias preserving external view references while delegating to `PopoverContentView`.
public struct ContentView: View {
    public init() {}

    public var body: some View {
        PopoverContentView()
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
