//
//  BrowserPaneViewModel.swift
//  Demolish
//
//  View model for managing an isolated browser pane with its own WKWebsiteDataStore
//

import SwiftUI
import WebKit
import Combine

// Zoom setting enum for content size control
enum ZoomSetting: String, CaseIterable, Codable {
    case outMore = "Out More"
    case out = "Out"
    case none = "None"
    case `in` = "In"
    case inMore = "In More"
    
    // Convert zoom setting to numeric zoom factor
    // Out More = 0.8 (smaller content)
    // Out = 1.0 (default, normal zoom)
    // None = 1.2 (larger content)
    // In = 1.4 (larger content)
    // In More = 1.8 (largest content)
    var zoomFactor: CGFloat {
        switch self {
        case .outMore: return 0.8
        case .out: return 1.0
        case .none: return 1.2
        case .`in`: return 1.4
        case .inMore: return 1.8
        }
    }
}

enum LoginAutofillResult {
    case success
    case noLoginFields
    case noWebView
    case scriptError(String)
}

struct SavedLogin: Identifiable, Codable, Equatable {
    let id: UUID
    var label: String
    var username: String
    var password: String
    var createdAt: Date
    
    var displayName: String {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLabel.isEmpty {
            return trimmedLabel
        }
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedUsername.isEmpty ? "Login" : trimmedUsername
    }
}

final class LoginCredentialStore: ObservableObject {
    static let shared = LoginCredentialStore()
    
    @Published private(set) var logins: [SavedLogin] = []
    
    private let storageKey = "savedLoginCredentials"
    
    private init() {
        load()
    }
    
    func add(label: String, username: String, password: String) {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let passwordCheck = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !passwordCheck.isEmpty else {
            return
        }
        
        let login = SavedLogin(
            id: UUID(),
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            username: trimmedUsername,
            password: password,
            createdAt: Date()
        )
        logins.insert(login, at: 0)
        persist()
    }
    
    func update(id: UUID, label: String, username: String, password: String) {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let passwordCheck = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !passwordCheck.isEmpty else {
            return
        }
        
        guard let index = logins.firstIndex(where: { $0.id == id }) else { return }
        let existing = logins[index]
        logins[index] = SavedLogin(
            id: existing.id,
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            username: trimmedUsername,
            password: password,
            createdAt: existing.createdAt
        )
        persist()
    }
    
    func remove(id: UUID) {
        logins.removeAll { $0.id == id }
        persist()
    }
    
    private func persist() {
        guard let data = try? JSONEncoder().encode(logins) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([SavedLogin].self, from: data) else {
            logins = []
            return
        }
        logins = saved
    }
}

class BrowserPaneViewModel: ObservableObject, Identifiable {
    let objectWillChange = ObservableObjectPublisher()
    
    // Unique identifier for this pane to ensure stable identity in SwiftUI
    let id: UUID
    
    // The isolated data store for this pane - this ensures no shared cookies/cache/storage
    let dataStore: WKWebsiteDataStore
    
    // The web view configuration using the isolated data store
    let webViewConfiguration: WKWebViewConfiguration
    
    // Published properties for UI binding
    @Published var currentURL: String = ""
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    @Published var isLoading: Bool = false
    @Published var shouldFocusURL: Bool = false
    @Published var displayNumber: Int = 0
    @Published var zoomSetting: ZoomSetting = .none {
        didSet {
            // Immediately apply zoom when setting changes
            applyZoomSetting()
        }
    }
    
    // Pane appearance settings
    @Published var showBorder: Bool = false {
        willSet {
            objectWillChange.send()
        }
    }
    @Published var borderColorIndex: Int = 0 {
        willSet {
            objectWillChange.send()
        }
    }  // Index into available colors
    @Published var paneTitle: String = "" {
        willSet {
            objectWillChange.send()
        }
    }
    @Published var showAvatar: Bool = false {
        willSet {
            objectWillChange.send()
        }
    }
    @Published var isSettingsMenuOpen: Bool = false
    @Published var isContentSizeExpanded: Bool = false {
        willSet {
            objectWillChange.send()
        }
    }
    @Published var isLoginSectionExpanded: Bool = false {
        willSet {
            objectWillChange.send()
        }
    }
    
    // Available border colors
    static let borderColors: [Color] = [
        .blue,
        .green,
        .orange,
        .purple
    ]
    
    var borderColor: Color {
        BrowserPaneViewModel.borderColors[borderColorIndex]
    }
    
    // Strong reference to the web view to prevent deallocation when view hierarchy changes
    // This ensures the web view and its content persist across SwiftUI view updates
    var webView: WKWebView?
    
    // Store the last loaded URL to restore if web view is recreated
    private var lastLoadedURL: String?
    
    // KVO observers for web view navigation state
    private var urlObservation: NSKeyValueObservation?
    private var canGoBackObservation: NSKeyValueObservation?
    private var canGoForwardObservation: NSKeyValueObservation?
    
