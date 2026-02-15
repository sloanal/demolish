//
//  ContentView.swift
//  Demolish
//
//  Main content view that manages multiple browser panes with resizable layout
//

import SwiftUI
import AppKit
import WebKit

enum DisplayConfiguration: String, Codable, Equatable {
    case manual
    case tiled
    case focused
    case rotated3D
    case layered
}

struct ContentView: View {
    @State private var panes: [BrowserPaneViewModel] = []
    @StateObject private var frameManager = PaneFrameManager()
    @StateObject private var cursorHighlightManager = CursorHighlightManager()
    @StateObject private var demoStore = DemoStore()
    @State private var containerSize: CGSize = .zero
    @State private var isSettingsDrawerOpen = false
    @State private var isAddButtonHovered = false
    @State private var isSettingsButtonHovered = false
    @State private var displayConfiguration: DisplayConfiguration = .manual
    @State private var paneOrder: [UUID] = []
    @State private var openSettingsMenuPaneID: UUID? = nil // Track which pane has menu open
    @State private var draggingPaneID: UUID? = nil // Track which pane is being dragged
    @State private var dragOffset: CGSize = .zero // Local drag offset for immediate feedback
    @State private var dragStartFrame: CGRect? = nil // Store frame at drag start
    @State private var autoCloseSettingsMenu: Bool = true
    @State private var settingsAutoCloseWorkItem: DispatchWorkItem? = nil
    @State private var isMouseInSettingsDrawer: Bool = false
    @State private var isApplyingDemo: Bool = false
    @Namespace private var paneNamespace
    private let maxPanes = 4
    private let panePadding: CGFloat = 16
    private let settingsDrawerHeight: CGFloat = 40
    private let settingsAutoCloseDelay: TimeInterval = 15
    
