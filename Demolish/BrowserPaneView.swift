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
                    
                    // URL field
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
                        .textFieldStyle(.roundedBorder)
                        .zIndex(0)
                        .onChange(of: isTextFieldFocused) { oldValue, newValue in
                            // Sync with FocusState
                            isURLFieldFocused = newValue
                        }
                        .onChange(of: isURLFieldFocused) { oldValue, newValue in
                            // Sync with State
                            isTextFieldFocused = newValue
                        }
                        .onChange(of: viewModel.currentURL) { oldURL, newURL in
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
            .background(Color(red: 0.35, green: 0.40, blue: 0.45))
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
        .background(Color(red: 0.35, green: 0.40, blue: 0.45))
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
        .onChange(of: viewModel.shouldFocusURL) { oldValue, shouldFocus in
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
                
                // Icon
                Image(systemName: viewModel.isLoading ? "xmark" : "arrow.clockwise")
                    .foregroundColor(.secondary)
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
    
    // Available border colors (use the same array from view model)
    private var borderColors: [Color] {
        BrowserPaneViewModel.borderColors
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
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.focusRingType = .none // Disable the focus ring
        textField.delegate = context.coordinator
        return textField
    }
    
    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        context.coordinator.textBinding = $text
        context.coordinator.onSubmit = onSubmit
        
        // Handle focus state
        let isCurrentlyFirstResponder = nsView.window?.firstResponder === nsView.currentEditor()
        if isFocused && !isCurrentlyFirstResponder {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        } else if !isFocused && isCurrentlyFirstResponder {
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

