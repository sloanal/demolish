//
//  BrowserPaneView.swift
//  Demolish
//
//  Individual browser pane view with toolbar and web view
//

import SwiftUI
import AppKit
import Combine

struct BrowserPaneView: View {
    @ObservedObject var viewModel: BrowserPaneViewModel
    let onClose: () -> Void
    let onNumberClick: (() -> Void)?
    let totalPanes: Int
    let paneFrame: CGRect
    let isPrimary: Bool
    
    @State private var urlInput: String = ""
    @FocusState private var isURLFieldFocused: Bool
    @State private var isTextFieldFocused: Bool = false
    
    // Reference viewport size for proportional scaling (Full HD)
    // Content will scale proportionally to pane size relative to this reference
    private let referenceViewportSize = CGSize(width: 1920, height: 1080)
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            ZStack(alignment: .trailing) {
                HStack(spacing: 4) {
                    // Close button
                    ToolbarIconButton(
                        systemName: "xmark",
                        action: onClose,
                        helpText: "Close this pane"
                    )
                    .tooltip("⌘⇧W", delay: 0.5, position: .top)
                    .zIndex(1000)
                    .allowsHitTesting(true)
                    
                    // Back button
                    ToolbarIconButton(
                        systemName: "chevron.left",
                        action: { viewModel.goBack() },
                        helpText: "Go back",
                        isDisabled: !viewModel.canGoBack
                    )
                    .zIndex(1000)
                    
                    // Forward button
                    ToolbarIconButton(
                        systemName: "chevron.right",
                        action: { viewModel.goForward() },
                        helpText: "Go forward",
                        isDisabled: !viewModel.canGoForward
                    )
                    .zIndex(1000)
                    
                    // Reload/Stop button
                    ReloadButton(viewModel: viewModel)
                        .zIndex(1000)
                    
                    // URL field — container drawn in SwiftUI so background color applies
                    NoFocusRingTextField(
                        text: $urlInput,
                        placeholder: "Enter URL",
                        onSubmit: {
                            viewModel.loadURL(urlInput)
                            isURLFieldFocused = false
                            isTextFieldFocused = false
                        },
                        isFocused: $isTextFieldFocused
                    )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(minWidth: 120)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(red: 0.19, green: 0.19, blue: 0.19))
                        )
                        .zIndex(0)
                        .onChange(of: isTextFieldFocused) { newValue in
                            // Sync with FocusState
                            isURLFieldFocused = newValue
                        }
                        .onChange(of: isURLFieldFocused) { newValue in
                            // Sync with State
                            isTextFieldFocused = newValue
                        }
                        .onReceive(viewModel.$currentURL.removeDuplicates()) { newURL in
                            // Ensure URL bar always displays the current URL
                            if !newURL.isEmpty && urlInput != newURL {
                                urlInput = newURL
                            }
                        }
                    
                    // Settings icon
                    ToolbarIconButton(
                        systemName: "gearshape.fill",
                        action: {
                            let newValue = !viewModel.isSettingsMenuOpen
                            viewModel.isSettingsMenuOpen = newValue
                            // Notify ContentView to update menu visibility immediately
                            NotificationCenter.default.post(
                                name: NSNotification.Name("PaneSettingsMenuToggled"),
                                object: nil,
                                userInfo: ["paneID": viewModel.id, "isOpen": newValue]
                            )
                        },
                        helpText: "Pane settings"
                    )
                    .zIndex(1000)
                    .padding(.trailing, totalPanes >= 2 && viewModel.displayNumber > 0 ? 16 : 0)
                    
