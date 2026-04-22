# 🚀 Demolish

**A powerful multi-pane browser for macOS that gives you up to 4 completely isolated browser instances in a single window.**

Demolish is designed for developers, researchers, and power users who need to work with multiple browser sessions simultaneously without any cross-contamination. Each pane operates as its own independent incognito browser with zero shared state.

Demolish
Swift
License

---

## ✨ Features

### 🔒 Complete Isolation

- **Independent Data Stores**: Each pane uses its own `WKWebsiteDataStore` with non-persistent storage
- **No Shared State**: Zero cookies, localStorage, sessionStorage, or cache sharing between panes
- **Separate Process Pools**: Each pane runs in its own process pool for maximum isolation
- **True Incognito**: All data is ephemeral and cleared when the app closes

### 🎨 Multiple Layout Modes

- **Tiled Layout** (`⌘⇧J`): Classic grid arrangement (1-4 panes)
- **Focused Layout** (`⌘⇧L`): Primary pane with secondary panes in L-shape
- **Rotated 3D** (`⌘⇧;`): Stunning 3D carousel with depth and rotation
- **Layered Layout** (`⌘⇧K`): Overlapping panes with depth perception
- **Manual Mode**: Drag and resize panes freely for custom arrangements

### 🎯 Smart Pane Management

- **Up to 4 Panes**: Add or remove panes with intuitive controls
- **Drag & Drop**: Reposition panes anywhere on the canvas
- **Resize Handles**: Adjust pane sizes with corner drag handles
- **Bring to Front**: Click pane numbers or use keyboard shortcuts to focus
- **Pane Cycling**: Navigate between panes with `⌘⇧[` and `⌘⇧]`

### ⌨️ Keyboard Shortcuts

App shortcuts are Shift-qualified where they would otherwise collide with common
web shortcuts (e.g. `⌘K` command palettes). Press `⌘.` to toggle **Browser capture
mode**, which temporarily suspends Demolish's shortcuts so every keystroke passes
through to the focused web view.


| Shortcut | Action                                             |
| -------- | -------------------------------------------------- |
| `⌘.`     | Toggle browser capture mode (pass all keys to web) |
| `⌘N`     | Add new browser pane                               |
| `⌘⇧W`    | Close active pane                                  |
| `⌘0`     | Toggle settings drawer                             |
| `⌘9`     | Toggle cursor highlight                            |
| `⌘1-4`   | Focus pane by number                               |
| `⌘⇧R`    | Refresh primary pane                               |
| `⌘⇧[`    | Cycle to previous pane                             |
| `⌘⇧]`    | Cycle to next pane                                 |
| `⌘⇧J`    | Switch to Tiled layout                             |
| `⌘⇧K`    | Switch to Layered layout                           |
| `⌘⇧L`    | Switch to Focused layout                           |
| `⌘⇧;`    | Switch to Rotated 3D layout                        |


### 🎨 Customization

- **Border Colors**: Assign unique colors to each pane for visual distinction
- **Zoom Controls**: Adjust content zoom per pane (Out More, Out, None, In, In More)
- **Default URL**: Set a default URL that new panes automatically load
- **Cursor Highlight**: Visual feedback for cursor position (configurable)
- **Pane Titles**: Custom titles for each pane
- **Avatar Display**: Optional avatar indicators

### 🛠️ Advanced Features

- **Custom Window Design**: Seamless title bar integration with custom controls
- **Settings Drawer**: Slide-down settings panel with quick access to all options
- **Pane Settings Menu**: Per-pane configuration (zoom, borders, titles)
- **Smooth Animations**: Spring-based transitions for all layout changes
- **Tooltips**: Contextual help with keyboard shortcut hints

---

## 🏗️ Architecture

### Project Structure

