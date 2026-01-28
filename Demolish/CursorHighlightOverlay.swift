//
//  CursorHighlightOverlay.swift
//  Demolish
//
//  Overlay view that displays a cursor highlight circle
//

import SwiftUI
import AppKit

struct CursorHighlightOverlay: View {
    @ObservedObject var manager: CursorHighlightManager
    @State private var mouseLocation: CGPoint = .zero
    @State private var trackingTimer: Timer?
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if manager.isEnabled {
                    // Cursor highlight circle with pulse animation
                    Circle()
                        .fill(manager.selectedColor.color.opacity(0.5))
                        .frame(width: manager.size, height: manager.size)
                        .scaleEffect(pulseScale)
                        .position(mouseLocation)
                        .allowsHitTesting(false)
                    
                    // Opaque center circle (4px wide = 4pt radius)
                    Circle()
                        .fill(manager.selectedColor.color)
                        .frame(width: 4, height: 4)
                        .position(mouseLocation)
                        .allowsHitTesting(false)
                }
            }
            .background(
                MouseTrackingView(
                    onMouseMove: { location in
                        mouseLocation = location
                    },
                    onMouseClick: {
                        triggerPulse()
                    }
                )
            )
            .onAppear {
                startTracking()
                updateCursorVisibility()
            }
            .onDisappear {
                stopTracking()
                restoreCursor()
            }
            .onChange(of: manager.isEnabled) { oldValue, newValue in
                if manager.isEnabled {
                    startTracking()
                } else {
                    stopTracking()
                }
                updateCursorVisibility()
            }
            .onChange(of: manager.hideCursor) { oldValue, newValue in
                updateCursorVisibility()
            }
        }
        .allowsHitTesting(false)
    }
    
    private func triggerPulse() {
        withAnimation(.easeOut(duration: 0.15)) {
            pulseScale = 1.30
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.15)) {
                pulseScale = 1.0
            }
        }
    }
    
    private func startTracking() {
        stopTracking()
        // Mouse tracking is handled by MouseTrackingView
    }
    
    private func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }
    
    private func updateCursorVisibility() {
        if manager.isEnabled && manager.hideCursor {
            NSCursor.hide()
        } else {
            NSCursor.unhide()
        }
    }
    
    private func restoreCursor() {
        NSCursor.unhide()
    }
}

// NSView wrapper for mouse tracking
struct MouseTrackingView: NSViewRepresentable {
    var onMouseMove: (CGPoint) -> Void
    var onMouseClick: () -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = MouseTrackingNSView()
        view.onMouseMove = onMouseMove
        view.onMouseClick = onMouseClick
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let trackingView = nsView as? MouseTrackingNSView {
            trackingView.onMouseMove = onMouseMove
            trackingView.onMouseClick = onMouseClick
        }
    }
}

class MouseTrackingNSView: NSView {
    var onMouseMove: ((CGPoint) -> Void)?
    var onMouseClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var trackingTimer: Timer?
    private var eventMonitor: Any?
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
        startTimer()
        startEventMonitoring()
    }
    
    override func removeFromSuperview() {
        stopTimer()
        stopEventMonitoring()
        super.removeFromSuperview()
    }
    
    private func startEventMonitoring() {
        stopEventMonitoring()
        
        // Monitor mouse clicks globally for this window
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.onMouseClick?()
            return event // Return the event so it continues to be processed
        }
    }
    
    private func stopEventMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        
        let options: NSTrackingArea.Options = [
            .activeAlways,
            .mouseMoved,
            .mouseEnteredAndExited,
            .inVisibleRect
        ]
        
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        
        if let trackingArea = trackingArea {
            addTrackingArea(trackingArea)
        }
    }
    
    private func startTimer() {
        stopTimer()
        trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            self?.updateMouseLocation()
        }
    }
    
    private func stopTimer() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }
    
    private func updateMouseLocation() {
        guard let window = window else { return }
        let screenLocation = NSEvent.mouseLocation
        let windowFrame = window.frame
        
        // Check if mouse is within window bounds
        let mouseInWindow = screenLocation.x >= windowFrame.minX && 
                           screenLocation.x <= windowFrame.maxX &&
                           screenLocation.y >= windowFrame.minY && 
                           screenLocation.y <= windowFrame.maxY
        
        if mouseInWindow {
            // Convert screen coordinates to window coordinates, then to view coordinates
            let windowLocation = CGPoint(
                x: screenLocation.x - windowFrame.origin.x,
                y: screenLocation.y - windowFrame.origin.y
            )
            
            // Convert window coordinates to view coordinates (flip Y axis)
            let viewLocation = convert(windowLocation, from: nil)
            let viewHeight = bounds.height
            let convertedLocation = CGPoint(
                x: viewLocation.x,
                y: viewHeight - viewLocation.y
            )
            
            onMouseMove?(convertedLocation)
        }
    }
    
    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        // Convert from bottom-left origin to top-left origin
        let viewHeight = bounds.height
        let convertedLocation = CGPoint(
            x: location.x,
            y: viewHeight - location.y
        )
        onMouseMove?(convertedLocation)
    }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return false
    }
}