                    // Only add Spacer when pane number is visible
                    if totalPanes >= 2 && viewModel.displayNumber > 0 {
                        Spacer()
                    }
                }
                
                // Pane number indicator (top right)
                if totalPanes >= 2 && viewModel.displayNumber > 0 {
                    PaneNumberIndicator(
                        number: viewModel.displayNumber,
                        showBorder: viewModel.showBorder,
                        borderColor: viewModel.borderColor,
                        onClick: onNumberClick,
                        isPrimary: isPrimary
                    )
                        .padding(.trailing, 4)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .scale(scale: 0.9).combined(with: .opacity)
                        ))
                }
            }
            .padding(8)
            .background(Color(red: 0.30, green: 0.30, blue: 0.30))
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: totalPanes)
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: viewModel.displayNumber)
            
            // Web view
            // Calculate proportional scaling based on pane size
            // Each pane acts like a virtual monitor - content scales with pane size
            GeometryReader { geometry in
                // Calculate content area size (excluding toolbar)
                let contentSize = geometry.size
                
                // Calculate scale factor based on pane size relative to reference viewport
                // Use the smaller of width/height ratios to maintain aspect ratio
                let widthScale = contentSize.width / referenceViewportSize.width
                let heightScale = contentSize.height / referenceViewportSize.height
                let paneScaleFactor = min(widthScale, heightScale)
                
                // Combine pane scale with zoom setting scale
                let zoomScaleFactor = viewModel.zoomSetting.zoomFactor
                let totalScaleFactor = paneScaleFactor * zoomScaleFactor
                
                // Make WebView larger so when scaled down it fills the content area
                WebViewWrapper(viewModel: viewModel, zoomSetting: viewModel.zoomSetting)
                    .frame(
                        width: contentSize.width / totalScaleFactor,
                        height: contentSize.height / totalScaleFactor
                    )
                    .scaleEffect(totalScaleFactor, anchor: .topLeading)
                    .animation(.easeInOut(duration: 0.2), value: viewModel.zoomSetting)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(Color(red: 0.30, green: 0.30, blue: 0.30))
        .onAppear {
            // Sync URL input with view model's current URL
            urlInput = viewModel.currentURL
            // Focus URL field if this is a new pane
            if viewModel.shouldFocusURL {
                // Use a small delay to ensure the view is fully laid out
                DispatchQueue.main.async {
                    isURLFieldFocused = true
                    isTextFieldFocused = true
                    viewModel.shouldFocusURL = false
                }
            }
        }
        .onChange(of: viewModel.shouldFocusURL) { shouldFocus in
            if shouldFocus {
                isURLFieldFocused = true
                isTextFieldFocused = true
                // Reset the flag after focusing
                DispatchQueue.main.async {
                    viewModel.shouldFocusURL = false
                }
            }
        }
    }
}

// Reusable toolbar icon button with standardized hover state
struct ToolbarIconButton: View {
    let systemName: String
    let action: () -> Void
    let helpText: String
    let isDisabled: Bool
    
    @State private var isHovered = false
    
    init(systemName: String, action: @escaping () -> Void, helpText: String = "", isDisabled: Bool = false) {
        self.systemName = systemName
        self.action = action
        self.helpText = helpText
        self.isDisabled = isDisabled
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Hover background - matching pane number selector style
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 20, height: 20)
                    .opacity(isHovered && !isDisabled ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: isHovered)
                
                // Icon
                Image(systemName: systemName)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(helpText)
        .onHover { hovering in
            if !isDisabled {
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                    NSCursor.arrow.set()
                }
            }
        }
    }
}

// Reload/Stop button with dynamic icon and hover state
struct ReloadButton: View {
    @ObservedObject var viewModel: BrowserPaneViewModel
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            if viewModel.isLoading {
                viewModel.stop()
            } else {
                viewModel.reload()
            }
        }) {
            ZStack {
                // Hover background - matching pane number selector style
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 20, height: 20)
                    .opacity(isHovered ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: isHovered)

                // Icon — .id() ensures SwiftUI updates the icon when isLoading changes
                Image(systemName: viewModel.isLoading ? "xmark" : "arrow.clockwise")
                    .foregroundColor(.secondary)
                    .id(viewModel.isLoading)
            }
        }
        .buttonStyle(.plain)
        .help(viewModel.isLoading ? "Stop loading" : "Reload")
        .tooltip("⌘R", delay: 0.5, position: .top)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
                NSCursor.arrow.set()
            }
        }
    }
}