```
Demolish/                          # Repo root
├── README.md
├── Demolish.xcodeproj/
├── Demolish/                      # App source
│   ├── DemolishApp.swift          # App entry point
│   ├── ContentView.swift         # Main view managing panes and layouts
│   ├── BrowserPaneView.swift     # Individual pane UI with toolbar
│   ├── BrowserPaneViewModel.swift # View model managing isolated WKWebView
│   ├── WebViewWrapper.swift      # SwiftUI wrapper for WKWebView
│   ├── PaneContainerView.swift   # Container with drag/resize handles
│   ├── PaneFrameManager.swift    # Manages pane positions and sizes
│   ├── SettingsDrawer.swift      # Settings panel UI
│   ├── WindowConfiguration.swift # Custom window title bar setup
│   ├── CursorHighlightManager.swift
│   ├── CursorHighlightOverlay.swift
│   ├── DragHandleView.swift
│   ├── ResizeHandleView.swift
│   ├── TooltipView.swift
│   ├── PaneTransitionEffect.swift
│   └── Assets.xcassets/
├── DemolishTests/
└── DemolishUITests/
```

### Key Components

#### Isolation Architecture

Each browser pane achieves complete isolation through:

1. **Separate WKWebsiteDataStore**: `WKWebsiteDataStore.nonPersistent()` ensures no disk persistence
2. **Independent Process Pool**: Each pane uses its own `WKProcessPool`
3. **Unique Configuration**: Each `WKWebView` has its own isolated configuration

```swift
// Each pane creates its own isolated data store
let dataStore = WKWebsiteDataStore.nonPersistent()
let processPool = WKProcessPool()
let configuration = WKWebViewConfiguration()
configuration.websiteDataStore = dataStore
configuration.processPool = processPool
```

#### Layout System

The app uses a flexible frame management system:

- **PaneFrameManager**: Centralized state management for all pane positions
- **Display Configurations**: Preset layouts (Tiled, Focused, Rotated3D, Layered)
- **Manual Mode**: Free-form positioning with drag and resize
- **Smooth Transitions**: Spring animations for all layout changes

#### State Management

- **ObservableObject**: View models use Combine for reactive updates
- **@StateObject/@ObservedObject**: SwiftUI property wrappers for state
- **Frame Persistence**: Pane positions maintained across layout changes

---

## 🚀 Getting Started

### Prerequisites

- **macOS 13.0+** (Ventura or later)
- **Xcode 14.0+** with Swift 5.9+
- Basic familiarity with SwiftUI and Xcode

### Building from Source

1. **Clone the repository**
  ```bash
   git clone https://github.com/sloanal/demolish.git
   cd Demolish
  ```
2. **Open in Xcode**
  ```bash
   open Demolish.xcodeproj
  ```
3. **Build and Run**
  - Select the `Demolish` scheme
  - Choose your Mac as the destination
  - Press `⌘R` or click the Run button
4. **First Launch**
  - The app will start with one browser pane
  - Click the `+` button or press `⌘N` to add more panes
  - Press `⌘0` to open the settings drawer

### Installation (Pre-built)

