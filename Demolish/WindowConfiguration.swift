//
//  WindowConfiguration.swift
//  Demolish
//
//  Window configuration helper to remove the default gray title bar
//  and enable full-size content view for custom top bar
//

import SwiftUI
import AppKit

/// Window delegate that ensures toolbar stays removed when window regains focus
class WindowConfigurationDelegate: NSObject, NSWindowDelegate {
    private var toolbarCheckTimer: Timer?
    private weak var observedWindow: NSWindow?
    
    func windowDidBecomeKey(_ notification: Notification) {
        // Re-apply configuration when window becomes key (gains focus)
        if let window = notification.object as? NSWindow {
            configureWindow(window)
            startPeriodicCheck(for: window)
        }
    }
    
    func windowDidBecomeMain(_ notification: Notification) {
        // Re-apply configuration when window becomes main
        if let window = notification.object as? NSWindow {
            configureWindow(window)
            startPeriodicCheck(for: window)
        }
    }
    
    func windowWillClose(_ notification: Notification) {
        // Stop timer when window closes
        stopPeriodicCheck()
    }
    
    /// Starts a periodic timer to aggressively check and remove toolbar
    func startPeriodicCheck(for window: NSWindow) {
        stopPeriodicCheck()
        observedWindow = window
        
        // Check every 0.1 seconds to catch any toolbar reappearance immediately
        toolbarCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let window = self?.observedWindow else {
                self?.stopPeriodicCheck()
                return
            }
            // Aggressively remove toolbar if it reappears
            if window.toolbar != nil {
                window.toolbar?.isVisible = false
                window.toolbar = nil
            }
            // Also re-apply other settings
            self?.configureWindow(window)
        }
    }
    
    private func stopPeriodicCheck() {
        toolbarCheckTimer?.invalidate()
        toolbarCheckTimer = nil
        observedWindow = nil
    }
    
    /// Configures the NSWindow to remove the gray title bar while keeping traffic lights
    func configureWindow(_ window: NSWindow) {
        // Hide the title text (no standard title shown)
        window.titleVisibility = .hidden
        
        // Make the title bar transparent (removes gray background)
        window.titlebarAppearsTransparent = true
        
        // Enable full-size content view so SwiftUI content can extend to the top
        window.styleMask.insert(.fullSizeContentView)
        
        // CRITICAL: Remove any existing toolbar to eliminate the gray bar overlay
        // Do this aggressively - check multiple times
        if let toolbar = window.toolbar {
            toolbar.isVisible = false
        }
        window.toolbar = nil
        
        // Double-check immediately after setting to nil
        DispatchQueue.main.async {
            if window.toolbar != nil {
                window.toolbar?.isVisible = false
                window.toolbar = nil
            }
        }
        
        // Force immediate update
        window.contentView?.needsLayout = true
    }
}

/// App delegate extension to monitor app activation
extension WindowConfigurationDelegate {
    private static var globalTimer: Timer?
    
    static func setupAppActivationObserver() {
        // Start a global timer that checks ALL windows periodically
        startGlobalToolbarRemovalTimer()
        
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            // When app becomes active, aggressively re-configure all windows
            for window in NSApplication.shared.windows {
                shared.configureWindow(window)
            }
        }
        
        // Also monitor when windows are created
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let window = notification.object as? NSWindow {
                shared.configureWindow(window)
            }
        }
    }
    
    /// Global timer that aggressively removes toolbar from ALL windows
    private static func startGlobalToolbarRemovalTimer() {
        globalTimer?.invalidate()
        
        // Check all windows every 0.05 seconds (very aggressive)
        globalTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            for window in NSApplication.shared.windows {
                // Aggressively remove toolbar if it exists
                if window.toolbar != nil {
                    window.toolbar?.isVisible = false
                    window.toolbar = nil
                }
                // Re-apply other settings
                shared.configureWindow(window)
            }
        }
    }
    
    static let shared = WindowConfigurationDelegate()
}

/// View modifier that configures the NSWindow to hide the title bar
/// and enable full-size content view, allowing custom UI to extend to the top
struct WindowConfigurationModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(WindowConfigurationHelper())
    }
}

/// Helper view that configures the window when it appears
private struct WindowConfigurationHelper: NSViewRepresentable {
    // Store the delegate as a static to persist across view updates
    private static let windowDelegate = WindowConfigurationDelegate.shared
    private static var hasSetupObserver = false
    