    init() {
        self.id = UUID()
        // Create a non-persistent (ephemeral) data store for this pane
        // This ensures complete isolation: no cookies, localStorage, sessionStorage, or cache
        // is shared with other panes or persisted to disk
        self.dataStore = WKWebsiteDataStore.nonPersistent()
        
        // Configure the web view to use this isolated data store
        self.webViewConfiguration = WKWebViewConfiguration()
        self.webViewConfiguration.websiteDataStore = dataStore
        
        // Enable JavaScript for proper click event handling
        // Note: javaScriptEnabled is deprecated, but we'll keep it for compatibility
        // The default is true, so this line is mainly for clarity
        self.webViewConfiguration.preferences.javaScriptEnabled = true
        
        // Note: processPool is deprecated in macOS 12.0+ as multiple instances no longer have effect
        // We'll remove this for macOS 12.0+ compatibility
        
        // Add drag and drop enhancement script to user content controller
        let dragDropScript = BrowserPaneViewModel.getDragAndDropEnhancementScript()
        let userScript = WKUserScript(source: dragDropScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        self.webViewConfiguration.userContentController.addUserScript(userScript)
        
        // Add console logging script to forward JavaScript console.log to Xcode
        let consoleLogScript = BrowserPaneViewModel.getConsoleLoggingScript()
        let consoleUserScript = WKUserScript(source: consoleLogScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        self.webViewConfiguration.userContentController.addUserScript(consoleUserScript)
        
        // Add URL monitoring script to track SPA and history changes
        let urlMonitoringScript = BrowserPaneViewModel.getURLChangeMonitoringScript()
        let urlUserScript = WKUserScript(source: urlMonitoringScript, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        self.webViewConfiguration.userContentController.addUserScript(urlUserScript)
    }
    
    func setWebView(_ webView: WKWebView) {
        self.webView = webView
        startObservingWebView(webView)
        
        // Apply the current zoom setting to the web view
        applyZoomSetting()
        
        // If we have a stored URL and the web view doesn't have that URL loaded, restore it
        if let urlToRestore = lastLoadedURL {
            let currentURLString = webView.url?.absoluteString ?? ""
            if currentURLString != urlToRestore {
                // Ensure currentURL is set before loading
                if currentURL.isEmpty {
                    currentURL = urlToRestore
                }
                // Restore the URL without updating lastLoadedURL (to avoid recursion)
                if let url = URL(string: urlToRestore) {
                    let request = URLRequest(url: url)
                    webView.load(request)
                }
            }
        }
        
        updateNavigationState()
    }
    
    // Apply the current zoom setting to the web view
    // This ensures zoom persists when the web view is recreated or navigates
    // Note: Browser zoom is always kept at 1.0 (normal rendering) to avoid breakpoint issues.
    // Visual scaling is handled by SwiftUI's scaleEffect in BrowserPaneView.
    func applyZoomSetting() {
        guard let webView = webView else { return }
        
        // Ensure we're on the main thread
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.applyZoomSetting()
            }
            return
        }
        
        // Always keep browser zoom at 1.0 (normal rendering)
        // This ensures HTML renders at its natural size, preventing breakpoint issues
        // Visual scaling will be handled by SwiftUI scaleEffect instead
        if #available(macOS 11.0, *) {
            webView.pageZoom = 1.0
        } else {
            // Fallback to magnification for older macOS versions
            webView.magnification = 1.0
        }
        
        // Force immediate visual and layout updates
        webView.needsLayout = true
        webView.layoutSubtreeIfNeeded()
        
        // Force display update
        webView.needsDisplay = true
        webView.displayIfNeeded()
        
        // Ensure the window's content view also updates
        if let window = webView.window, let contentView = window.contentView {
            contentView.needsLayout = true
            contentView.layoutSubtreeIfNeeded()
            contentView.needsDisplay = true
            contentView.displayIfNeeded()
        }
    }
    
    func loadURL(_ urlString: String) {
        var urlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Add https:// if no scheme is provided
        if !urlString.contains("://") {
            urlString = "https://\(urlString)"
        }
        
        // Store the URL for potential restoration and update the URL bar
        updateCurrentURL(urlString)
        
        guard let webView = webView else { return }
        guard let url = URL(string: urlString) else { return }
        
        let request = URLRequest(url: url)
        webView.load(request)
    }
    
    func goBack() {
        guard let webView = webView else { return }
        if webView.canGoBack {
            webView.goBack()
        } else if let backItem = webView.backForwardList.backItem {
            webView.go(to: backItem)
        }
        refreshBackForwardState()
    }
    
    func goForward() {
        guard let webView = webView else { return }
        if webView.canGoForward {
            webView.goForward()
        } else if let forwardItem = webView.backForwardList.forwardItem {
            webView.go(to: forwardItem)
        }
        refreshBackForwardState()
    }
    
    func reload() {
        webView?.reload()
    }
    
    func stop() {
        webView?.stopLoading()
    }

