//
//  SettingsDrawer.swift
//  Demolish
//
//  Settings drawer that slides down from the top
//

import SwiftUI

struct SettingsDrawer: View {
    @ObservedObject var cursorHighlightManager: CursorHighlightManager
    let displayConfiguration: DisplayConfiguration
    let onSelectDisplayConfiguration: (DisplayConfiguration) -> Void
    let panes: [BrowserPaneViewModel]
    let activePaneID: UUID?
    let onSelectPane: (BrowserPaneViewModel) -> Void
    @State private var defaultURL: String = ""
    @State private var hoveredPaneID: UUID? = nil
    @State private var hoveredConfiguration: DisplayConfiguration? = nil
    
    private let defaultURLKey = "defaultURL"
    
    var body: some View {
        HStack(spacing: 24) {
            // Default URL field
            HStack(spacing: 8) {
                Text("Default URL:")
                    .foregroundColor(.white.opacity(0.8))
                TextField("Enter default URL", text: $defaultURL)
                    .textFieldStyle(.roundedBorder)
                    .foregroundColor(.black)
                    .frame(width: 300)
                    .onChange(of: defaultURL) { oldValue, newValue in
                        UserDefaults.standard.set(newValue, forKey: defaultURLKey)
                    }
            }
            
            Divider()
                .frame(height: 20)
                .background(Color.white.opacity(0.3))
            
            // Cursor Highlight section
            HStack(spacing: 12) {
                // Enable toggle
                Toggle("Cursor Highlight", isOn: $cursorHighlightManager.isEnabled)
                    .toggleStyle(.switch)
                    .foregroundColor(.white.opacity(0.8))
                    .tooltip("⌘9", delay: 0.5, position: .bottom)
                
                if cursorHighlightManager.isEnabled {
                    Divider()
                        .frame(height: 20)
                        .background(Color.white.opacity(0.3))
                    
                    // Color picker
                    HStack(spacing: 6) {
                        ForEach(CursorHighlightColor.allCases, id: \.self) { color in
                            Button(action: {
                                cursorHighlightManager.selectedColor = color
                            }) {
                                Circle()
                                    .fill(color.color.opacity(0.7))
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: cursorHighlightManager.selectedColor == color ? 2 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Divider()
                        .frame(height: 20)
                        .background(Color.white.opacity(0.3))
                    
                    // Size slider
                    HStack(spacing: 8) {
                        Text("Size:")
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 35)
                        Slider(value: $cursorHighlightManager.size, in: 20...200, step: 5)
                            .frame(width: 120)
                        Text("\(Int(cursorHighlightManager.size))")
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 35)
                    }
                    
                    Divider()
                        .frame(height: 20)
                        .background(Color.white.opacity(0.3))
                    
                    // Hide cursor toggle
                    Toggle("Hide Cursor", isOn: $cursorHighlightManager.hideCursor)
                        .toggleStyle(.switch)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            
            Spacer()
            
            Divider()
                .frame(height: 20)
                .background(Color.white.opacity(0.3))
            
            if !panes.isEmpty {
                panePicker
                
                Divider()
                    .frame(height: 20)
                    .background(Color.white.opacity(0.3))
            }
            
            // Layout configuration icons
            HStack(spacing: 6) {
                layoutButton(
                    imageName: "TiledLayoutIcon",
                    configuration: .tiled,
                    help: "Tiled layout"
                )
                
                layoutButton(
                    imageName: "LayeredLayoutIcon",
                    configuration: .layered,
                    help: "Layered layout"
                )
                
                layoutButton(
                    imageName: "FocusedLayoutIcon",
                    configuration: .focused,
                    help: "Focused layout"
                )
                
                layoutButton(
                    imageName: "Rotated3DLayoutIcon",
                    configuration: .rotated3D,
                    help: "3D Rotated layout"
                )
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
        .onAppear {
            // Load saved default URL
            defaultURL = UserDefaults.standard.string(forKey: defaultURLKey) ?? ""
        }
    }
    
    private func layoutButton(
        imageName: String,
        configuration: DisplayConfiguration,
        help: String
    ) -> some View {
        // Map configuration to keyboard shortcut
        let shortcutKey: String?
        switch configuration {
        case .tiled:
            shortcutKey = "J"
        case .focused:
            shortcutKey = "L"
        case .rotated3D:
            shortcutKey = ";"
        case .layered:
            shortcutKey = "K"
        case .manual:
            shortcutKey = nil
        }
        
        let tooltipText = shortcutKey != nil ? "⌘\(shortcutKey!)" : nil
        let isSelected = displayConfiguration == configuration
        let isHovered = hoveredConfiguration == configuration
        
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                onSelectDisplayConfiguration(configuration)
            }
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                          ? Color.white.opacity(0.25)
                          : (isHovered
                             ? Color.white.opacity(0.18)
                             : Color.white.opacity(0.12)))
                    .frame(width: 30, height: 30)
                
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .help(help)
        .tooltip(tooltipText ?? "", delay: 0.5, position: .bottom)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredConfiguration = hovering ? configuration : nil
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
                NSCursor.arrow.set()
            }
        }
    }
    
    private var panePicker: some View {
        HStack(spacing: 6) {
            ForEach(panes.filter { $0.displayNumber > 0 }) { pane in
                paneShortcutButton(for: pane, isActive: pane.id == activePaneID)
            }
        }
    }
    
    private func paneShortcutButton(for pane: BrowserPaneViewModel, isActive: Bool) -> some View {
        // Panes use Command + 1, 2, 3, 4
        let shortcutKey = "\(pane.displayNumber)"
        let isHovered = hoveredPaneID == pane.id
        
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                onSelectPane(pane)
            }
        }) {
            Text("\(pane.displayNumber)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive
                              ? Color.white.opacity(0.25)
                              : (isHovered
                                 ? Color.white.opacity(0.18)
                                 : Color.white.opacity(0.12)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            pane.showBorder ? pane.borderColor : Color.clear,
                            lineWidth: pane.showBorder ? 2 : 0
                        )
                        .animation(.easeInOut(duration: 0.2), value: pane.showBorder)
                        .animation(.easeInOut(duration: 0.2), value: pane.borderColorIndex)
                )
        }
        .buttonStyle(.plain)
        .help("Call Pane \(pane.displayNumber)")
        .tooltip("⌘\(shortcutKey)", delay: 0.5, position: .bottom)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredPaneID = hovering ? pane.id : nil
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
                NSCursor.arrow.set()
            }
        }
    }
}