// Pane number indicator - styled similar to settings menu icons but smaller
struct PaneNumberIndicator: View {
    let number: Int
    let showBorder: Bool
    let borderColor: Color
    let onClick: (() -> Void)?
    let isPrimary: Bool
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            onClick?()
        }) {
            ZStack {
                if isPrimary {
                    // Primary pane: current default state (selected state)
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovered ? Color.white.opacity(0.25) : Color.white.opacity(0.15))
                        .frame(width: 20, height: 20)
                        .animation(.easeInOut(duration: 0.2), value: isHovered)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(
                                    showBorder ? borderColor : Color.clear,
                                    lineWidth: showBorder ? 2 : 0
                                )
                                .animation(.easeInOut(duration: 0.2), value: showBorder)
                                .animation(.easeInOut(duration: 0.2), value: borderColor)
                        )
                        .overlay(
                            Text("\(number)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        )
                } else {
                    // Secondary pane: gray number with thin gray outline
                    // Hover state matching toolbar buttons
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 20, height: 20)
                        .opacity(isHovered ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2), value: isHovered)
                    
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary, lineWidth: 1)
                        .frame(width: 20, height: 20)
                        .overlay(
                            Text("\(number)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .tooltip("⌘\(number)", delay: 0.5, position: .top)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
                NSCursor.arrow.set()
            }
        }
        .help("Bring pane to front")
    }
}

// Flyout menu for pane settings
struct PaneSettingsMenu: View {
    @ObservedObject var viewModel: BrowserPaneViewModel
    let onDismiss: () -> Void
    
    @ObservedObject private var loginStore = LoginCredentialStore.shared
    @State private var loginLabelInput: String = ""
    @State private var loginUsernameInput: String = ""
    @State private var loginPasswordInput: String = ""
    @State private var loginStatusMessage: String? = nil
    @State private var loginStatusIsError: Bool = false
    @State private var editingLoginID: UUID? = nil
    @State private var hoveredLoginID: UUID? = nil
    
    // Available border colors (use the same array from view model)
    private var borderColors: [Color] {
        BrowserPaneViewModel.borderColors
    }
    