    func makeNSView(context: Context) -> NSView {
        // Setup app activation observer once
        if !Self.hasSetupObserver {
            Self.hasSetupObserver = true
            WindowConfigurationDelegate.setupAppActivationObserver()
        }
        
        let view = NSView()
        
        // Configure the window as soon as the view is added to the window hierarchy
        // Use multiple dispatch strategies to ensure configuration is applied early
        DispatchQueue.main.async {
            if let window = view.window {
                configureWindow(window)
                // Set the delegate to monitor window focus changes
                if window.delegate !== Self.windowDelegate {
                    window.delegate = Self.windowDelegate
                }
                // Start aggressive periodic checking
                Self.windowDelegate.startPeriodicCheck(for: window)
            } else {
                // If window isn't available yet, try again after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                    if let window = view.window {
                        configureWindow(window)
                        if window.delegate !== Self.windowDelegate {
                            window.delegate = Self.windowDelegate
                        }
                        Self.windowDelegate.startPeriodicCheck(for: window)
                    } else {
                        // Try one more time with a slightly longer delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let window = view.window {
                                configureWindow(window)
                                if window.delegate !== Self.windowDelegate {
                                    window.delegate = Self.windowDelegate
                                }
                                Self.windowDelegate.startPeriodicCheck(for: window)
                            }
                        }
                    }
                }
            }
        }
        
        // Also try to configure when the view moves to a window
        view.postsFrameChangedNotifications = false
        view.postsBoundsChangedNotifications = false
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-apply configuration whenever the view updates to ensure it persists
        // This is critical to prevent visual regressions when the window gains/loses focus
        // or when the app is switched away and back
        if let window = nsView.window {
            configureWindow(window)
            // Ensure delegate is set to monitor focus changes
            if window.delegate !== Self.windowDelegate {
                window.delegate = Self.windowDelegate
            }
            // Ensure periodic check is running
            Self.windowDelegate.startPeriodicCheck(for: window)
        }
    }
    
    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        // Clean up if needed
    }
    
    /// Configures the NSWindow to remove the gray title bar while keeping traffic lights
    /// This configuration is applied persistently to prevent visual regressions
    private func configureWindow(_ window: NSWindow) {
        // First, apply the delegate's configuration (handles toolbar removal)
        Self.windowDelegate.configureWindow(window)
        
        // Then apply additional comprehensive configuration
        // Hide the title text (no standard title shown)
        window.titleVisibility = .hidden
        
        // Make the title bar transparent (removes gray background)
        window.titlebarAppearsTransparent = true
        
        // Enable full-size content view so SwiftUI content can extend to the top
        // This allows our custom top bar to sit flush with the traffic light buttons
        window.styleMask.insert(.fullSizeContentView)
        
        // CRITICAL: Remove any existing toolbar to eliminate the gray bar overlay
        // This is essential to prevent the system toolbar from blocking our custom UI
        // First, hide the toolbar if it exists
        if let toolbar = window.toolbar {
            toolbar.isVisible = false
        }
        // Then remove it entirely
        window.toolbar = nil
        
        // Ensure the window maintains these settings
        // This prevents the system from reverting to default appearance
        window.isMovableByWindowBackground = false
        
        // Force a layout update to ensure changes take effect immediately
        window.contentView?.needsLayout = true
        window.contentView?.layoutSubtreeIfNeeded()
        
        // Ensure the content view can receive mouse events in the title bar area
        // This is critical to allow our custom buttons to be clickable
        if let contentView = window.contentView {
            // Note: acceptsTouchEvents is deprecated, but we'll keep it for compatibility
            // The default behavior should work for mouse events
            if #available(macOS 10.12.2, *) {
                // Use allowedTouchTypes for newer macOS versions if needed
                // For now, mouse events should work without this
            } else {
                contentView.acceptsTouchEvents = true
            }
        }
        
        // Store configuration in user defaults to persist across app launches
        // This is a defensive measure to ensure settings don't get reset
        UserDefaults.standard.set(true, forKey: "windowTitleBarHidden")
    }
}

extension View {
    /// Applies window configuration to hide the title bar and enable full-size content view
    /// This should be applied to the root view in the WindowGroup
    func configureWindowForCustomTitleBar() -> some View {
        modifier(WindowConfigurationModifier())
    }
}