1. Download the latest release from the [Releases](https://github.com/sloanal/demolish/releases) page
2. Extract the `.app` bundle
3. Move `Demolish.app` to your Applications folder
4. Open normally (no Gatekeeper bypass needed when signed + notarized)

### Publishing a New Release

Users running Demolish 1.3+ get an in-app update banner automatically when a new version is published. Follow these steps for each release:

1. **Bump the version** — In Xcode, update `MARKETING_VERSION` in the project settings (e.g. `1.4` → `1.5`)
2. **Archive** — In Xcode, select **Product → Archive**
3. **Distribute** — In the Organizer, click **Distribute App → Direct Distribution**. Xcode will sign with your Developer ID and submit to Apple's notary service automatically.
4. **Zip the `.app`** — Once exported, zip the `.app` bundle (e.g. `Demolish-1.5.zip`)
5. **Create a GitHub Release** — Go to [https://github.com/sloanal/demolish/releases/new](https://github.com/sloanal/demolish/releases/new)
  - **Tag**: the version number (e.g. `v1.5` or `1.5`)
  - **Title**: e.g. `Demolish 1.5`
  - **Description**: release notes (optional)
  - **Attach the zip** as a release asset
6. **(Optional)** Upload the zip to your website download page as well

The app checks for updates on launch and hourly. When it finds a release with a version tag newer than the running version and a `.zip` asset attached, it shows a banner prompting the user to update. Clicking "Update & Restart" downloads, extracts, replaces the app, and relaunches — all in one step.

> **Note:** Users on versions older than 1.3 don't have the updater and will need to download the new version manually one last time.

### Releasing via the Command Line (Alternative)

The release script handles archiving, signing, notarization, stapling, and zip creation in one step:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="Demolish" \
./scripts/release-macos.sh
```

To re-sign and notarize an already-exported `.app`:

```bash
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="Demolish" \
EXISTING_APP_PATH="/absolute/path/to/Demolish.app" \
./scripts/release-macos.sh
```

The script produces a `Demolish-{version}.zip` ready to attach to a GitHub Release.

Requirements:

- A valid `Developer ID Application` certificate in Keychain
- A notarytool keychain profile (`xcrun notarytool store-credentials "Demolish" --apple-id ... --team-id ...`)

---

## 📖 Usage Guide

### Basic Operations

#### Adding Panes

- Click the `+` button in the top-right toolbar
- Or press `⌘N` (up to 4 panes maximum)

#### Navigating

- Enter a URL in the address bar and press Enter
- Use back/forward buttons in each pane's toolbar
- Click the reload button to refresh the current page

#### Managing Panes

- **Close**: Click the `X` button on any pane, or press `⌘⇧W` to close the active pane
- **Focus**: Click the pane number badge, or use `⌘1-4` shortcuts
- **Cycle**: Use `⌘⇧[` and `⌘⇧]` to cycle through panes
- **Drag**: Click and drag the pane title bar to reposition
- **Resize**: Drag the corner resize handle to adjust size

### Layout Modes

#### Tiled Layout (`⌘⇧J`)

Classic grid arrangement that automatically adjusts based on pane count:

- **1 Pane**: Full screen
- **2 Panes**: Side-by-side
- **3 Panes**: 2 on top, 1 on bottom
- **4 Panes**: 2x2 grid

#### Focused Layout (`⌘⇧L`)

Primary pane takes center stage with secondary panes arranged in an L-shape:

- Primary pane: Large, top-left with 16:9 aspect ratio
- Secondary panes: Smaller panes in bottom-right corner

#### Rotated 3D (`⌘⇧;`)

Stunning 3D carousel effect:

- Panes stacked with depth and rotation
- Click pane numbers to bring them forward
- Smooth animations with perspective transforms

#### Layered Layout (`⌘⇧K`)

Overlapping panes with depth:

- Primary pane offset slightly
- Secondary panes layered behind with progressive offsets
- Creates a visual depth effect

#### Manual Mode

Free-form arrangement:

- Drag panes anywhere
- Resize to any dimensions
- Custom positioning for your workflow

### Settings & Customization

#### Settings Drawer (`⌘0`)

Access all settings from the top toolbar:

- **Default URL**: Set URL for new panes
- **Cursor Highlight**: Toggle and configure cursor tracking
- **Pane Picker**: Quick access to switch between panes
- **Layout Selector**: Switch between layout modes

#### Pane Settings Menu

Click the gear icon on any pane to access:

- **Zoom**: Adjust content zoom level
- **Border**: Toggle and change border color
- **Title**: Set custom pane title
- **Avatar**: Toggle avatar display

---

## 🔧 Technical Details

### Isolation Implementation

The isolation is achieved at multiple levels:

1. **Data Store Isolation**
  ```swift
   let dataStore = WKWebsiteDataStore.nonPersistent()
  ```
  - No cookies shared between panes
  - No localStorage/sessionStorage sharing
  - No cache sharing
  - Ephemeral storage (cleared on app close)
2. **Process Pool Isolation**
  ```swift
   let processPool = WKProcessPool()
  ```
  - Separate process pools prevent cross-pane communication
  - Each pane runs in its own WebKit process
3. **Configuration Isolation**
  - Each `WKWebView` has its own configuration
  - No shared preferences or settings

### Window Configuration

The app uses a custom window setup to achieve a seamless UI:

- **Hidden Title Bar**: `window.titleVisibility = .hidden`
- **Transparent Title Bar**: `window.titlebarAppearsTransparent = true`
- **Full-Size Content**: `window.styleMask.insert(.fullSizeContentView)`
- **No Toolbar**: Custom toolbar replaces system toolbar

This allows the custom settings drawer to sit flush with the traffic light buttons.

### Animation System

All layout transitions use SwiftUI's spring animations:

```swift
Animation.spring(response: 0.7, dampingFraction: 0.8, blendDuration: 0.3)
```

- **Response**: Controls animation speed (0.7 = smooth)
- **Damping**: Controls bounce (0.8 = minimal bounce)
- **Blend Duration**: Smooth transitions between animations

### Performance Considerations

- **Lazy Loading**: Web views are created on-demand
- **Resource Cleanup**: Proper cleanup when panes are removed
- **Efficient Updates**: Only necessary views update on state changes
- **Frame Management**: Centralized frame updates prevent layout thrashing

---

## 🎯 Use Cases

### Development & Testing

- Test multiple user sessions simultaneously
- Compare different authentication states
- Debug cookie and session issues
- Test cross-origin scenarios

### Research & Analysis

- Compare different websites side-by-side
- Monitor multiple data sources
- Research without session interference
- Analyze competitor websites

### Productivity

- Keep reference materials open while working
- Monitor multiple dashboards
- Compare documentation versions
- Multi-account management

---

## 🐛 Known Limitations

- **Maximum 4 Panes**: Current implementation limits to 4 panes (easily adjustable)
- **Non-Persistent Storage**: All data is cleared when app closes (by design)
- **No Tab Support**: Each pane is a single-page browser (future enhancement)
- **No Bookmarks**: No built-in bookmark management (future enhancement)
- **No History**: Navigation history is per-pane only (future enhancement)

---

## 🛣️ Roadmap

### Planned Features

- Tab support within panes
- Bookmark management
- Navigation history
- Developer tools integration
- Custom user agent per pane
- Screenshot/capture functionality
- Export/import pane configurations
- Resizable pane dividers (for tiled mode)
- Pane templates/presets
- Dark/light mode toggle
- Custom keyboard shortcuts

### Under Consideration

- Extension support
- Password management integration
- Session save/restore
- Multi-window support
- Pane grouping

---

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

1. **Fork the repository**
2. **Create a feature branch** (`git checkout -b feature/amazing-feature`)
3. **Commit your changes** (`git commit -m 'Add amazing feature'`)
4. **Push to the branch** (`git push origin feature/amazing-feature`)
5. **Open a Pull Request**

### Development Guidelines

- Follow SwiftUI best practices
- Maintain code style consistency
- Add comments for complex logic
- Test on multiple macOS versions
- Update documentation for new features

---

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- Built with [SwiftUI](https://developer.apple.com/xcode/swiftui/)
- Uses [WebKit](https://webkit.org/) for browser functionality
- Inspired by the need for better multi-session browser management

---

## 📧 Contact & Support

- **Issues**: [GitHub Issues](https://github.com/sloanal/demolish/issues)
- **Discussions**: [GitHub Discussions](https://github.com/sloanal/demolish/discussions)
- **Email**: [your-email@example.com](mailto:your-email@example.com)

---

## ⭐ Show Your Support

If you find Demolish useful, please consider:

- ⭐ Starring the repository
- 🐛 Reporting bugs
- 💡 Suggesting features
- 📖 Improving documentation
- 🔄 Sharing with others

---

**Made with ❤️ for the macOS community**