    var body: some View {
        ZStack(alignment: .top) {
            // Main content area - extends all the way to the top
            // The custom top bar overlay sits on top of this
            GeometryReader { geometry in
                ZStack {
                    // Darker background
                    Color(red: 0.15, green: 0.15, blue: 0.15)
                        .ignoresSafeArea()
                    
                    // Panes with explicit translate and scale animations
                    // Using explicit offset/scale + GeometryEffect ensures all panes have visible motion
                    let orderedPaneList = orderedPanes
                    
                    ForEach(Array(orderedPaneList.enumerated()), id: \.element.id) { index, pane in
                        if let paneFrame = frameManager.frames[pane.id] {
                            paneLayer(index: index, pane: pane, geometry: geometry)
                        }
                    }
                }
                .onAppear {
                    containerSize = geometry.size
                    if displayConfiguration == .manual {
                        initializePaneFrames(in: geometry.size)
                    } else {
                        applyCurrentDisplayConfiguration(in: geometry.size)
                    }
                }
                .onChange(of: geometry.size) { newSize in
                    containerSize = newSize
                    if displayConfiguration == .manual {
                        // For a single pane, always arrange it to fill the space
                        // Otherwise, adjust existing frames proportionally
                        if panes.count == 1 {
                            arrangePanesTiled(in: newSize)
                        } else {
                            adjustPaneFrames(to: newSize)
                        }
                    } else {
                        applyCurrentDisplayConfiguration(in: newSize)
                    }
                }
                .onChange(of: panes.count) { newCount in
                    if isApplyingDemo {
                        return
                    }
                    syncPaneOrderWithPanes()
                    // Only initialize frames if we have a valid geometry size
                    guard geometry.size.width > 0, geometry.size.height > 0 else { return }
                    if displayConfiguration == .manual {
                        initializePaneFrames(in: geometry.size)
                    } else {
                        applyCurrentDisplayConfiguration(in: geometry.size)
                    }
                }
            }
            .ignoresSafeArea(edges: .top)
            
            // Custom top bar in title bar area - rendered as overlay to ensure it's above system UI
            // This replaces the default gray macOS title bar and must be on top for interaction
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // Left padding to account for traffic light buttons (~80-90 points)
                    // This ensures our toolbar buttons don't overlap with the window controls
                    Spacer()
                        .frame(width: 80)
                    
                    // Settings drawer content area (when open, slides down from here)
                    // When closed, this space is empty
                    if isSettingsDrawerOpen {
                        SettingsDrawer(
                            cursorHighlightManager: cursorHighlightManager,
                            displayConfiguration: displayConfiguration,
                            onSelectDisplayConfiguration: setDisplayConfiguration,
                            panes: orderedPanes,
                            activePaneID: orderedPanes.first?.id,
                            onSelectPane: { pane in bringPaneToFront(pane) },
                            autoCloseEnabled: $autoCloseSettingsMenu,
                            onHoverChange: handleSettingsDrawerHover,
                            demos: demoStore.demos,
                            onSaveDemo: saveDemo,
                            onLoadDemo: applyDemo,
                            onDeleteDemo: deleteDemo
                        )
                            .frame(height: settingsDrawerHeight)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    } else {
                        Spacer()
                    }
                    
                    // Toolbar buttons (settings gear + new pane button) on the right
                    HStack(spacing: 12) {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSettingsDrawerOpen.toggle()
                            }
                        }) {
                            Image(systemName: "gearshape.fill")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .help("Settings")
                        .tooltip("⌘0", delay: 0.5, position: .bottom)
                        .foregroundColor(isSettingsDrawerOpen 
                                          ? .blue.opacity(isSettingsButtonHovered ? 0.6 : 0.8) 
                                          : .white.opacity(isSettingsButtonHovered ? 0.5 : 0.8))
                        .onHover { hovering in
                            isSettingsButtonHovered = hovering
                            if hovering {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                                NSCursor.arrow.set()
                            }
                        }
                        
                        Button(action: addPane) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .semibold))
                                Image("BrowserIcon")
                                    .resizable()
                                    .renderingMode(.template)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 18, height: 18)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                // Rectangle with rounded corners matching window corner radius (10 points)
                                // All corners rounded to match the window's corner radius
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(panes.count >= maxPanes 
                                          ? Color.white.opacity(0.1) 
                                          : (isAddButtonHovered ? Color.white.opacity(0.25) : Color.white.opacity(0.15)))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(panes.count >= maxPanes)
                        .help("Add a new browser pane (max \(maxPanes))")
                        .tooltip(panes.count >= maxPanes ? "\(maxPanes) max" : "⌘N", delay: 0.5, position: .bottom)
                        .foregroundColor(panes.count >= maxPanes ? .white.opacity(0.3) : .white.opacity(0.9))
                        .onHover { hovering in
                            isAddButtonHovered = hovering && panes.count < maxPanes
                            if hovering && panes.count < maxPanes {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                                NSCursor.arrow.set()
                            }
                        }
                    }
                    .padding(.trailing, 4)
                    .padding(.vertical, 4)
                }
                .frame(height: settingsDrawerHeight)
                .background(Color(red: 0.15, green: 0.15, blue: 0.15))
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Ignore safe area at top to extend into title bar space
            // This ensures the bar is flush with the top edge and traffic lights
            .ignoresSafeArea(edges: .top)
            // High z-index to ensure it's above any system UI layers
            .zIndex(10000)
            
            // Cursor highlight overlay - must stay above all menus/modals
            CursorHighlightOverlay(manager: cursorHighlightManager)
                .allowsHitTesting(false)
                .zIndex(20002)
            
            // Pane settings menus - rendered at top level for immediate updates
            if let openPaneID = openSettingsMenuPaneID,
               let pane = panes.first(where: { $0.id == openPaneID }),
               let paneFrame = frameManager.frames[pane.id] {
                PaneSettingsMenu(
                    viewModel: pane,
                    onDismiss: {
                        // Close menu without animation to avoid flicker
                        openSettingsMenuPaneID = nil
                        pane.isSettingsMenuOpen = false
                    }
                )
                .frame(width: 200, alignment: .top) // Top-aligned so it expands downward
                .offset(
                    x: paneFrame.frame.maxX - 757 - 200, // Position right edge (82px + 675px left shift)
                    y: paneFrame.frame.minY + 4  // Top edge position (10px down from -6)
                )
                .transition(.asymmetric(
                    insertion: .offset(y: 10).combined(with: .opacity).animation(.easeInOut(duration: 0.2)),
                    removal: .offset(y: -10).combined(with: .opacity).animation(.easeInOut(duration: 0.2))
                ))
                .zIndex(10001) // Above everything else
            }
            
            // Background overlay to dismiss settings menus when clicking outside
            // Must be after menu in ZStack order, but lower z-index so menu receives clicks first
            if openSettingsMenuPaneID != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // Close all open settings menus
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if let paneID = openSettingsMenuPaneID,
                               let pane = panes.first(where: { $0.id == paneID }) {
                                pane.isSettingsMenuOpen = false
                            }
                            openSettingsMenuPaneID = nil
                        }
                    }
                    .zIndex(9999) // Below menu (10001) so menu receives clicks first
                    .allowsHitTesting(true)
            }
        }
        .background(Color(red: 0.15, green: 0.15, blue: 0.15))
        .overlay(alignment: .topLeading) {
            paneKeyboardShortcutOverlay
        }
        // Explicit animation triggers for smooth transitions
        .animation(.spring(response: 0.7, dampingFraction: 0.8, blendDuration: 0.3), value: paneOrder)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PaneSettingsMenuToggled"))) { notification in
            // Update openSettingsMenuPaneID when menu is toggled
            if let paneID = notification.userInfo?["paneID"] as? UUID,
               let isOpen = notification.userInfo?["isOpen"] as? Bool {
                if isOpen {
                    openSettingsMenuPaneID = paneID
                } else if openSettingsMenuPaneID == paneID {
                    openSettingsMenuPaneID = nil
                }
            }
        }
        .onAppear {
            // Start with one pane by default
            if panes.isEmpty {
                addPane()
            } else {
                syncPaneOrderWithPanes()
            }
            
            // Backup: Ensure window configuration is applied when view appears
            // This helps catch cases where the window configuration helper might miss the window
            DispatchQueue.main.async {
                if let window = NSApplication.shared.windows.first {
                    window.titleVisibility = .hidden
                    window.titlebarAppearsTransparent = true
                    window.styleMask.insert(.fullSizeContentView)
                    window.toolbar = nil
                }
            }
        }
        .onChange(of: isSettingsDrawerOpen) { isOpen in
            if isOpen {
                scheduleSettingsAutoClose()
            } else {
                isMouseInSettingsDrawer = false
                cancelSettingsAutoClose()
            }
        }
        .onChange(of: autoCloseSettingsMenu) { isEnabled in
            if !isEnabled {
                cancelSettingsAutoClose()
                return
            }
            scheduleSettingsAutoClose()
        }
    }
    
    private var orderedPanes: [BrowserPaneViewModel] {
        var ordered: [BrowserPaneViewModel] = paneOrder.compactMap { id in
            panes.first(where: { $0.id == id })
        }
        
        let remaining = panes.filter { pane in
            !paneOrder.contains(pane.id)
        }
        ordered.append(contentsOf: remaining)
        return ordered
    }
    
    @ViewBuilder
    private func paneView(for pane: BrowserPaneViewModel, frame: CGRect, zIndex: Int, totalPanes: Int) -> some View {
        let isPrimary = orderedPanes.first?.id == pane.id
        PaneContainerView(
            pane: pane,
            frame: frame,
            onResize: { newFrame in
                recordManualLayoutChange()
                // Ensure pane doesn't go under toolbar when resizing
                var constrainedFrame = newFrame
                let minY = settingsDrawerHeight
                if constrainedFrame.origin.y < minY {
                    // If top edge would be under toolbar, adjust origin to keep it below
                    constrainedFrame.origin.y = minY
                }
                // Disable animations during resize to prevent flickering
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    frameManager.updateFrame(id: pane.id, frame: constrainedFrame)
                }
            },
            onDrag: { newOrigin in
                recordManualLayoutChange()
                
                // Initialize drag state on first drag event
                if draggingPaneID != pane.id {
                    draggingPaneID = pane.id
                    if let currentFrame = frameManager.frames[pane.id] {
                        dragStartFrame = currentFrame.frame
                    }
                }
                
                // Get the frame at drag start
                guard let startFrame = dragStartFrame else { return }
                
                // Calculate drag offset from start position
                let minY = settingsDrawerHeight
                let constrainedY = max(newOrigin.y, minY)
                let constrainedOrigin = CGPoint(x: newOrigin.x, y: constrainedY)
                
                // Calculate offset from start position
                dragOffset = CGSize(
                    width: constrainedOrigin.x - startFrame.origin.x,
                    height: constrainedY - startFrame.origin.y
                )
            },
            onDragEnd: {
                // Commit the final position to frame manager
                if let paneID = draggingPaneID,
                   let startFrame = dragStartFrame {
                    var finalFrame = startFrame
                    finalFrame.origin.x += dragOffset.width
                    finalFrame.origin.y += dragOffset.height
                    
                    // Ensure pane doesn't go under toolbar
                    let minY = settingsDrawerHeight
                    finalFrame.origin.y = max(finalFrame.origin.y, minY)
                    
                    // Update frame manager with final position
                    if var paneFrame = frameManager.frames[paneID] {
                        paneFrame.frame = finalFrame
                        frameManager.setFrame(id: paneID, frame: paneFrame)
                    }
                }
                
                // Reset drag state
                draggingPaneID = nil
                dragOffset = .zero
                dragStartFrame = nil
            },
            onClose: {
                removePane(pane)
            },
            onNumberClick: {
                bringPaneToFront(pane)
            },
            totalPanes: totalPanes,
            isPrimary: isPrimary
        )
        .matchedGeometryEffect(id: draggingPaneID == pane.id ? UUID() : pane.id, in: paneNamespace)
        .id(pane.id)
    }
    
    private func paneLayer(index: Int, pane: BrowserPaneViewModel, geometry: GeometryProxy) -> some View {
        let orderedPaneList = orderedPanes
        guard let paneFrame = frameManager.frames[pane.id] else { return AnyView(EmptyView()) }

        let targetPosition = CGPoint(x: paneFrame.frame.midX, y: paneFrame.frame.midY)
        let isRotated3D = displayConfiguration == .rotated3D
        let isLayered = displayConfiguration == .layered
        let isFocused = displayConfiguration == .focused

        let depthScale: CGFloat = 1.0
        let rotationAngle: Double = isRotated3D ? -30 : 0
        let zDepthScale: CGFloat = isRotated3D ? max(0.0, 1.0 - (CGFloat(index) * 0.08)) : 1.0

        let isDragging = draggingPaneID == pane.id
        let offsetX = targetPosition.x - geometry.size.width / 2 + (isDragging ? dragOffset.width : 0)
        let offsetY = targetPosition.y - geometry.size.height / 2 + (isDragging ? dragOffset.height : 0)

        let paneOpacity: Double = {
            if isRotated3D { return max(0.0, 1.0 - Double(index) * 0.08) }
            if isLayered { return max(0.0, 1.0 - Double(index) * 0.08) }
            if isFocused { return index == 0 ? 1.0 : 0.7 }
            return 1.0
        }()

        let scaleEffectValue: CGFloat = isRotated3D ? zDepthScale : depthScale

        let view = paneView(for: pane, frame: paneFrame.frame, zIndex: index, totalPanes: orderedPaneList.count)
            .offset(x: offsetX, y: offsetY)
            .scaleEffect(scaleEffectValue)
            .rotation3DEffect(
                .degrees(rotationAngle),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                perspective: 0.6
            )
            .zIndex(Double(orderedPaneList.count - index))
            .opacity(paneOpacity)
            .modifier(
                PaneCarouselEffect(
                    position: .zero,
                    scale: scaleEffectValue,
                    zIndex: index,
                    totalPanes: orderedPaneList.count
                )
            )

        return AnyView(view)
    }
    
    private func recordManualLayoutChange() {
        if displayConfiguration != .manual {
            displayConfiguration = .manual
        }
    }
    
    private func setDisplayConfiguration(_ configuration: DisplayConfiguration) {
        // Animate the transition when switching between preset views
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75, blendDuration: 0.2)) {
            displayConfiguration = configuration
            if configuration != .manual {
                applyCurrentDisplayConfiguration()
            }
        }
    }
    
    private func applyCurrentDisplayConfiguration(in size: CGSize? = nil) {
        guard displayConfiguration != .manual else { return }
        let targetSize = size ?? containerSize
        guard targetSize.width > 0, targetSize.height > 0 else { return }
        
        switch displayConfiguration {
        case .manual:
            break
        case .tiled:
            arrangePanesTiled(in: targetSize)
        case .focused:
            arrangePanesFocused(in: targetSize)
        case .rotated3D:
            arrangePanesRotated3D(in: targetSize)
        case .layered:
            arrangePanesLayered(in: targetSize)
        }
    }
    
    private func initializePaneFrames(in size: CGSize) {
        guard !panes.isEmpty, size.width > 0, size.height > 0 else { return }
        
        // For a single pane, always arrange it to fill the available space
        if panes.count == 1 {
            arrangePanesTiled(in: size)
            return
        }
        
        if frameManager.frames.count == panes.count {
            adjustPaneFrames(to: size)
            return
        }
        
        arrangePanesTiled(in: size)
    }
    
    private func adjustPaneFrames(to newSize: CGSize) {
        // For a single pane, always arrange it to fill the space instead of scaling
        if panes.count == 1 {
            arrangePanesTiled(in: newSize)
            return
        }
        
        // Scale existing frames proportionally to fit new container
        guard !frameManager.frames.isEmpty, containerSize.width > 0, containerSize.height > 0 else { return }
        
        let scaleX = newSize.width / containerSize.width
        let scaleY = newSize.height / containerSize.height
        let toolbarHeight = settingsDrawerHeight
        
        for paneId in frameManager.frames.keys {
            if var frame = frameManager.frames[paneId] {
                let scaledY = frame.frame.origin.y * scaleY
                // Ensure pane doesn't go under toolbar
                let constrainedY = max(scaledY, toolbarHeight)
                
                frame.frame = CGRect(
                    x: frame.frame.origin.x * scaleX,
                    y: constrainedY,
                    width: frame.frame.width * scaleX,
                    height: frame.frame.height * scaleY
                )
                frameManager.setFrame(id: paneId, frame: frame)
            }
        }
    }
    
    private func arrangePanesTiled(in size: CGSize) {
        let panesToArrange = orderedPanes
        guard !panesToArrange.isEmpty, size.width > 0, size.height > 0 else { return }
        
        let toolbarHeight = settingsDrawerHeight
        let availableWidth = size.width - (panePadding * 2)
        let availableHeight = size.height - (panePadding * 2) - toolbarHeight
        
        switch panesToArrange.count {
        case 1:
            // Make the single pane fill the entire available space (maximize size)
            let pane = panesToArrange[0]
            // Use full width minus side padding, full height minus toolbar and bottom padding
            // Bottom padding matches side padding for consistency
            let maxWidth = size.width - (panePadding * 2)
            let maxHeight = size.height - toolbarHeight - panePadding
            frameManager.setFrame(id: pane.id, frame: PaneFrame(
                id: pane.id,
                frame: CGRect(
                    x: panePadding,
                    y: toolbarHeight,
                    width: maxWidth,
                    height: maxHeight
                )
            ))
            
        case 2:
            let paneWidth = (availableWidth - panePadding) / 2
            let paneHeight = min(availableHeight, paneWidth * 9 / 16)
            let startY = (size.height - toolbarHeight - paneHeight) / 2 + toolbarHeight
            
            frameManager.setFrame(id: panesToArrange[0].id, frame: PaneFrame(
                id: panesToArrange[0].id,
                frame: CGRect(
                    x: panePadding,
                    y: startY,
                    width: paneWidth,
                    height: paneHeight
                )
            ))
            frameManager.setFrame(id: panesToArrange[1].id, frame: PaneFrame(
                id: panesToArrange[1].id,
                frame: CGRect(
                    x: panePadding + paneWidth + panePadding,
                    y: startY,
                    width: paneWidth,
                    height: paneHeight
                )
            ))
            
        case 3:
            let topPaneWidth = (availableWidth - panePadding) / 2
            let topPaneHeight = min(availableHeight / 2 - panePadding / 2, topPaneWidth * 9 / 16)
            let bottomPaneWidth = availableWidth
            let bottomPaneHeight = min(availableHeight / 2 - panePadding / 2, bottomPaneWidth * 9 / 16)
            
            let topStartY = toolbarHeight + panePadding
            let bottomStartY = toolbarHeight + panePadding + topPaneHeight + panePadding
            
            frameManager.setFrame(id: panesToArrange[0].id, frame: PaneFrame(
                id: panesToArrange[0].id,
                frame: CGRect(
                    x: panePadding,
                    y: topStartY,
                    width: topPaneWidth,
                    height: topPaneHeight
                )
            ))
            frameManager.setFrame(id: panesToArrange[1].id, frame: PaneFrame(
                id: panesToArrange[1].id,
                frame: CGRect(
                    x: panePadding + topPaneWidth + panePadding,
                    y: topStartY,
                    width: topPaneWidth,
                    height: topPaneHeight
                )
            ))
            frameManager.setFrame(id: panesToArrange[2].id, frame: PaneFrame(
                id: panesToArrange[2].id,
                frame: CGRect(
                    x: panePadding,
                    y: bottomStartY,
                    width: bottomPaneWidth,
                    height: bottomPaneHeight
                )
            ))
            
        case 4:
            let paneWidth = (availableWidth - panePadding) / 2
            let paneHeight = (availableHeight - panePadding) / 2
            
            frameManager.setFrame(id: panesToArrange[0].id, frame: PaneFrame(
                id: panesToArrange[0].id,
                frame: CGRect(
                    x: panePadding,
                    y: toolbarHeight + panePadding,
                    width: paneWidth,
                    height: paneHeight
                )
            ))
            frameManager.setFrame(id: panesToArrange[1].id, frame: PaneFrame(
                id: panesToArrange[1].id,
                frame: CGRect(
                    x: panePadding + paneWidth + panePadding,
                    y: toolbarHeight + panePadding,
                    width: paneWidth,
                    height: paneHeight
                )
            ))
            frameManager.setFrame(id: panesToArrange[2].id, frame: PaneFrame(
                id: panesToArrange[2].id,
                frame: CGRect(
                    x: panePadding,
                    y: toolbarHeight + panePadding + paneHeight + panePadding,
                    width: paneWidth,
                    height: paneHeight
                )
            ))
            frameManager.setFrame(id: panesToArrange[3].id, frame: PaneFrame(
                id: panesToArrange[3].id,
                frame: CGRect(
                    x: panePadding + paneWidth + panePadding,
                    y: toolbarHeight + panePadding + paneHeight + panePadding,
                    width: paneWidth,
                    height: paneHeight
                )
            ))
            
        default:
            break
        }
    }
    
    private func arrangePanesFocused(in size: CGSize) {
        let panesToArrange = orderedPanes
        guard !panesToArrange.isEmpty else { return }
        
        let toolbarHeight = settingsDrawerHeight
        let innerWidth = size.width - (panePadding * 2)
        let innerHeight = size.height - toolbarHeight - (panePadding * 2)
        guard innerWidth > 0, innerHeight > 0 else { return }
        
        let spacing = panePadding
        let originY = toolbarHeight + panePadding
        
        // Primary pane stays in the top-left with a locked 16:9 ratio.
        let maxPrimaryWidth = min(innerWidth * 0.7, (innerHeight) * (16.0 / 9.0))
        var primaryWidth = maxPrimaryWidth * 1.15
        primaryWidth = min(primaryWidth, innerWidth)
        var primaryHeight = primaryWidth * 9.0 / 16.0
        
        if primaryHeight > innerHeight {
            primaryHeight = innerHeight
            primaryWidth = primaryHeight * 16.0 / 9.0
        }
        
        guard primaryWidth > 0, primaryHeight > 0 else {
            arrangePanesTiled(in: size)
            return
        }
        
        if let primaryPane = panesToArrange.first {
            let primaryFrame = CGRect(
                x: panePadding,
                y: originY,
                width: primaryWidth,
                height: primaryHeight
            )
            frameManager.setFrame(id: primaryPane.id, frame: PaneFrame(id: primaryPane.id, frame: primaryFrame))
        }
        
        let secondaryPanes = Array(panesToArrange.dropFirst())
        guard !secondaryPanes.isEmpty else { return }
        
        // Secondary panes form an L/J shape in the bottom-right.
        let secondaryCount = secondaryPanes.count
        var cellWidth = min(innerWidth * 0.4, primaryWidth * 0.75)
        cellWidth = max(cellWidth, innerWidth * 0.28)
        var cellHeight = cellWidth * 9.0 / 16.0
        if cellHeight > innerHeight {
            cellHeight = innerHeight
            cellWidth = cellHeight * 16.0 / 9.0
        }
        
        guard cellWidth > 0, cellHeight > 0 else {
            arrangePanesTiled(in: size)
            return
        }
        
        let bottomRightOrigin = CGPoint(
            x: panePadding + innerWidth - cellWidth,
            y: originY + innerHeight - cellHeight
        )
        let aboveOrigin = CGPoint(
            x: bottomRightOrigin.x,
            y: max(originY, bottomRightOrigin.y - spacing - cellHeight)
        )
        let leftOrigin = CGPoint(
            x: max(panePadding, bottomRightOrigin.x - spacing - cellWidth),
            y: bottomRightOrigin.y
        )
        
        var placementFrames: [CGRect] = []
        placementFrames.append(CGRect(origin: bottomRightOrigin, size: CGSize(width: cellWidth, height: cellHeight)))
        if secondaryCount >= 2 {
            placementFrames.append(CGRect(origin: aboveOrigin, size: CGSize(width: cellWidth, height: cellHeight)))
        }
        if secondaryCount >= 3 {
            placementFrames.append(CGRect(origin: leftOrigin, size: CGSize(width: cellWidth, height: cellHeight)))
        }
        
        for (pane, frame) in zip(secondaryPanes, placementFrames) {
            frameManager.setFrame(id: pane.id, frame: PaneFrame(id: pane.id, frame: frame))
        }
    }
    
    private func arrangePanesRotated3D(in size: CGSize) {
        guard !panes.isEmpty else { return }
        
        let panesToArrange = orderedPanes
        let toolbarHeight = settingsDrawerHeight
        let availableWidth = size.width - (panePadding * 2)
        let availableHeight = size.height - (panePadding * 2) - toolbarHeight
        
        // All panes get the same size - use a consistent 16:9 ratio
        let standardSize = PaneFrame.initial16x9Size(in: size, padding: panePadding)
        // Scale down slightly to fit (50% larger than original default)
        let paneSize = CGSize(
            width: min(standardSize.width * 1.09375, availableWidth * 0.78125),
            height: min(standardSize.height * 1.09375, availableHeight * 0.78125)
        )
        
        // Stack all panes with X-axis offset - like dominos or walls in a row
        // Each pane behind moves further to the right in even increments
        // Shift base center left to center the entire cluster, then 3% more
        let totalSpan = CGFloat(panesToArrange.count - 1) * 100.0  // Total width of all panes
        let baseCenterX = (size.width / 2) - (totalSpan / 2) - (size.width * 0.03)  // Shift left to center, then 3% more
        let centerY = toolbarHeight + availableHeight / 2
        let xOffsetPerLayer: CGFloat = 100.0  // 100 points per layer
        
        for (index, pane) in panesToArrange.enumerated() {
            // Apply X offset so back panes are visible sticking out from behind
            let xOffset = CGFloat(index) * xOffsetPerLayer
            let centerX = baseCenterX + xOffset
            
            frameManager.setFrame(id: pane.id, frame: PaneFrame(
                id: pane.id,
                frame: CGRect(
                    x: centerX - paneSize.width / 2,
                    y: centerY - paneSize.height / 2,
                    width: paneSize.width,
                    height: paneSize.height
                )
            ))
        }
    }
    
    private func arrangePanesLayered(in size: CGSize) {
        let panesToArrange = orderedPanes
        guard !panesToArrange.isEmpty else { return }
        
        let toolbarHeight = settingsDrawerHeight
        let innerWidth = size.width - (panePadding * 2)
        let innerHeight = size.height - toolbarHeight - (panePadding * 2)
        guard innerWidth > 0, innerHeight > 0 else { return }
        
        let originY = toolbarHeight + panePadding
        
        // All panes are the same size: 90% of the container
        let paneWidth = innerWidth * 0.9
        let paneHeight = innerHeight * 0.9
        
        // Offset primary pane 80px to the right
        let primaryOffsetX: CGFloat = 80.0
        
        // Primary pane in top-left (offset 80px to the right)
        if let primaryPane = panesToArrange.first {
            let primaryFrame = CGRect(
                x: panePadding + primaryOffsetX,
                y: originY,
                width: paneWidth,
                height: paneHeight
            )
            frameManager.setFrame(id: primaryPane.id, frame: PaneFrame(id: primaryPane.id, frame: primaryFrame))
        }
        
        // Secondary panes layered in bottom-right with even overlap from primary pane
        let secondaryPanes = Array(panesToArrange.dropFirst())
        guard !secondaryPanes.isEmpty else { return }
        
        // Calculate the primary pane's bottom-right corner (starting point for secondary panes)
        let primaryBottomRightX = panePadding + primaryOffsetX + paneWidth
        let primaryBottomRightY = originY + paneHeight
        
        // Offset amount for each layer - enough to see a bit of each pane sticking out
        // Use a percentage of the pane size to ensure even overlap
        let overlapOffset: CGFloat = min(paneWidth * 0.04, paneHeight * 0.04, 20) // 4% of size or 20 points, whichever is smaller
        
        for (index, pane) in secondaryPanes.enumerated() {
            // Each secondary pane is offset evenly from the primary pane
            // Front panes (lower index, higher z) are closer to primary (less offset)
            // Back panes (higher index, lower z) are further from primary (more offset)
            // Offset moves right and down from primary's bottom-right corner
            let offsetX = CGFloat(index + 1) * overlapOffset
            let offsetY = CGFloat(index + 1) * overlapOffset
            
            let paneFrame = CGRect(
                x: primaryBottomRightX - paneWidth + offsetX,
                y: primaryBottomRightY - paneHeight + offsetY,
                width: paneWidth,
                height: paneHeight
            )
            frameManager.setFrame(id: pane.id, frame: PaneFrame(id: pane.id, frame: paneFrame))
        }
    }
    
    private func addPane() {
        guard panes.count < maxPanes else { return }
        let newPane = BrowserPaneViewModel()
        newPane.displayNumber = nextAvailableDisplayNumber()
        newPane.shouldFocusURL = true
        
        // Assign a unique border color index (default, not enabled)
        let usedIndices = Set(panes.map { $0.borderColorIndex })
        let availableIndices = Array(0..<BrowserPaneViewModel.borderColors.count)
        if let unusedIndex = availableIndices.first(where: { !usedIndices.contains($0) }) {
            newPane.borderColorIndex = unusedIndex
        } else {
            // If all colors are used, cycle through them
            newPane.borderColorIndex = panes.count % BrowserPaneViewModel.borderColors.count
        }
        
        // Load default URL if set
        if let defaultURL = UserDefaults.standard.string(forKey: "defaultURL"),
           !defaultURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Load the URL - the view model will handle it even if web view isn't ready yet
            newPane.loadURL(defaultURL)
        }
        
        panes.append(newPane)
        syncPaneOrderWithPanes()
        applyCurrentDisplayConfiguration()
    }
    
    private func removePane(_ pane: BrowserPaneViewModel) {
        guard let index = panes.firstIndex(where: { $0.id == pane.id }) else { return }
        
        // Clean up the web view resources
        if let webView = pane.webView {
            webView.stopLoading()
            webView.navigationDelegate = nil
        }
        
        // Remove the pane
        panes.remove(at: index)
        frameManager.removeFrame(id: pane.id)
        syncPaneOrderWithPanes()
        applyCurrentDisplayConfiguration()
    }
    
    private func removePane(at index: Int) {
        guard index < panes.count else { return }
        removePane(panes[index])
    }

    @ViewBuilder
    private var paneKeyboardShortcutOverlay: some View {
        ZStack {
            // Command + N: New pane
            Button(action: addPane) {
                EmptyView()
            }
            .keyboardShortcut("n", modifiers: [.command])
            
            // Command + Shift + W: Close highlighted/active pane
            Button(action: closeActivePane) {
                EmptyView()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            
            // Command + 0: Toggle settings drawer
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSettingsDrawerOpen.toggle()
                }
            }) {
                EmptyView()
            }
            .keyboardShortcut("0", modifiers: [.command])
            
            // Command + 9: Toggle cursor highlight
            Button(action: {
                cursorHighlightManager.isEnabled.toggle()
            }) {
                EmptyView()
            }
            .keyboardShortcut("9", modifiers: [.command])
            
            // Command + J, K, L, ;: Toggle view modes
            // J = Tiled, K = Layered, L = Focused, ; = Rotated 3D
            Button(action: {
                setDisplayConfiguration(.tiled)
            }) {
                EmptyView()
            }
            .keyboardShortcut("j", modifiers: [.command])
            
            Button(action: {
                setDisplayConfiguration(.layered)
            }) {
                EmptyView()
            }
            .keyboardShortcut("k", modifiers: [.command])
            
            Button(action: {
                setDisplayConfiguration(.focused)
            }) {
                EmptyView()
            }
            .keyboardShortcut("l", modifiers: [.command])
            
            Button(action: {
                setDisplayConfiguration(.rotated3D)
            }) {
                EmptyView()
            }
            .keyboardShortcut(";", modifiers: [.command])
            
            // Command + 1, 2, 3, 4: Select panes by display number
            ForEach(orderedPanes) { pane in
                if pane.displayNumber > 0 && pane.displayNumber <= 4 {
                    Button(action: {
                        bringPaneToFront(pane)
                    }) {
                        EmptyView()
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(pane.displayNumber))), modifiers: [.command])
                }
            }
            
            // Command + R: Refresh the primary pane
            Button(action: {
                if let primaryPane = orderedPanes.first {
                    primaryPane.reload()
                }
            }) {
                EmptyView()
            }
            .keyboardShortcut("r", modifiers: [.command])
            
            // Command + ]: Cycle panes counter-clockwise
            Button(action: cyclePanesCounterClockwise) {
                EmptyView()
            }
            .keyboardShortcut("]", modifiers: [.command])
            
            // Command + [: Cycle panes clockwise
            Button(action: cyclePanesClockwise) {
                EmptyView()
            }
            .keyboardShortcut("[", modifiers: [.command])
        }
        .frame(width: 0, height: 0)
        .opacity(0.001)
    }
    
    private func closeActivePane() {
        // Close the highlighted/active pane (first in orderedPanes)
        guard let activePane = orderedPanes.first else { return }
        removePane(activePane)
    }
    
    private func bringPaneToFront(_ pane: BrowserPaneViewModel, swapFrames: Bool = true, fromKeyboardCycle: Bool = false) {
        let oldOrder = orderedPaneIDs()
        guard let currentIndex = oldOrder.firstIndex(of: pane.id) else { return }
        guard currentIndex != 0 else { return }
        
        // For rotated3D mode, don't change to manual - keep the 3D layout. When cycling via keyboard, don't record manual layout change.
        if displayConfiguration != .rotated3D && !fromKeyboardCycle {
            recordManualLayoutChange()
        }
        
        var newOrder = oldOrder
        let movedPaneID = newOrder.remove(at: currentIndex)
        newOrder.insert(movedPaneID, at: 0)
        
        // When not swapping frames (e.g. keyboard cycle), only update z-order so visual positions stay fixed
        if !swapFrames {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0.2)) {
                paneOrder = newOrder
            }
            return
        }
        
        // For rotated3D mode, panes swap both Z-order and X positions
        if displayConfiguration == .rotated3D {
            // Get the base center X and calculate new X positions for each pane based on new order
            // Use the same logic as arrangePanesRotated3D to calculate X offsets
            let xOffsetPerLayer: CGFloat = 100.0  // Same as in arrangePanesRotated3D
            // Shift base center left to center the entire cluster, then 3% more
            let totalSpan = CGFloat(newOrder.count - 1) * xOffsetPerLayer
            let baseCenterX = (containerSize.width / 2) - (totalSpan / 2) - (containerSize.width * 0.03)
            
            // Capture current frame info (we need Y, width, height to preserve them)
            let frameInfo: [(y: CGFloat, width: CGFloat, height: CGFloat)] = newOrder.map { paneID in
                if let frame = frameManager.frames[paneID]?.frame {
                    return (frame.origin.y, frame.width, frame.height)
                } else {
                    // Fallback - shouldn't happen but just in case
                    return (0, 0, 0)
                }
            }
            
            let animation = Animation.spring(response: 0.7, dampingFraction: 0.8, blendDuration: 0.3)
            withAnimation(animation) {
                paneOrder = newOrder
                
                // Update X positions based on new order - each pane gets X position based on its new index
                for (newIndex, paneID) in newOrder.enumerated() {
                    if newIndex < frameInfo.count {
                        let xOffset = CGFloat(newIndex) * xOffsetPerLayer
                        let centerX = baseCenterX + xOffset
                        let info = frameInfo[newIndex]
                        
                        if var paneFrame = frameManager.frames[paneID] {
                            paneFrame.frame = CGRect(
                                x: centerX - info.width / 2,  // New X position based on new index
                                y: info.y,  // Preserve Y position
                                width: info.width,  // Preserve width
                                height: info.height  // Preserve height
                            )
                            frameManager.setFrame(id: paneID, frame: paneFrame)
                        }
                    }
                }
            }
        } else {
            // For other modes, use carousel frame swapping
            let slotFrames: [CGRect] = oldOrder.enumerated().map { index, paneID in
                if let frame = frameManager.frames[paneID]?.frame {
                    return frame
                } else {
                    return defaultCarouselFrame(forSlot: index)
                }
            }
            
            // Use a more dramatic animation with explicit easing
            let animation = Animation.spring(response: 0.7, dampingFraction: 0.8, blendDuration: 0.3)
            
            withAnimation(animation) {
                paneOrder = newOrder
                applyCarouselFrames(slotFrames, to: newOrder)
            }
        }
    }
    
    private func orderedPaneIDs() -> [UUID] {
        orderedPanes.map { $0.id }
    }
    
    private func applyCarouselFrames(_ slotFrames: [CGRect], to order: [UUID]) {
        for (index, paneID) in order.enumerated() {
            guard index < slotFrames.count else { break }
            let frame = slotFrames[index]
            if var existingFrame = frameManager.frames[paneID] {
                existingFrame.frame = frame
                frameManager.setFrame(id: paneID, frame: existingFrame)
            } else {
                frameManager.setFrame(id: paneID, frame: PaneFrame(id: paneID, frame: frame))
            }
        }
    }
    
    private func defaultCarouselFrame(forSlot index: Int) -> CGRect {
        let size = defaultPaneSize()
        let offset = CGFloat(index) * 32
        let origin = CGPoint(
            x: panePadding + offset,
            y: settingsDrawerHeight + panePadding + offset
        )
        return CGRect(origin: origin, size: size)
    }
    
    private func defaultPaneSize() -> CGSize {
        guard containerSize.width > 0, containerSize.height > 0 else {
            return CGSize(width: 640, height: 360)
        }
        
        let proposedSize = PaneFrame.initial16x9Size(in: containerSize, padding: panePadding)
        let width = max(320, proposedSize.width)
        let height = max(180, proposedSize.height)
        return CGSize(width: width, height: height)
    }

    private func scheduleSettingsAutoClose() {
        cancelSettingsAutoClose()
        guard isSettingsDrawerOpen, autoCloseSettingsMenu, !isMouseInSettingsDrawer else { return }

        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSettingsDrawerOpen = false
            }
        }
        settingsAutoCloseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + settingsAutoCloseDelay, execute: workItem)
    }

    private func cancelSettingsAutoClose() {
        settingsAutoCloseWorkItem?.cancel()
        settingsAutoCloseWorkItem = nil
    }

    private func handleSettingsDrawerHover(_ hovering: Bool) {
        isMouseInSettingsDrawer = hovering
        if hovering {
            cancelSettingsAutoClose()
        } else {
            scheduleSettingsAutoClose()
        }
    }
    
    private func nextAvailableDisplayNumber() -> Int {
        let usedNumbers = Set(panes.map { $0.displayNumber })
        var candidate = 1
        while usedNumbers.contains(candidate) {
            candidate += 1
        }
        return candidate
    }
    
    private func syncPaneOrderWithPanes() {
        let existingIDs = panes.map { $0.id }
        paneOrder = paneOrder.filter { existingIDs.contains($0) }
        for id in existingIDs where !paneOrder.contains(id) {
            paneOrder.append(id)
        }
    }

    private func saveDemo(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let snapshots = captureDemoSnapshots()
        demoStore.save(name: trimmedName, displayConfiguration: displayConfiguration, panes: snapshots)
    }
    
    private func deleteDemo(_ demo: DemoLayout) {
        demoStore.remove(id: demo.id)
    }
    
    private func applyDemo(_ demo: DemoLayout) {
        isApplyingDemo = true
        openSettingsMenuPaneID = nil
        draggingPaneID = nil
        dragOffset = .zero
        dragStartFrame = nil
        
        for pane in panes {
            pane.isSettingsMenuOpen = false
            if let webView = pane.webView {
                webView.stopLoading()
                webView.navigationDelegate = nil
            }
        }
        
        panes.removeAll()
        paneOrder.removeAll()
        frameManager.frames = [:]
        displayConfiguration = demo.displayConfiguration
        
        let snapshots = Array(demo.panes.prefix(maxPanes))
        var usedDisplayNumbers = Set<Int>()
        var newPanes: [BrowserPaneViewModel] = []
        
        for (index, snapshot) in snapshots.enumerated() {
            let pane = BrowserPaneViewModel()
            pane.shouldFocusURL = false
            pane.displayNumber = resolvedDisplayNumber(snapshot.displayNumber, usedNumbers: &usedDisplayNumbers)
            pane.showBorder = snapshot.showBorder
            
            let colorIndex = min(max(snapshot.borderColorIndex, 0), BrowserPaneViewModel.borderColors.count - 1)
            pane.borderColorIndex = colorIndex
            pane.paneTitle = snapshot.title
            pane.zoomSetting = snapshot.zoomSetting
            
            let trimmedURL = snapshot.url.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedURL.isEmpty {
                pane.loadURL(trimmedURL)
            }
            
            newPanes.append(pane)
            
            if demo.displayConfiguration == .manual {
                let frame = snapshot.frame.rect
                frameManager.setFrame(id: pane.id, frame: PaneFrame(id: pane.id, frame: frame))
            } else if frameManager.frames[pane.id] == nil {
                let fallback = defaultCarouselFrame(forSlot: index)
                frameManager.setFrame(id: pane.id, frame: PaneFrame(id: pane.id, frame: fallback))
            }
        }
        
        panes = newPanes
        paneOrder = newPanes.map { $0.id }
        
        if displayConfiguration != .manual {
            applyCurrentDisplayConfiguration()
        }
        
        DispatchQueue.main.async {
            isApplyingDemo = false
        }
    }
    
    private func captureDemoSnapshots() -> [DemoPaneSnapshot] {
        orderedPanes.enumerated().map { index, pane in
            let frame = frameManager.frames[pane.id]?.frame ?? defaultCarouselFrame(forSlot: index)
            return DemoPaneSnapshot(
                title: pane.paneTitle,
                showBorder: pane.showBorder,
                borderColorIndex: pane.borderColorIndex,
                zoomSetting: pane.zoomSetting,
                displayNumber: pane.displayNumber,
                url: pane.currentURL,
                frame: DemoFrame(rect: frame)
            )
        }
    }
    
    private func resolvedDisplayNumber(_ requested: Int, usedNumbers: inout Set<Int>) -> Int {
        if requested > 0, requested <= maxPanes, !usedNumbers.contains(requested) {
            usedNumbers.insert(requested)
            return requested
        }
        
        var candidate = 1
        while usedNumbers.contains(candidate) && candidate <= maxPanes {
            candidate += 1
        }
        if candidate > maxPanes {
            candidate = maxPanes
        }
        usedNumbers.insert(candidate)
        return candidate
    }
    
    // MARK: - Visual position pane cycling (⌘] / ⌘[)
    // Uses current frame positions to compute a clockwise order:
    // top-left → top-right → bottom-right → bottom-left (wrapping as needed).
    
    private func cyclePanesClockwise() {
        cyclePanes(.clockwise)
    }
    
    private func cyclePanesCounterClockwise() {
        cyclePanes(.counterClockwise)
    }
    
    private enum PaneCycleDirection {
        case clockwise
        case counterClockwise
    }
    
    private func cyclePanes(_ direction: PaneCycleDirection) {
        let visualOrder = visualPaneOrder()
        let count = visualOrder.count
        guard count >= 2 else { return }
        guard let primaryPane = orderedPanes.first,
              let primaryIndex = visualOrder.firstIndex(where: { $0.id == primaryPane.id }) else { return }
        
        let nextIndex: Int
        let frameShift: Int
        switch direction {
        case .clockwise:
            nextIndex = (primaryIndex + 1) % count
            // Shift panes counter-clockwise so the next pane moves into the primary slot.
            frameShift = -1
        case .counterClockwise:
            nextIndex = (primaryIndex - 1 + count) % count
            // Shift panes clockwise so the previous pane moves into the primary slot.
            frameShift = 1
        }
        
        let paneToFront = visualOrder[nextIndex]
        if displayConfiguration == .rotated3D {
            rotateRotated3DStack(direction: direction)
        } else if displayConfiguration == .layered {
            rotateLayeredStack(direction: direction)
        } else {
            rotatePaneFrames(in: visualOrder, shift: frameShift)
            bringPaneToFront(paneToFront, swapFrames: false, fromKeyboardCycle: true)
        }
    }
    
    private func visualPaneOrder() -> [BrowserPaneViewModel] {
        let panesWithFrames = orderedPanes.compactMap { pane -> (BrowserPaneViewModel, CGRect)? in
            guard let frame = frameManager.frames[pane.id]?.frame else { return nil }
            return (pane, frame)
        }
        
        guard panesWithFrames.count == orderedPanes.count else {
            return orderedPanes
        }
        
        let centers = panesWithFrames.map { CGPoint(x: $0.1.midX, y: $0.1.midY) }
        let centerX = centers.reduce(0) { $0 + $1.x } / CGFloat(centers.count)
        let centerY = centers.reduce(0) { $0 + $1.y } / CGFloat(centers.count)
        let centroid = CGPoint(x: centerX, y: centerY)
        
        let ordered = panesWithFrames.map { pane, frame -> (pane: BrowserPaneViewModel, angle: Double, distance: Double, center: CGPoint) in
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let dx = center.x - centroid.x
            let dy = center.y - centroid.y
            let angle = atan2(dy, dx) // y axis increases downward; ascending angle yields clockwise order
            let distance = hypot(dx, dy)
            return (pane, angle, distance, center)
        }
        .sorted { lhs, rhs in
            if abs(lhs.angle - rhs.angle) > 0.0001 {
                return lhs.angle < rhs.angle
            }
            if abs(lhs.distance - rhs.distance) > 0.0001 {
                return lhs.distance < rhs.distance
            }
            if abs(lhs.center.y - rhs.center.y) > 0.0001 {
                return lhs.center.y < rhs.center.y
            }
            return lhs.center.x < rhs.center.x
        }
        
        return ordered.map { $0.pane }
    }
    
    private func rotatePaneFrames(in ordered: [BrowserPaneViewModel], shift: Int) {
        let count = ordered.count
        guard count >= 2 else { return }
        
        let frames = ordered.enumerated().map { index, pane in
            frameManager.frames[pane.id]?.frame ?? defaultCarouselFrame(forSlot: index)
        }
        let animation = Animation.spring(response: 0.7, dampingFraction: 0.8, blendDuration: 0.3)
        
        withAnimation(animation) {
            for (index, pane) in ordered.enumerated() {
                let sourceIndex = (index + shift + count) % count
                let frame = frames[sourceIndex]
                if var existingFrame = frameManager.frames[pane.id] {
                    existingFrame.frame = frame
                    frameManager.setFrame(id: pane.id, frame: existingFrame)
                } else {
                    frameManager.setFrame(id: pane.id, frame: PaneFrame(id: pane.id, frame: frame))
                }
            }
        }
    }

    private func rotateRotated3DStack(direction: PaneCycleDirection) {
        let currentOrder = orderedPaneIDs()
        let count = currentOrder.count
        guard count >= 2 else { return }

        var newOrder = currentOrder
        switch direction {
        case .clockwise:
            // Move primary (front) to the back.
            let front = newOrder.removeFirst()
            newOrder.append(front)
        case .counterClockwise:
            // Move farthest back to the front.
            if let back = newOrder.popLast() {
                newOrder.insert(back, at: 0)
            }
        }

        applyRotated3DOrder(newOrder)
    }

    private func applyRotated3DOrder(_ order: [UUID]) {
        let count = order.count
        guard count >= 1 else { return }

        let xOffsetPerLayer: CGFloat = 100.0
        let totalSpan = CGFloat(count - 1) * xOffsetPerLayer
        let baseCenterX = (containerSize.width / 2) - (totalSpan / 2) - (containerSize.width * 0.03)

        let frameInfo: [(y: CGFloat, width: CGFloat, height: CGFloat)] = order.map { paneID in
            if let frame = frameManager.frames[paneID]?.frame {
                return (frame.origin.y, frame.width, frame.height)
            }
            let fallback = defaultCarouselFrame(forSlot: 0)
            return (fallback.origin.y, fallback.width, fallback.height)
        }

        let animation = Animation.spring(response: 0.7, dampingFraction: 0.8, blendDuration: 0.3)
        withAnimation(animation) {
            paneOrder = order
            for (newIndex, paneID) in order.enumerated() {
                let xOffset = CGFloat(newIndex) * xOffsetPerLayer
                let centerX = baseCenterX + xOffset
                let info = frameInfo[newIndex]
                if var paneFrame = frameManager.frames[paneID] {
                    paneFrame.frame = CGRect(
                        x: centerX - info.width / 2,
                        y: info.y,
                        width: info.width,
                        height: info.height
                    )
                    frameManager.setFrame(id: paneID, frame: paneFrame)
                }
            }
        }
    }

    private func rotateLayeredStack(direction: PaneCycleDirection) {
        let currentOrder = orderedPaneIDs()
        let count = currentOrder.count
        guard count >= 2 else { return }

        var newOrder = currentOrder
        switch direction {
        case .clockwise:
            let front = newOrder.removeFirst()
            newOrder.append(front)
        case .counterClockwise:
            if let back = newOrder.popLast() {
                newOrder.insert(back, at: 0)
            }
        }

        applyLayeredOrder(newOrder)
    }

    private func applyLayeredOrder(_ order: [UUID]) {
        guard !order.isEmpty else { return }
        let animation = Animation.spring(response: 0.7, dampingFraction: 0.8, blendDuration: 0.3)

        withAnimation(animation) {
            paneOrder = order
            arrangePanesLayered(in: containerSize)
        }
    }
}