    private var isLoginSaveDisabled: Bool {
        loginUsernameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || loginPasswordInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func defaultLoginLabel() -> String {
        if let host = URL(string: viewModel.currentURL)?.host, !host.isEmpty {
            return host
        }
        let trimmedUsername = loginUsernameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedUsername.isEmpty ? "Login" : trimmedUsername
    }
    
    private func saveLogin() {
        let labelInput = loginLabelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let usernameInput = loginUsernameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLabel = labelInput.isEmpty ? defaultLoginLabel() : labelInput
        
        if let editingID = editingLoginID {
            loginStore.update(id: editingID, label: resolvedLabel, username: usernameInput, password: loginPasswordInput)
            loginStatusMessage = "Updated login."
        } else {
            loginStore.add(label: resolvedLabel, username: usernameInput, password: loginPasswordInput)
            loginStatusMessage = "Saved login."
        }
        loginStatusIsError = false
        resetLoginForm()
    }
    
    private func resetLoginForm() {
        editingLoginID = nil
        loginLabelInput = ""
        loginUsernameInput = ""
        loginPasswordInput = ""
    }
    
    private func startEditing(_ login: SavedLogin) {
        editingLoginID = login.id
        loginLabelInput = login.label
        loginUsernameInput = login.username
        loginPasswordInput = login.password
        loginStatusMessage = "Editing login."
        loginStatusIsError = false
    }
    
    private func deleteLogin(_ login: SavedLogin) {
        loginStore.remove(id: login.id)
        if editingLoginID == login.id {
            resetLoginForm()
        }
        loginStatusMessage = "Deleted login."
        loginStatusIsError = false
    }
    
    private func attemptAutofill(_ login: SavedLogin) {
        viewModel.autofillLogin(login) { result in
            switch result {
            case .success:
                loginStatusMessage = "Filled login fields."
                loginStatusIsError = false
            case .noLoginFields:
                loginStatusMessage = "No login fields found on this page."
                loginStatusIsError = true
            case .noWebView:
                loginStatusMessage = "Page not ready yet."
                loginStatusIsError = true
            case .scriptError:
                loginStatusMessage = "Couldn't fill login fields."
                loginStatusIsError = true
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Zoom Level option (expandable)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Zoom Level")
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: viewModel.isContentSizeExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.isContentSizeExpanded.toggle()
                    }
                }
                
                if viewModel.isContentSizeExpanded {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(ZoomSetting.allCases, id: \.self) { setting in
                            Button(action: {
                                // Update setting immediately - this will trigger didSet which calls applyZoomSetting()
                                // Force immediate view update by ensuring the change happens synchronously
                                viewModel.objectWillChange.send()
                                viewModel.zoomSetting = setting
                                // Don't close the menu - keep it open
                            }) {
                                HStack {
                                    Text(setting.rawValue)
                                        .foregroundColor(viewModel.zoomSetting == setting ? .blue : .white.opacity(0.8))
                                    Spacer()
                                    if viewModel.zoomSetting == setting {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                            .font(.system(size: 10))
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .padding(.leading, 20)
                                .contentShape(Rectangle()) // Ensure entire area is clickable
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.vertical, 4)
            
            // Border toggle
            HStack {
                Toggle("Colored Border", isOn: $viewModel.showBorder)
                    .toggleStyle(.switch)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            // Border color picker (only shown when border is enabled)
            if viewModel.showBorder {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Border Color")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 11))
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                    
                    HStack(spacing: 8) {
                        ForEach(Array(borderColors.enumerated()), id: \.offset) { index, color in
                            Button(action: {
                                withAnimation {
                                    viewModel.borderColorIndex = index
                                }
                            }) {
                                Circle()
                                    .fill(color)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.3), lineWidth: viewModel.borderColorIndex == index ? 2 : 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.vertical, 4)
            
            // Title field
            VStack(alignment: .leading, spacing: 4) {
                Text("Title")
                    .foregroundColor(.white.opacity(0.8))
                    .font(.system(size: 11))
                    .padding(.horizontal, 12)
                
                TextField("Enter pane title", text: $viewModel.paneTitle)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.vertical, 4)
            
            // Saved logins
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Saved Logins")
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: viewModel.isLoginSectionExpanded ? "chevron.down" : "chevron.right")
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.isLoginSectionExpanded.toggle()
                    }
                }
                
                if viewModel.isLoginSectionExpanded {
                    VStack(alignment: .leading, spacing: 0) {
                        if loginStore.logins.isEmpty {
                            Text("No saved logins")
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        } else {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(loginStore.logins) { login in
                                    HStack(spacing: 6) {
                                            Button(action: {
                                                attemptAutofill(login)
                                            }) {
                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(login.displayName)
                                                        .foregroundColor(.white.opacity(0.9))
                                                        .font(.system(size: 12))
                                                    if !login.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                        Text(login.username)
                                                            .foregroundColor(.white.opacity(0.6))
                                                            .font(.system(size: 10))
                                                    }
                                                }
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            
                                            if hoveredLoginID == login.id {
                                                Button(action: {
                                                    startEditing(login)
                                                }) {
                                                    Image(systemName: "pencil")
                                                        .foregroundColor(.white.opacity(0.7))
                                                        .font(.system(size: 10))
                                                }
                                                .buttonStyle(.plain)
                                                
                                                Button(action: {
                                                    deleteLogin(login)
                                                }) {
                                                    Image(systemName: "trash")
                                                        .foregroundColor(.white.opacity(0.7))
                                                        .font(.system(size: 10))
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 4)
                                                .fill(Color.white.opacity(hoveredLoginID == login.id ? 0.12 : 0))
                                        )
                                        .contentShape(Rectangle())
                                        .onHover { hovering in
                                            hoveredLoginID = hovering ? login.id : nil
                                        }
                                }
                            }
                            .padding(.bottom, 6)
                        }
                        
                        Divider()
                            .background(Color.white.opacity(0.2))
                            .padding(.vertical, 4)
                        
                        Text(editingLoginID == nil ? "Add Login" : "Edit Login")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.system(size: 11))
                            .padding(.horizontal, 12)
                        
                        TextField("Label (optional)", text: $loginLabelInput)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                        
                        TextField("Username", text: $loginUsernameInput)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                        
                        SecureField("Password", text: $loginPasswordInput)
                            .textFieldStyle(.roundedBorder)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)
                        
                        HStack(spacing: 8) {
                            Button("Clear") {
                                resetLoginForm()
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.white.opacity(0.7))
                            
                            Spacer()
                            
                            Button(editingLoginID == nil ? "Save" : "Update") {
                                saveLogin()
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white.opacity(isLoginSaveDisabled ? 0.1 : 0.2))
                            )
                            .opacity(isLoginSaveDisabled ? 0.5 : 1.0)
                            .disabled(isLoginSaveDisabled)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        
                        if let statusMessage = loginStatusMessage {
                            Text(statusMessage)
                                .font(.system(size: 11))
                                .foregroundColor(loginStatusIsError ? .red : .blue)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 8)
                        }
                    }
                    .padding(.bottom, 8)
                } else {
                    Color.clear
                        .frame(height: 6)
                }
            }
        }
        .frame(width: 200, alignment: .top) // Align content to top so it expands downward
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.2, green: 0.2, blue: 0.25))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .allowsHitTesting(true) // Ensure menu can receive clicks
        .fixedSize(horizontal: true, vertical: false) // Let height grow naturally from top
    }
}