    /// Clears loading state and notifies observers so the reload button icon updates.
    /// Call from the main queue (e.g. from WKNavigationDelegate).
    func clearLoadingState() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.clearLoadingState() }
            return
        }
        guard isLoading else { return }
        objectWillChange.send()
        isLoading = false
    }
    
    func autofillLogin(_ login: SavedLogin, completion: @escaping (LoginAutofillResult) -> Void) {
        guard let webView = webView else {
            completion(.noWebView)
            return
        }
        
        let script = BrowserPaneViewModel.getLoginAutofillScript(username: login.username, password: login.password)
        webView.evaluateJavaScript(script) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.scriptError(error.localizedDescription))
                    return
                }
                
                if let dict = result as? [String: Any],
                   let success = dict["success"] as? Bool {
                    completion(success ? .success : .noLoginFields)
                    return
                }
                
                if let success = result as? Bool {
                    completion(success ? .success : .noLoginFields)
                    return
                }
                
                completion(.noLoginFields)
            }
        }
    }
    
    func updateNavigationState() {
        guard let webView = webView else { return }
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        // Only update currentURL if web view has a URL, otherwise preserve existing value
        if let webViewURL = webView.url?.absoluteString, !webViewURL.isEmpty {
            updateCurrentURL(webViewURL)
        } else if currentURL.isEmpty, let lastURL = lastLoadedURL {
            // If currentURL is empty but we have a lastLoadedURL, use that
            currentURL = lastURL
        }
    }
    
    private func startObservingWebView(_ webView: WKWebView) {
        urlObservation?.invalidate()
        canGoBackObservation?.invalidate()
        canGoForwardObservation?.invalidate()
        
        urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
            guard let self = self else { return }
            let urlString = webView.url?.absoluteString ?? ""
            guard !urlString.isEmpty else { return }
            if urlString == "about:blank" {
                return
            }
            DispatchQueue.main.async {
                self.updateCurrentURL(urlString)
            }
        }
        
        canGoBackObservation = webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.canGoBack = webView.canGoBack
            }
        }
        
        canGoForwardObservation = webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
            DispatchQueue.main.async {
                self?.canGoForward = webView.canGoForward
            }
        }
    }
    
    func updateCurrentURL(_ urlString: String) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed == "about:blank" {
            return
        }
        if currentURL != trimmed {
            currentURL = trimmed
        }
        lastLoadedURL = trimmed
        refreshBackForwardState()
    }
    
    private func refreshBackForwardState() {
        guard let webView = webView else { return }
        let updateState = {
            self.canGoBack = webView.canGoBack || webView.backForwardList.backItem != nil
            self.canGoForward = webView.canGoForward || webView.backForwardList.forwardItem != nil
        }
        if Thread.isMainThread {
            updateState()
        } else {
            DispatchQueue.main.async {
                updateState()
            }
        }
    }
    
    // MARK: - URL Monitoring
    
    /// Returns JavaScript code that reports URL changes from SPA/history APIs
    static func getURLChangeMonitoringScript() -> String {
        return """
        (function() {
            'use strict';
            
            if (window.__demolishURLMonitor) {
                return;
            }
            window.__demolishURLMonitor = true;
            
            function notify() {
                try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.urlChanged) {
                        window.webkit.messageHandlers.urlChanged.postMessage(window.location.href);
                    }
                } catch (e) {
                    // Ignore reporting errors
                }
            }
            
            const originalPushState = history.pushState;
            history.pushState = function() {
                const result = originalPushState.apply(this, arguments);
                notify();
                return result;
            };
            
            const originalReplaceState = history.replaceState;
            history.replaceState = function() {
                const result = originalReplaceState.apply(this, arguments);
                notify();
                return result;
            };
            
            window.addEventListener('popstate', notify);
            window.addEventListener('hashchange', notify);
            
            notify();
        })();
        """
    }

    // MARK: - Login Autofill
    
    private static func escapeJavaScriptString(_ value: String) -> String {
        var escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "'", with: "\\'")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
        escaped = escaped.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        escaped = escaped.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return escaped
    }
    
    private static func getLoginAutofillScript(username: String, password: String) -> String {
        let safeUsername = escapeJavaScriptString(username)
        let safePassword = escapeJavaScriptString(password)
        
        return """
        (function() {
            'use strict';
            
            function isVisible(el) {
                if (!el) { return false; }
                const rect = el.getBoundingClientRect();
                return !!(rect.width || rect.height || el.getClientRects().length);
            }
            
            function isEditableInput(el) {
                if (!el) { return false; }
                if (el.disabled || el.readOnly) { return false; }
                const type = (el.getAttribute('type') || 'text').toLowerCase();
                if (type === 'hidden') { return false; }
                return isVisible(el);
            }
            
            function tokenMatches(value, tokens) {
                if (!value) { return false; }
                const lower = value.toLowerCase();
                return tokens.some(token => lower.includes(token));
            }
            
            function scoreField(el) {
                let score = 0;
                const type = (el.getAttribute('type') || 'text').toLowerCase();
                const autocomplete = (el.getAttribute('autocomplete') || '').toLowerCase();
                const name = (el.getAttribute('name') || '').toLowerCase();
                const id = (el.getAttribute('id') || '').toLowerCase();
                const placeholder = (el.getAttribute('placeholder') || '').toLowerCase();
                
                if (type === 'email') { score += 6; }
                if (autocomplete.includes('username')) { score += 8; }
                if (autocomplete.includes('email')) { score += 6; }
                if (tokenMatches(name, ['user', 'login', 'email'])) { score += 5; }
                if (tokenMatches(id, ['user', 'login', 'email'])) { score += 4; }
                if (tokenMatches(placeholder, ['user', 'email', 'login'])) { score += 3; }
                
                if (tokenMatches(name, ['search', 'filter', 'query'])) { score -= 6; }
                if (tokenMatches(id, ['search', 'filter', 'query'])) { score -= 6; }
                if (tokenMatches(placeholder, ['search', 'filter', 'query'])) { score -= 6; }
                
                if (type === 'password') { score = -100; }
                return score;
            }
            
            function chooseUsernameField(root, allowFallback) {
                if (!root || !root.querySelectorAll) { return null; }
                const inputs = Array.from(root.querySelectorAll('input'))
                    .filter(isEditableInput)
                    .filter(el => (el.getAttribute('type') || 'text').toLowerCase() !== 'password');
                if (!inputs.length) { return null; }
                let best = null;
                let bestScore = -Infinity;
                inputs.forEach(el => {
                    const score = scoreField(el);
                    if (score > bestScore) {
                        bestScore = score;
                        best = el;
                    }
                });
                if (bestScore < 1) { return allowFallback ? inputs[0] : null; }
                return best;
            }
            
            function setNativeValue(el, value) {
                const valueSetter = Object.getOwnPropertyDescriptor(el.__proto__, 'value')?.set;
                const prototypeSetter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
                if (prototypeSetter && valueSetter !== prototypeSetter) {
                    prototypeSetter.call(el, value);
                } else if (valueSetter) {
                    valueSetter.call(el, value);
                } else {
                    el.value = value;
                }
            }
            
            function setValue(el, value) {
                el.focus();
                setNativeValue(el, value);
                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
                el.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true, key: 'Unidentified' }));
            }
            
            const usernameValue = '\(safeUsername)';
            const passwordValue = '\(safePassword)';
            
            const passwordFields = Array.from(document.querySelectorAll('input[type="password"]'))
                .filter(isEditableInput);
            if (!passwordFields.length) {
                return { success: false, reason: 'password_not_found' };
            }
            
            const passwordField = passwordFields[0];
            const formScope = passwordField.form || passwordField.closest('form') || passwordField.closest('fieldset') || passwordField.closest('div') || document;
            let usernameField = chooseUsernameField(formScope, formScope !== document);
            if (!usernameField && formScope !== document) {
                usernameField = chooseUsernameField(document, false);
            }
            
            if (!usernameField) {
                return { success: false, reason: 'username_not_found' };
            }
            
            setValue(usernameField, usernameValue);
            setValue(passwordField, passwordValue);
            return { success: true };
        })();
        """
    }
    
    // MARK: - Drag and Drop Enhancement
    
    /// Returns the JavaScript code to enhance HTML5 Drag and Drop API support
    /// This ensures:
    /// 1. Custom dataTransfer.dragData property support
    /// 2. Continuous onDrag event firing during drag operations
    /// 3. Proper clientX/clientY coordinates in drag events
    static func getDragAndDropEnhancementScript() -> String {
        return """
        (function() {
            'use strict';
            
            // Only inject once per page
            if (window.__dragDropEnhanced) {
                console.log('[DragDrop] Enhancement already loaded');
                return;
            }
            window.__dragDropEnhanced = true;
            console.log('[DragDrop] Enhancement script loaded');
            
            // Enable debug logging (set to false to disable)
            const DEBUG = true;
            function log(...args) {
                if (DEBUG) {
                    console.log('[DragDrop]', ...args);
                }
            }
            
            // Store custom drag data - use WeakMap to persist across events
            const dragDataStore = new WeakMap();
            const effectAllowedStore = new WeakMap();
            
            // Track active drag operations with full context (moved up so it's available to getter)
            let activeDrags = new WeakMap();
            
            // GLOBAL STORE for current drag data - this persists across different DataTransfer instances
            // Since we can only have one active drag at a time, we use a simple global variable
            let currentDragData = null;
            let currentEffectAllowed = null;
            
            // Enhance DataTransfer prototype to support custom dragData property
            Object.defineProperty(DataTransfer.prototype, 'dragData', {
                get: function() {
                    // FIRST: Check global store (most reliable across different DataTransfer instances)
                    if (currentDragData !== null && currentDragData !== undefined) {
                        // Also store it on this DataTransfer instance for consistency
                        dragDataStore.set(this, currentDragData);
                        log('dragData get: from global store:', currentDragData);
                        return currentDragData;
                    }
                    
                    // Second: check if this DataTransfer has dragData stored directly
                    let data = dragDataStore.get(this);
                    
                    // If found, update global store for consistency
                    if (data !== undefined && data !== null) {
                        currentDragData = data;
                        log('dragData get: from WeakMap:', data);
                        return data;
                    }
                    
                    // Third: try to restore from standard API fallback
                    if (!data) {
                        try {
                            const storedData = this.getData('application/json');
                            if (storedData) {
                                data = JSON.parse(storedData);
                                dragDataStore.set(this, data);
                                currentDragData = data; // Update global store
                                log('dragData get: restored from setData fallback:', data);
                                return data;
                            }
                        } catch (e) {
                            // Ignore parse errors
                        }
                    }
                    
                    // Fourth: check if there's an active drag operation for this DataTransfer
                    // and restore the dragData from the drag context
                    if (!data) {
                        const dragInfo = activeDrags.get(this);
                        if (dragInfo && dragInfo.dragData !== undefined) {
                            // Restore dragData to this DataTransfer instance
                            data = dragInfo.dragData;
                            dragDataStore.set(this, data);
                            currentDragData = data; // Update global store
                            // Also store in standard API for future access
                            try {
                                this.setData('application/json', JSON.stringify(data));
                            } catch (e) {
                                // Ignore errors
                            }
                            log('dragData get: restored from drag context:', data);
                            return data;
                        }
                    }
                    
                    log('dragData get: undefined');
                    return null;
                },
                set: function(value) {
                    log('dragData set:', value);
                    
                    // CRITICAL: Update global store FIRST - this ensures it's available
                    // regardless of which DataTransfer instance is used
                    currentDragData = value;
                    
                    // Also store in WeakMap for this specific DataTransfer instance
                    dragDataStore.set(this, value);
                    
                    // Also update the drag context if there's an active drag
                    const dragInfo = activeDrags.get(this);
                    if (dragInfo) {
                        dragInfo.dragData = value;
                    }
                    
                    // Also store in standard API as fallback
                    if (value && typeof value === 'object') {
                        try {
                            this.setData('application/json', JSON.stringify(value));
                        } catch (e) {
                            log('Error storing dragData in setData:', e);
                        }
                    }
                },
                configurable: true,
                enumerable: true
            });
            
            // Ensure effectAllowed is properly supported and can be set/get
            const originalEffectAllowedDescriptor = Object.getOwnPropertyDescriptor(DataTransfer.prototype, 'effectAllowed');
            if (originalEffectAllowedDescriptor) {
                // Wrap the existing effectAllowed to add logging
                Object.defineProperty(DataTransfer.prototype, 'effectAllowed', {
                    get: function() {
                        const value = effectAllowedStore.get(this) || originalEffectAllowedDescriptor.get?.call(this) || 'uninitialized';
                        log('effectAllowed get:', value);
                        return value;
                    },
                    set: function(value) {
                        log('effectAllowed set:', value);
                        effectAllowedStore.set(this, value);
                        if (originalEffectAllowedDescriptor.set) {
                            originalEffectAllowedDescriptor.set.call(this, value);
                        }
                    },
                    configurable: true,
                    enumerable: true
                });
            }
            
            // dragMouseMoveHandler and dragMouseUpHandler declared here (activeDrags moved up)
            let dragMouseMoveHandler = null;
            let dragMouseUpHandler = null;
            
            // Helper function to create a custom drag event
            function createCustomDragEvent(moveEvent, dataTransfer, eventType) {
                eventType = eventType || 'drag';
                
                // Create a basic event and enhance it with drag event properties
                let event;
                try {
                    event = document.createEvent('Event');
                    event.initEvent(eventType, true, true);
                } catch (e) {
                    // Fallback for older browsers
                    event = document.createEvent('MouseEvent');
                    event.initMouseEvent(eventType, true, true, window, 0,
                        moveEvent.screenX, moveEvent.screenY,
                        moveEvent.clientX, moveEvent.clientY,
                        moveEvent.ctrlKey, moveEvent.shiftKey,
                        moveEvent.altKey, moveEvent.metaKey,
                        moveEvent.button, null);
                }
                
                // Add all the properties we need - ensure they're always available
                Object.defineProperties(event, {
                    clientX: { 
                        value: moveEvent.clientX || 0, 
                        writable: false, 
                        configurable: true 
                    },
                    clientY: { 
                        value: moveEvent.clientY || 0, 
                        writable: false, 
                        configurable: true 
                    },
                    screenX: { 
                        value: moveEvent.screenX || 0, 
                        writable: false, 
                        configurable: true 
                    },
                    screenY: { 
                        value: moveEvent.screenY || 0, 
                        writable: false, 
                        configurable: true 
                    },
                    button: { 
                        value: moveEvent.button || 0, 
                        writable: false, 
                        configurable: true 
                    },
                    buttons: { 
                        value: moveEvent.buttons || 0, 
                        writable: false, 
                        configurable: true 
                    },
                    ctrlKey: { 
                        value: moveEvent.ctrlKey || false, 
                        writable: false, 
                        configurable: true 
                    },
                    shiftKey: { 
                        value: moveEvent.shiftKey || false, 
                        writable: false, 
                        configurable: true 
                    },
                    altKey: { 
                        value: moveEvent.altKey || false, 
                        writable: false, 
                        configurable: true 
                    },
                    metaKey: { 
                        value: moveEvent.metaKey || false, 
                        writable: false, 
                        configurable: true 
                    },
                    dataTransfer: { 
                        value: dataTransfer, 
                        writable: false, 
                        configurable: true 
                    }
                });
                
                return event;
            }
            
            // Intercept and enhance dragstart events
            document.addEventListener('dragstart', function(e) {
                if (!e.dataTransfer) {
                    log('dragstart: no dataTransfer');
                    return;
                }
                
                const target = e.target;
                log('dragstart:', {
                    target: target,
                    tagName: target.tagName,
                    clientX: e.clientX,
                    clientY: e.clientY,
                    dataTransfer: e.dataTransfer,
                    dragData: e.dataTransfer.dragData,
                    effectAllowed: e.dataTransfer.effectAllowed
                });
                
                // Ensure effectAllowed is set if not already set
                if (!e.dataTransfer.effectAllowed || e.dataTransfer.effectAllowed === 'uninitialized') {
                    e.dataTransfer.effectAllowed = 'all';
                    log('dragstart: set effectAllowed to "all"');
                }
                
                // Initialize global store for this drag operation
                currentDragData = e.dataTransfer.dragData || null;
                currentEffectAllowed = e.dataTransfer.effectAllowed || 'all';
                
                // Store drag context - capture initial values
                const dragContext = {
                    target: target,
                    originalTarget: target,
                    startX: e.clientX || 0,
                    startY: e.clientY || 0,
                    lastX: e.clientX || 0,
                    lastY: e.clientY || 0,
                    dataTransfer: e.dataTransfer,
                    dragData: currentDragData, // Use global store value
                    effectAllowed: currentEffectAllowed
                };
                
                activeDrags.set(e.dataTransfer, dragContext);
                
                // Set up a watcher to capture dragData when it's set by the website code
                // Use a MutationObserver-like approach or intercept the setter
                // Actually, we already intercept the setter, so we update dragContext there
                // But let's also poll for it after a short delay to catch it if set asynchronously
                setTimeout(function() {
                    const updatedDragData = e.dataTransfer.dragData;
                    if (updatedDragData !== undefined && updatedDragData !== null) {
                        // Update global store
                        currentDragData = updatedDragData;
                        const currentDragInfo = activeDrags.get(e.dataTransfer);
                        if (currentDragInfo) {
                            currentDragInfo.dragData = updatedDragData;
                            log('dragstart: captured dragData after delay:', updatedDragData);
                        }
                    }
                }, 10);
                
                // Set up continuous drag event firing using mousemove
                dragMouseMoveHandler = function(moveEvent) {
                    if (!activeDrags.has(e.dataTransfer)) {
                        log('mousemove: drag no longer active, cleaning up');
                        document.removeEventListener('mousemove', dragMouseMoveHandler);
                        document.removeEventListener('mouseup', dragMouseUpHandler);
                        dragMouseMoveHandler = null;
                        dragMouseUpHandler = null;
                        return;
                    }
                    
                    const dragInfo = activeDrags.get(e.dataTransfer);
                    if (!dragInfo) {
                        log('mousemove: no drag info');
                        return;
                    }
                    
                    // CRITICAL: Restore dragData to the DataTransfer BEFORE creating the drag event
                    // Use global store first, then fall back to dragInfo
                    const dragDataToUse = currentDragData !== null ? currentDragData : (dragInfo.dragData !== undefined ? dragInfo.dragData : null);
                    
                    if (dragDataToUse !== null && dragDataToUse !== undefined) {
                        // Update global store if needed
                        if (currentDragData !== dragDataToUse) {
                            currentDragData = dragDataToUse;
                        }
                        
                        // Force set dragData on the DataTransfer instance
                        dragDataStore.set(e.dataTransfer, dragDataToUse);
                        // Also update the property directly
                        try {
                            Object.defineProperty(e.dataTransfer, 'dragData', {
                                value: dragDataToUse,
                                writable: true,
                                configurable: true,
                                enumerable: true
                            });
                        } catch (err) {
                            // If that fails, just use the setter
                            e.dataTransfer.dragData = dragDataToUse;
                        }
                        log('mousemove: restored dragData to DataTransfer:', dragDataToUse);
                    }
                    
                    const effectAllowedToUse = currentEffectAllowed || dragInfo.effectAllowed || 'all';
                    if (effectAllowedToUse) {
                        e.dataTransfer.effectAllowed = effectAllowedToUse;
                        currentEffectAllowed = effectAllowedToUse;
                    }
                    
                    // Create a synthetic drag event with all necessary properties
                    let dragEvent;
                    
                    // Try to create a DragEvent (modern browsers support this)
                    if (typeof DragEvent !== 'undefined') {
                        try {
                            dragEvent = new DragEvent('drag', {
                                bubbles: true,
                                cancelable: true,
                                clientX: moveEvent.clientX,
                                clientY: moveEvent.clientY,
                                screenX: moveEvent.screenX,
                                screenY: moveEvent.screenY,
                                dataTransfer: e.dataTransfer, // Use the same DataTransfer instance with restored dragData
                                button: moveEvent.button,
                                buttons: moveEvent.buttons,
                                ctrlKey: moveEvent.ctrlKey,
                                shiftKey: moveEvent.shiftKey,
                                altKey: moveEvent.altKey,
                                metaKey: moveEvent.metaKey
                            });
                            
                            // Ensure dragData is also on the new event's dataTransfer
                            const dragDataForEvent = currentDragData !== null ? currentDragData : (dragInfo.dragData !== undefined ? dragInfo.dragData : null);
                            if (dragDataForEvent !== null && dragDataForEvent !== undefined && dragEvent.dataTransfer) {
                                dragDataStore.set(dragEvent.dataTransfer, dragDataForEvent);
                                // Also set it directly
                                try {
                                    dragEvent.dataTransfer.dragData = dragDataForEvent;
                                } catch (err) {
                                    // Ignore errors
                                }
                            }
                        } catch (err) {
                            log('DragEvent constructor failed, using custom event:', err);
                            dragEvent = createCustomDragEvent(moveEvent, e.dataTransfer, 'drag');
                        }
                    } else {
                        dragEvent = createCustomDragEvent(moveEvent, e.dataTransfer, 'drag');
                    }
                    
                    // Force update clientX/clientY to ensure they're always available
                    Object.defineProperty(dragEvent, 'clientX', {
                        value: moveEvent.clientX || 0,
                        writable: false,
                        configurable: true
                    });
                    Object.defineProperty(dragEvent, 'clientY', {
                        value: moveEvent.clientY || 0,
                        writable: false,
                        configurable: true
                    });
                    
                    // Ensure dataTransfer is the same instance with all properties
                    Object.defineProperty(dragEvent, 'dataTransfer', {
                        value: e.dataTransfer,
                        writable: false,
                        configurable: true
                    });
                    
                    // Update drag info
                    dragInfo.lastX = moveEvent.clientX || 0;
                    dragInfo.lastY = moveEvent.clientY || 0;
                    
                    log('drag (synthetic):', {
                        clientX: dragEvent.clientX,
                        clientY: dragEvent.clientY,
                        dragData: dragEvent.dataTransfer?.dragData,
                        effectAllowed: dragEvent.dataTransfer?.effectAllowed
                    });
                    
                    // Dispatch the drag event on the original target and bubble up
                    if (dragInfo.target && dragInfo.target.dispatchEvent) {
                        try {
                            dragInfo.target.dispatchEvent(dragEvent);
                        } catch (err) {
                            log('Error dispatching drag event:', err);
                        }
                    }
                    
                    // Also try calling onDrag directly if it exists (for inline handlers like onDrag={...})
                    if (dragInfo.target && typeof dragInfo.target.onDrag === 'function') {
                        try {
                            dragInfo.target.onDrag(dragEvent);
                        } catch (err) {
                            log('Error in onDrag handler:', err);
                        }
                    }
                    
                    // Also dispatch on parent elements to ensure event propagation works
                    let currentElement = dragInfo.target.parentElement;
                    let depth = 0;
                    while (currentElement && depth < 10) {
                        if (currentElement.dispatchEvent) {
                            try {
                                currentElement.dispatchEvent(dragEvent);
                            } catch (err) {
                                log('Error dispatching drag event on parent:', err);
                            }
                        }
                        currentElement = currentElement.parentElement;
                        depth++;
                    }
                };
                
                // Handle mouseup to clean up if dragend doesn't fire
                dragMouseUpHandler = function(upEvent) {
                    log('mouseup during drag, cleaning up');
                    if (dragMouseMoveHandler) {
                        document.removeEventListener('mousemove', dragMouseMoveHandler);
                        dragMouseMoveHandler = null;
                    }
                    document.removeEventListener('mouseup', dragMouseUpHandler);
                    dragMouseUpHandler = null;
                    if (e.dataTransfer) {
                        activeDrags.delete(e.dataTransfer);
                    }
                    
                    // Clear global store
                    currentDragData = null;
                    currentEffectAllowed = null;
                };
                
                document.addEventListener('mousemove', dragMouseMoveHandler, { passive: true, capture: true });
                document.addEventListener('mouseup', dragMouseUpHandler, { passive: true, capture: true });
                
                log('dragstart: handlers attached');
            }, true);
            
            // Enhance native drag events to ensure clientX/clientY are available and dragData persists
            document.addEventListener('drag', function(e) {
                if (!e.dataTransfer) return;
                
                const dragInfo = activeDrags.get(e.dataTransfer);
                
                // CRITICAL: Use global store first - this works even if DataTransfer instance is different
                const dragDataToUse = currentDragData !== null ? currentDragData : (dragInfo && dragInfo.dragData !== undefined ? dragInfo.dragData : null);
                
                if (dragInfo) {
                    // Ensure clientX/clientY are set if missing
                    if (typeof e.clientX === 'undefined' || e.clientX === null || e.clientX === 0) {
                        Object.defineProperty(e, 'clientX', {
                            value: dragInfo.lastX || 0,
                            writable: false,
                            configurable: true
                        });
                    }
                    if (typeof e.clientY === 'undefined' || e.clientY === null || e.clientY === 0) {
                        Object.defineProperty(e, 'clientY', {
                            value: dragInfo.lastY || 0,
                            writable: false,
                            configurable: true
                        });
                    }
                    
                    // CRITICAL: Restore dragData to this DataTransfer instance
                    // Native drag events might use a different DataTransfer instance
                    if (dragDataToUse !== null && dragDataToUse !== undefined) {
                        // Force restore dragData
                        dragDataStore.set(e.dataTransfer, dragDataToUse);
                        // Also try to set it as a property
                        try {
                            Object.defineProperty(e.dataTransfer, 'dragData', {
                                value: dragDataToUse,
                                writable: true,
                                configurable: true,
                                enumerable: true
                            });
                        } catch (err) {
                            // Fallback to setter
                            e.dataTransfer.dragData = dragDataToUse;
                        }
                        log('drag (native): restored dragData from global store:', dragDataToUse);
                    }
                    
                    // Also restore effectAllowed
                    const effectAllowedToUse = currentEffectAllowed || dragInfo.effectAllowed || 'all';
                    if (effectAllowedToUse) {
                        e.dataTransfer.effectAllowed = effectAllowedToUse;
                    }
                    
                    log('drag (native):', {
                        clientX: e.clientX,
                        clientY: e.clientY,
                        dragData: e.dataTransfer.dragData,
                        effectAllowed: e.dataTransfer.effectAllowed
                    });
                } else {
                    // If no dragInfo found for this DataTransfer, the browser might be using
                    // a different DataTransfer instance. Use global store or try standard API fallback
                    if (dragDataToUse !== null && dragDataToUse !== undefined) {
                        dragDataStore.set(e.dataTransfer, dragDataToUse);
                        e.dataTransfer.dragData = dragDataToUse;
                        log('drag (native): restored dragData from global store (no dragInfo):', dragDataToUse);
                    } else {
                        try {
                            const storedData = e.dataTransfer.getData('application/json');
                            if (storedData) {
                                const parsed = JSON.parse(storedData);
                                dragDataStore.set(e.dataTransfer, parsed);
                                currentDragData = parsed; // Update global store
                                e.dataTransfer.dragData = parsed;
                                log('drag (native): restored dragData from setData fallback:', parsed);
                            }
                        } catch (err) {
                            // Ignore errors
                        }
                    }
                }
            }, true);
            
            // Clean up on dragend
            document.addEventListener('dragend', function(e) {
                log('dragend:', {
                    clientX: e.clientX,
                    clientY: e.clientY,
                    dragData: e.dataTransfer?.dragData
                });
                
                if (dragMouseMoveHandler) {
                    document.removeEventListener('mousemove', dragMouseMoveHandler);
                    dragMouseMoveHandler = null;
                }
                if (dragMouseUpHandler) {
                    document.removeEventListener('mouseup', dragMouseUpHandler);
                    dragMouseUpHandler = null;
                }
                if (e.dataTransfer) {
                    activeDrags.delete(e.dataTransfer);
                }
                
                // Clear global store
                currentDragData = null;
                currentEffectAllowed = null;
            }, true);
            
            // Also clean up on drop
            document.addEventListener('drop', function(e) {
                log('drop:', {
                    clientX: e.clientX,
                    clientY: e.clientY,
                    dragData: e.dataTransfer?.dragData
                });
                
                if (dragMouseMoveHandler) {
                    document.removeEventListener('mousemove', dragMouseMoveHandler);
                    dragMouseMoveHandler = null;
                }
                if (dragMouseUpHandler) {
                    document.removeEventListener('mouseup', dragMouseUpHandler);
                    dragMouseUpHandler = null;
                }
                if (e.dataTransfer) {
                    activeDrags.delete(e.dataTransfer);
                }
                
                // Clear global store
                currentDragData = null;
                currentEffectAllowed = null;
            }, true);
            
            // Ensure draggable attribute is properly supported
            // Enhance elements with draggable attribute
            const observer = new MutationObserver(function(mutations) {
                mutations.forEach(function(mutation) {
                    mutation.addedNodes.forEach(function(node) {
                        if (node.nodeType === 1) { // Element node
                            enhanceDraggableElement(node);
                        }
                    });
                });
            });
            
            function enhanceDraggableElement(element) {
                if (element.hasAttribute && element.hasAttribute('draggable')) {
                    // Ensure draggable is properly set
                    if (element.draggable !== true) {
                        element.draggable = true;
                    }
                }
                
                // Recursively enhance child elements
                if (element.querySelectorAll) {
                    const draggableChildren = element.querySelectorAll('[draggable]');
                    draggableChildren.forEach(function(child) {
                        if (child.draggable !== true) {
                            child.draggable = true;
                        }
                    });
                }
            }
            
            // Enhance existing draggable elements
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', function() {
                    enhanceDraggableElement(document.body);
                });
            } else {
                enhanceDraggableElement(document.body);
            }
            
            // Watch for new elements
            observer.observe(document.body, {
                childList: true,
                subtree: true
            });
            
            // Ensure clientX/clientY are always available in drag events
            const originalDispatchEvent = EventTarget.prototype.dispatchEvent;
            EventTarget.prototype.dispatchEvent = function(event) {
                if (event instanceof DragEvent && event.type === 'drag') {
                    // Ensure clientX/clientY are set if missing
                    if (typeof event.clientX === 'undefined' || event.clientX === null) {
                        Object.defineProperty(event, 'clientX', {
                            value: event.clientX || 0,
                            writable: false,
                            configurable: true
                        });
                    }
                    if (typeof event.clientY === 'undefined' || event.clientY === null) {
                        Object.defineProperty(event, 'clientY', {
                            value: event.clientY || 0,
                            writable: false,
                            configurable: true
                        });
                    }
                }
                return originalDispatchEvent.call(this, event);
            };
        })();
        """
    }
    
    /// Returns JavaScript code that overrides console.log to send messages to Swift/Xcode
    static func getConsoleLoggingScript() -> String {
        return """
        (function() {
            'use strict';
            
            // Store original console methods
            const originalLog = console.log;
            const originalError = console.error;
            const originalWarn = console.warn;
            const originalInfo = console.info;
            const originalDebug = console.debug;
            
            // Function to send log message to Swift
            function sendToSwift(level, args) {
                try {
                    // Convert arguments to string
                    const message = Array.from(args).map(arg => {
                        if (typeof arg === 'object') {
                            try {
                                return JSON.stringify(arg, null, 2);
                            } catch (e) {
                                return String(arg);
                            }
                        }
                        return String(arg);
                    }).join(' ');
                    
                    // Send to Swift via message handler
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.consoleLog) {
                        window.webkit.messageHandlers.consoleLog.postMessage({
                            level: level,
                            message: message,
                            timestamp: new Date().toISOString()
                        });
                    }
                } catch (e) {
                    // Fallback to original if message handler fails
                    originalError('Error sending log to Swift:', e);
                }
            }
            
            // Override console methods
            console.log = function(...args) {
                originalLog.apply(console, args);
                sendToSwift('log', args);
            };
            
            console.error = function(...args) {
                originalError.apply(console, args);
                sendToSwift('error', args);
            };
            
            console.warn = function(...args) {
                originalWarn.apply(console, args);
                sendToSwift('warn', args);
            };
            
            console.info = function(...args) {
                originalInfo.apply(console, args);
                sendToSwift('info', args);
            };
            
            console.debug = function(...args) {
                originalDebug.apply(console, args);
                sendToSwift('debug', args);
            };
        })();
        """
    }
}

