//
//  WebViewWrapper.swift
//  Demolish
//
//  SwiftUI wrapper for WKWebView to integrate with SwiftUI views
//

import SwiftUI
import AppKit
import OSLog
internal import WebKit

// Custom wrapper to ensure mouse events work properly
// This wrapper is completely transparent to mouse events - all events pass through to the web view
class WebViewWrapperView: NSView {
    var webView: WKWebView? {
        didSet {
            // Remove old web view
            oldValue?.removeFromSuperview()
            // Add new web view
            if let webView = webView {
                webView.frame = bounds
                webView.autoresizingMask = [.width, .height]
                addSubview(webView)
            }
        }
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // When the view is added to a window, ensure the web view can receive events
        if window != nil, let webView = webView {
            // Ensure the web view is properly configured
            webView.allowsMagnification = true
            webView.allowsBackForwardNavigationGestures = false
            // Zoom is now controlled by the view model's zoomSetting
            
            // Ensure the web view can become first responder for drag operations
            // This is critical for drag events to work
            DispatchQueue.main.async {
                // Make the web view first responder so it can receive all mouse events
                if webView.window != nil {
                    webView.window?.makeFirstResponder(webView)
                }
            }
        }
    }
    
    override func layout() {
        super.layout()
        webView?.frame = bounds
    }
    
    // Make the wrapper completely transparent to mouse events
    // All events should go directly to the web view subview
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Always delegate to the web view - don't handle events ourselves
        if let webView = webView, bounds.contains(point) {
            let webViewPoint = convert(point, to: webView)
            return webView.hitTest(webViewPoint)
        }
        return nil
    }
    
    // Don't accept mouse events ourselves - let them go to the web view
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        // Forward to web view
        return webView?.acceptsFirstMouse(for: event) ?? true
    }
    
    // Ensure we don't interfere with window dragging
    override var mouseDownCanMoveWindow: Bool {
        return false
    }
    
    // Don't accept first responder - let the web view handle it
    override var acceptsFirstResponder: Bool {
        return false
    }
}

struct WebViewWrapper: NSViewRepresentable {
    let viewModel: BrowserPaneViewModel
    let zoomSetting: ZoomSetting // Observe zoom setting changes
    
    func makeNSView(context: Context) -> WebViewWrapperView {
        let wrapperView = WebViewWrapperView()
        wrapperView.wantsLayer = true
        // Set wrapper background to white to match web content
        wrapperView.layer?.backgroundColor = NSColor.white.cgColor
        
        // Check if we can safely reuse an existing web view
        let webView: WKWebView
        if let existingWebView = viewModel.webView {
            // If it has a superview, remove it first
            if existingWebView.superview != nil {
                existingWebView.removeFromSuperview()
            }
            webView = existingWebView
            webView.navigationDelegate = context.coordinator
            webView.uiDelegate = context.coordinator
            
            // Ensure message handler is registered for reused web view
            // Remove old handler first if it exists, then add new one
            webView.configuration.userContentController.removeScriptMessageHandler(forName: "consoleLog")
            webView.configuration.userContentController.add(context.coordinator, name: "consoleLog")
        } else {
            // Create a new web view instance
            webView = WKWebView(frame: .zero, configuration: viewModel.webViewConfiguration)
            webView.navigationDelegate = context.coordinator
            webView.uiDelegate = context.coordinator
            webView.allowsMagnification = true
            webView.allowsBackForwardNavigationGestures = false
            // Zoom will be applied by viewModel.setWebView() which calls applyZoomSetting()
            // Set drawsTransparentBackground to false so WKWebView draws white background
            // This prevents gray background from showing through
            webView.setValue(false, forKey: "drawsTransparentBackground")
            
            // Register message handler for console logging
            webView.configuration.userContentController.add(context.coordinator, name: "consoleLog")
            
            viewModel.setWebView(webView)
        }
        
        wrapperView.webView = webView
        
        return wrapperView
    }
    
    func updateNSView(_ nsView: WebViewWrapperView, context: Context) {
        guard let webView = nsView.webView else { return }
        
        // Ensure delegates are set
        if webView.navigationDelegate !== context.coordinator {
            webView.navigationDelegate = context.coordinator
        }
        if webView.uiDelegate !== context.coordinator {
            webView.uiDelegate = context.coordinator
        }
        
        // Message handler is already registered in makeNSView, no need to re-register here
        
        // Ensure view model reference
        if viewModel.webView !== webView {
            viewModel.setWebView(webView)
        }
        
        // Apply the current zoom setting from the view model
        // This ensures zoom persists when navigating between pages and updates immediately when changed
        // The zoomSetting parameter ensures this method is called when zoom changes
        viewModel.applyZoomSetting()
        
        // Ensure WebView draws white background (not transparent) to prevent gray from showing through
        webView.setValue(false, forKey: "drawsTransparentBackground")
        // Set wrapper background to white to match web content
        nsView.layer?.backgroundColor = NSColor.white.cgColor
        
        // Update frame
        webView.frame = nsView.bounds
    }
    
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let viewModel: BrowserPaneViewModel
        