// Custom TextField that disables the focus ring
struct NoFocusRingTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void
    @Binding var isFocused: Bool
    
    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = placeholder
        textField.isBordered = false
        textField.isBezeled = false
        textField.focusRingType = .none // Disable the focus ring
        textField.delegate = context.coordinator
        // Transparent so SwiftUI-drawn container shows through
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        textField.textColor = NSColor(white: 1, alpha: 0.8)
        textField.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: NSColor(white: 1, alpha: 0.5)]
        )
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        // Only sync binding → field when the field is not being edited, so we never
        // overwrite the user's selection or in-progress edit (fixes first key/backspace
        // only deselecting instead of replacing text).
        let fieldOrEditorIsFirstResponder = nsView.window?.firstResponder === nsView || nsView.window?.firstResponder === nsView.currentEditor()
        if !fieldOrEditorIsFirstResponder, nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.textBinding = $text
        context.coordinator.onSubmit = onSubmit
        
        // Handle focus state — only call makeFirstResponder when the field (or its editor)
        // doesn't already have focus, to avoid stealing focus from the editor and clearing selection.
        if isFocused && !fieldOrEditorIsFirstResponder {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        } else if !isFocused && fieldOrEditorIsFirstResponder {
            nsView.window?.makeFirstResponder(nil)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused, onSubmit: onSubmit)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var textBinding: Binding<String>
        var isFocusedBinding: Binding<Bool>
        var onSubmit: () -> Void
        
        init(text: Binding<String>, isFocused: Binding<Bool>, onSubmit: @escaping () -> Void) {
            self.textBinding = text
            self.isFocusedBinding = isFocused
            self.onSubmit = onSubmit
        }
        
        func controlTextDidChange(_ notification: Notification) {
            if let textField = notification.object as? NSTextField {
                textBinding.wrappedValue = textField.stringValue
            }
        }
        
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                // Handle Enter key - trigger onSubmit
                onSubmit()
                return true // Consume the event
            }
            return false
        }
        
        func controlTextDidEndEditing(_ notification: Notification) {
            // Update focus state when editing ends
            isFocusedBinding.wrappedValue = false
        }
        
        func controlTextDidBeginEditing(_ notification: Notification) {
            // Update focus state when editing begins
            isFocusedBinding.wrappedValue = true
        }
    }
}

