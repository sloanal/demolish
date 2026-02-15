//
//  SettingsDrawer.swift
//  Demolish
//
//  Settings drawer that slides down from the top
//

import SwiftUI

// Cursor highlight flyout menu — same structure and styles as PaneSettingsMenu so it anchors from top when toggling
struct CursorHighlightMenu: View {
    @ObservedObject var manager: CursorHighlightManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Enable toggle
            HStack {
                Toggle("Cursor Highlight", isOn: $manager.isEnabled)
                    .toggleStyle(.switch)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            // Options (only when enabled) — same conditional pattern as Colored Border in PaneSettingsMenu
            if manager.isEnabled {
                Divider()
                    .background(Color.white.opacity(0.2))
                    .padding(.vertical, 4)
                
                // Color
                VStack(alignment: .leading, spacing: 8) {
                    Text("Color")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 11))
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                    
                    HStack(spacing: 8) {
                        ForEach(CursorHighlightColor.allCases, id: \.self) { color in
                            Button(action: {
                                manager.selectedColor = color
                            }) {
                                Circle()
                                    .fill(color.color.opacity(0.7))
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: manager.selectedColor == color ? 2 : 0)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                
                Divider()
                    .background(Color.white.opacity(0.2))
                    .padding(.vertical, 4)
                
                // Size
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Size")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.system(size: 11))
                        Spacer()
                        Text("\(Int(manager.size))")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    
                    Slider(value: $manager.size, in: 20...200, step: 5)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                
                Divider()
                    .background(Color.white.opacity(0.2))
                    .padding(.vertical, 4)
                
                // Hide cursor toggle
                HStack {
                    Toggle("Hide Cursor", isOn: $manager.hideCursor)
                        .toggleStyle(.switch)
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(width: 200, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.2, green: 0.2, blue: 0.25))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .allowsHitTesting(true)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct SettingsDrawer: View {
    @ObservedObject var cursorHighlightManager: CursorHighlightManager
    let displayConfiguration: DisplayConfiguration
    let onSelectDisplayConfiguration: (DisplayConfiguration) -> Void
    let panes: [BrowserPaneViewModel]
    let activePaneID: UUID?
    let onSelectPane: (BrowserPaneViewModel) -> Void
    @Binding var autoCloseEnabled: Bool
    let onHoverChange: (Bool) -> Void
    let demos: [DemoLayout]
    let onSaveDemo: (String) -> Void
    let onLoadDemo: (DemoLayout) -> Void
    let onDeleteDemo: (DemoLayout) -> Void
    @State private var defaultURL: String = ""
    @State private var hoveredPaneID: UUID? = nil
    @State private var hoveredConfiguration: DisplayConfiguration? = nil
    @State private var showDefaultURLModal: Bool = false
    @State private var tempURLInput: String = ""
    @State private var showCursorSettingsMenu: Bool = false
    @State private var isCursorHighlightButtonHovered: Bool = false
    @State private var urlBarWidth: CGFloat = 300
    @State private var isDefaultURLHovered: Bool = false
    @State private var isDefaultURLSetHovered: Bool = false
    @State private var isHoveringDrawer: Bool = false
    @State private var isHoveringCursorMenu: Bool = false
    @State private var isHoveringURLMenu: Bool = false
    @State private var showSaveDemoModal: Bool = false
    @State private var demoNameInput: String = ""
    @State private var showLoadDemoMenu: Bool = false
    @State private var isSaveDemoButtonHovered: Bool = false
    @State private var isLoadDemoButtonHovered: Bool = false
    @State private var hoveredDemoID: UUID? = nil
    @State private var isHoveringDemoMenu: Bool = false
    @State private var isHoveringDemoModal: Bool = false
    
    private let defaultURLKey = "defaultURL"

    init(
        cursorHighlightManager: CursorHighlightManager,
        displayConfiguration: DisplayConfiguration,
        onSelectDisplayConfiguration: @escaping (DisplayConfiguration) -> Void,
        panes: [BrowserPaneViewModel],
        activePaneID: UUID?,
        onSelectPane: @escaping (BrowserPaneViewModel) -> Void,
        autoCloseEnabled: Binding<Bool>,
        onHoverChange: @escaping (Bool) -> Void,
        demos: [DemoLayout],
        onSaveDemo: @escaping (String) -> Void,
        onLoadDemo: @escaping (DemoLayout) -> Void,
        onDeleteDemo: @escaping (DemoLayout) -> Void
    ) {
        self.cursorHighlightManager = cursorHighlightManager
        self.displayConfiguration = displayConfiguration
        self.onSelectDisplayConfiguration = onSelectDisplayConfiguration
        self.panes = panes
        self.activePaneID = activePaneID
        self.onSelectPane = onSelectPane
        self._autoCloseEnabled = autoCloseEnabled
        self.onHoverChange = onHoverChange
        self.demos = demos
        self.onSaveDemo = onSaveDemo
        self.onLoadDemo = onLoadDemo
        self.onDeleteDemo = onDeleteDemo

        _defaultURL = State(initialValue: UserDefaults.standard.string(forKey: "defaultURL") ?? "")
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            demoControls
            
            // Default URL field - HStack is base so label/button never disappear
            HStack(spacing: 8) {
                Text("Default URL:")
                    .foregroundColor(.white.opacity(0.8))
                    .tooltip("Sets the default URL that new browser panes\nwill load automatically.", delay: 0.5, position: .bottom)
                
                if defaultURL.isEmpty {
                    Button("Set") {
                        tempURLInput = ""
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDefaultURLModal = true
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isDefaultURLSetHovered ? Color.white.opacity(0.18) : Color.white.opacity(0.12))
                    )
                    .tooltip("Sets the default URL that new browser panes\nwill load automatically.", delay: 0.5, position: .bottom)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isDefaultURLSetHovered = hovering
                        }
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                            NSCursor.arrow.set()
                        }
                    }
                } else {
                    Button(action: {
                        tempURLInput = defaultURL
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDefaultURLModal = true
                        }
                    }) {
                        Text(truncateURL(defaultURL, maxLength: 20))
                            .foregroundColor(.white.opacity(0.7))
                            .font(.system(size: 12))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isDefaultURLHovered ? Color.white.opacity(0.18) : Color.white.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isDefaultURLHovered = hovering
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
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: URLBarWidthPreferenceKey.self, value: geometry.size.width)
                }
            )
            .overlay(alignment: .topLeading) {
                if showDefaultURLModal {
                    defaultURLModal
                        .offset(x: 0, y: 39)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                        .allowsHitTesting(true)
                        .onHover { hovering in
                            isHoveringURLMenu = hovering
                            updateHoverState()
                        }
                }
            }
            .onPreferenceChange(URLBarWidthPreferenceKey.self) { width in
                urlBarWidth = width
            }
            
