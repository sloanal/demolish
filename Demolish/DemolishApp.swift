//
//  DemolishApp.swift
//  Demolish
//
//  App entry point for the multi-incognito browser container
//

import SwiftUI

@main
struct DemolishApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Configure window to hide gray title bar and enable full-size content view
                // This allows the custom top bar (settings drawer) to extend to the top
                // and appear flush with the traffic light buttons
                .configureWindowForCustomTitleBar()
        }
        .windowStyle(.automatic)
        .defaultSize(width: 1200, height: 800)
    }
}