        init(viewModel: BrowserPaneViewModel) {
            self.viewModel = viewModel
        }
        
        // MARK: - WKScriptMessageHandler
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "consoleLog" {
                if let body = message.body as? [String: Any],
                   let level = body["level"] as? String,
                   let logMessage = body["message"] as? String {
                    
                    // Parse timestamp if available
                    var timeString = ""
                    if let timestamp = body["timestamp"] as? String {
                        // Format timestamp to be more readable (just time, not full ISO string)
                        if let date = ISO8601DateFormatter().date(from: timestamp) {
                            let formatter = DateFormatter()
                            formatter.dateFormat = "HH:mm:ss.SSS"
                            timeString = formatter.string(from: date)
                        } else {
                            timeString = timestamp
                        }
                    }
                    
                    // Format the log message for Xcode
                    let levelPrefix: String
                    switch level {
                    case "error":
                        levelPrefix = "🔴 [JS ERROR]"
                    case "warn":
                        levelPrefix = "⚠️ [JS WARN]"
                    case "info":
                        levelPrefix = "ℹ️ [JS INFO]"
                    case "debug":
                        levelPrefix = "🐛 [JS DEBUG]"
                    default:
                        levelPrefix = "📝 [JS LOG]"
                    }
                    
                    let fullMessage: String
                    if !timeString.isEmpty {
                        fullMessage = "\(levelPrefix) [\(timeString)] \(logMessage)"
                    } else {
                        fullMessage = "\(levelPrefix) \(logMessage)"
                    }
                    
                    // Log to Xcode console
                    print(fullMessage)
                    
                    // Also log to system console for debugging (only in debug builds)
                    #if DEBUG
                    let logType: OSLogType
                    switch level {
                    case "error":
                        logType = .error
                    case "warn":
                        logType = .default
                    case "info", "debug":
                        logType = .debug
                    default:
                        logType = .default
                    }
                    os_log("%{public}@", log: .default, type: logType, fullMessage)
                    #endif
                } else {
                    // Log raw message if parsing fails
                    print("[JS Console] Failed to parse message: \(message.body)")
                }
            }
        }
        
        // MARK: - WKNavigationDelegate
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.viewModel.isLoading = true
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.viewModel.isLoading = false
                self.viewModel.updateNavigationState()
                // Reapply zoom after navigation to ensure it persists
                self.viewModel.applyZoomSetting()
                // Inject drag and drop enhancement script
                self.injectDragAndDropEnhancement(webView: webView)
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                self.viewModel.isLoading = false
                self.viewModel.updateNavigationState()
            }
        }
        
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.viewModel.updateNavigationState()
                // Reapply zoom when page commits to ensure it persists
                self.viewModel.applyZoomSetting()
            }
        }
        
        // MARK: - Drag and Drop Enhancement
        
        /// Injects JavaScript to enhance HTML5 Drag and Drop API support
        /// This ensures:
        /// 1. Custom dataTransfer.dragData property support
        /// 2. Continuous onDrag event firing during drag operations
        /// 3. Proper clientX/clientY coordinates in drag events
        /// 
        /// Note: The script is already added to the web view configuration as a user script,
        /// but we also evaluate it immediately here to ensure it runs on pages that are already loaded.
        private func injectDragAndDropEnhancement(webView: WKWebView) {
            let script = BrowserPaneViewModel.getDragAndDropEnhancementScript()
            
            // Evaluate immediately in case the page is already loaded
            // The user script will handle injection for future page loads
            webView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    print("Error injecting drag and drop enhancement: \(error.localizedDescription)")
                }
            }
            
            // Also ensure console logging is active
            let consoleScript = BrowserPaneViewModel.getConsoleLoggingScript()
            webView.evaluateJavaScript(consoleScript) { result, error in
                if let error = error {
                    print("Error injecting console logging: \(error.localizedDescription)")
                }
            }
        }
        
        // MARK: - WKUIDelegate
        
        // Handle links that open in new windows/tabs (target="_blank")
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Load the link in the same web view instead of opening a new window
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
        
        // Handle JavaScript alerts, confirms, and prompts if needed
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
            completionHandler()
        }
        
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            completionHandler(response == .alertFirstButtonReturn)
        }
    }
}