            // Cursor Highlight dropdown menu (same presentation as pane settings cog menu)
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showCursorSettingsMenu.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Text("Cursor Highlight")
                        .foregroundColor(.white.opacity(0.8))
                    
                    Image(systemName: showCursorSettingsMenu ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(showCursorSettingsMenu
                              ? Color.white.opacity(0.25)
                              : (isCursorHighlightButtonHovered
                                 ? Color.white.opacity(0.18)
                                 : Color.white.opacity(0.12)))
                )
            }
            .buttonStyle(.plain)
            .tooltip("⌘9", delay: 0.5, position: .bottom, verticalOffset: -10)
            .zIndex(1001)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isCursorHighlightButtonHovered = hovering
                }
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                    NSCursor.arrow.set()
                }
            }
            .overlay(alignment: .topLeading) {
                if showCursorSettingsMenu {
                    CursorHighlightMenu(manager: cursorHighlightManager)
                        .offset(y: 40)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                        .zIndex(1000)
                        .onHover { hovering in
                            isHoveringCursorMenu = hovering
                            updateHoverState()
                        }
                }
            }
            
            Spacer()
            
            if !panes.isEmpty {
                panePicker
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

            Toggle(isOn: $autoCloseEnabled) {
                Text("Auto-close\nthis menu")
                    .multilineTextAlignment(.center)
                    .lineSpacing(-1)
            }
            .toggleStyle(.switch)
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.8))
            .help("Auto-close settings after 15 seconds")
        }
        .foregroundColor(.white)
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
        .onChange(of: showDefaultURLModal) { isShowing in
            if isShowing {
                tempURLInput = defaultURL
            }
        }
        .onHover { hovering in
            isHoveringDrawer = hovering
            updateHoverState()
        }
        .animation(.easeInOut(duration: 0.2), value: showCursorSettingsMenu)
    }

    private func updateHoverState() {
        onHoverChange(isHoveringDrawer || isHoveringCursorMenu || isHoveringURLMenu || isHoveringDemoMenu || isHoveringDemoModal)
    }
    
    private var defaultURLModal: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Default URL")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            
            Text("Sets the default URL that new browser panes will load automatically")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            
            TextField("Enter default URL", text: $tempURLInput)
                .textFieldStyle(.roundedBorder)
                .foregroundColor(.black)
                .onSubmit {
                    defaultURL = tempURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    UserDefaults.standard.set(defaultURL, forKey: defaultURLKey)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDefaultURLModal = false
                    }
                }
            
            HStack(spacing: 8) {
                Button("Clear") {
                    tempURLInput = ""
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.7))
                
                Spacer()
                
                Button("Cancel") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDefaultURLModal = false
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.7))
                
                Button("Save") {
                    defaultURL = tempURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
                    UserDefaults.standard.set(defaultURL, forKey: defaultURLKey)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDefaultURLModal = false
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.2))
                )
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(width: 200)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.2, green: 0.2, blue: 0.25))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
    
    private func truncateURL(_ url: String, maxLength: Int) -> String {
        if url.count <= maxLength {
            return url
        }
        return String(url.prefix(maxLength)) + "..."
    }

    private var demoControls: some View {
        HStack(spacing: 8) {
            Button("Save Demo") {
                demoNameInput = ""
                closeLoadDemoMenu()
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSaveDemoModal = true
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.white.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSaveDemoButtonHovered ? Color.white.opacity(0.18) : Color.white.opacity(0.12))
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isSaveDemoButtonHovered = hovering
                }
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                    NSCursor.arrow.set()
                }
            }
            .overlay(alignment: .topLeading) {
                if showSaveDemoModal {
                    saveDemoModal
                        .offset(y: 39)
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                        .allowsHitTesting(true)
                        .onHover { hovering in
                            isHoveringDemoModal = hovering
                            updateHoverState()
                        }
                }
            }
            
            if !demos.isEmpty {
                Button(action: {
                    closeSaveDemoModal()
                    if showLoadDemoMenu {
                        closeLoadDemoMenu()
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showLoadDemoMenu = true
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Text("Load Demo")
                            .foregroundColor(.white.opacity(0.8))
                        
                        Image(systemName: showLoadDemoMenu ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(showLoadDemoMenu
                                  ? Color.white.opacity(0.25)
                                  : (isLoadDemoButtonHovered
                                     ? Color.white.opacity(0.18)
                                     : Color.white.opacity(0.12)))
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isLoadDemoButtonHovered = hovering
                    }
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                        NSCursor.arrow.set()
                    }
                }
                .overlay(alignment: .topLeading) {
                    if showLoadDemoMenu {
                        demoMenu
                            .offset(y: 40)
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                            .zIndex(1000)
                            .onHover { hovering in
                                isHoveringDemoMenu = hovering
                                updateHoverState()
                            }
                    }
                }
            }
        }
    }
    
    private var saveDemoModal: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Demo")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
            
            Text("Name this demo layout so you can load it later.")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            
            TextField("Demo name", text: $demoNameInput)
                .textFieldStyle(.roundedBorder)
                .foregroundColor(.black)
                .onSubmit {
                    handleSaveDemo()
                }
            
            HStack(spacing: 8) {
                Spacer()
                
                Button("Cancel") {
                    closeSaveDemoModal()
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.7))
                
                Button("Save") {
                    handleSaveDemo()
                }
                .buttonStyle(.plain)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.2))
                )
                .fixedSize(horizontal: true, vertical: false)
                .disabled(demoNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(demoNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
            }
        }
        .frame(width: 200)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.2, green: 0.2, blue: 0.25))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var demoMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(demos) { demo in
                HStack(spacing: 6) {
                    Button(action: {
                        onLoadDemo(demo)
                        closeLoadDemoMenu()
                    }) {
                        Text(demo.name)
                            .foregroundColor(.white.opacity(0.9))
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    
                    if hoveredDemoID == demo.id {
                        Button(action: {
                            onDeleteDemo(demo)
                            if demos.count == 1 {
                                closeLoadDemoMenu()
                            }
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
                        .fill(Color.white.opacity(hoveredDemoID == demo.id ? 0.12 : 0))
                )
                .contentShape(Rectangle())
                .onHover { hovering in
                    hoveredDemoID = hovering ? demo.id : nil
                }
            }
        }
        .frame(width: 200, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.2, green: 0.2, blue: 0.25))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .allowsHitTesting(true)
        .fixedSize(horizontal: true, vertical: false)
    }
    
    private func handleSaveDemo() {
        let trimmedName = demoNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        onSaveDemo(trimmedName)
        closeSaveDemoModal()
    }
    
    private func closeSaveDemoModal() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showSaveDemoModal = false
        }
        isHoveringDemoModal = false
        updateHoverState()
    }
    
    private func closeLoadDemoMenu() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showLoadDemoMenu = false
        }
        isHoveringDemoMenu = false
        updateHoverState()
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
        .tooltip(tooltipText ?? "", delay: 0.5, position: .bottom, verticalOffset: -10)
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
        .tooltip("⌘\(shortcutKey)", delay: 0.5, position: .bottom, verticalOffset: -10)
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

struct URLBarWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 300
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

