# Demolish - Multi-Incognito Browser Container

A macOS app that provides up to 4 independent, isolated browser panes in a single window. Each pane behaves like its own incognito browser with no shared cookies, localStorage, sessionStorage, or cache.

## Features

- **Independent Browser Panes**: Up to 4 isolated browser instances in one window
- **Complete Isolation**: Each pane uses its own `WKWebsiteDataStore` with non-persistent storage
- **Tiled Layout**: Automatic layout adjustment based on the number of panes (1-4)
- **Browser Controls**: Each pane has URL bar, back, forward, and reload buttons
- **Easy Management**: Add panes with the + button, remove them with the X button on each pane

## Project Structure

```
Demolish/
├── DemolishApp.swift          # App entry point
├── ContentView.swift           # Main view managing panes and layout
├── BrowserPaneView.swift       # Individual pane UI with toolbar
├── BrowserPaneViewModel.swift  # View model managing isolated WKWebView
├── WebViewWrapper.swift        # SwiftUI wrapper for WKWebView
└── README.md                   # This file
```

## How Isolation Works

Each browser pane is completely isolated through:

1. **Separate WKWebsiteDataStore**: Each pane creates its own `WKWebsiteDataStore.nonPersistent()` instance. This ensures:
   - No shared cookies between panes
   - No shared localStorage or sessionStorage
   - No shared cache
   - No persistence to disk (ephemeral storage)

2. **Separate Process Pool**: Each pane uses its own `WKProcessPool`, providing additional isolation at the process level.

3. **Independent WKWebView Configuration**: Each pane's web view is configured with its own data store and process pool.

## Setup Instructions

### Creating the Xcode Project

1. Open Xcode and create a new project:
   - Choose "macOS" → "App"
   - Product Name: `Demolish`
   - Interface: `SwiftUI`
   - Language: `Swift`
   - Uncheck "Use Core Data" and "Include Tests" (optional)

2. Replace the default files:
   - Delete the auto-generated `ContentView.swift` and `DemolishApp.swift` (or `App.swift`)
   - Copy all the Swift files from this project into your Xcode project

3. File organization in Xcode:
   ```
   Demolish/
   ├── DemolishApp.swift
   ├── ContentView.swift
   ├── BrowserPaneView.swift
   ├── BrowserPaneViewModel.swift
   └── WebViewWrapper.swift
   ```

### Build and Run

1. Select your target (Demolish) in Xcode
2. Choose a destination (e.g., "My Mac")
3. Press `Cmd + R` or click the Run button
4. The app should launch with one browser pane ready to use

## Usage

1. **Add a Pane**: Click the `+` button in the top-right corner (up to 4 panes)
2. **Navigate**: Enter a URL in the text field and press Enter or click "Go"
3. **Browser Controls**: Use the back, forward, and reload buttons in each pane's toolbar
4. **Remove a Pane**: Click the `X` button in the top-left of any pane's toolbar

## Layout Behavior

- **1 Pane**: Fills the entire content area
- **2 Panes**: Split vertically (top and bottom)
- **3 Panes**: 2 panes on top, 1 pane on bottom
- **4 Panes**: 2x2 grid layout

## Technical Details

### AppKit Interop

The app uses `NSViewRepresentable` to bridge `WKWebView` (AppKit/UIKit) with SwiftUI:

- `WebViewWrapper` wraps `WKWebView` as a SwiftUI view
- Uses a `Coordinator` pattern to handle `WKNavigationDelegate` callbacks
- Updates the view model state based on navigation events

### State Management

- Uses `@StateObject` and `@ObservedObject` for unidirectional data flow
- `BrowserPaneViewModel` manages the web view state and isolation
- `ContentView` manages the collection of panes

### Extensibility

The code is structured to be easily extended:

- Add new toolbar controls in `BrowserPaneView`
- Modify layout logic in `ContentView.paneLayout`
- Extend `BrowserPaneViewModel` with additional browser features
- Adjust isolation settings in `BrowserPaneViewModel.init()`

## Limitations and Notes

- **Non-persistent Storage**: Since we use `nonPersistent()` data stores, all data (cookies, localStorage, etc.) is lost when the app closes. This is by design for true incognito behavior.
- **Maximum 4 Panes**: The current implementation limits to 4 panes, but this can be easily adjusted in `ContentView.maxPanes`.
- **Layout**: The current layout is fixed (not resizable by dragging dividers). This can be enhanced with `GeometryReader` and drag gestures if needed.

## Future Enhancements

Potential improvements for later:

- Resizable pane dividers
- Tab support within panes
- Bookmark management
- Developer tools integration
- Custom user agent per pane
- Screenshot/capture functionality
- Export/import pane configurations

