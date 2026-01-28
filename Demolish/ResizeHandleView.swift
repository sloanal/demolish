//
//  ResizeHandleView.swift
//  Demolish
//
//  Resize handle for bottom-right corner of panes
//

import SwiftUI

struct ResizeHandleView: View {
    let paneId: UUID
    let frame: CGRect
    let onResize: (CGRect) -> Void
    
    @State private var isDragging = false
    @State private var isHovering = false
    @State private var initialFrame: CGRect = .zero
    
    // Small, precise hover area at bottom-right corner
    private let handleSize: CGFloat = 30
    private let handleOffset: CGFloat = 12 // Offset from corner
    private let circleRadius: CGFloat = 4
    private let minPaneSize: CGFloat = 200
    
    var body: some View {
        GeometryReader { geometry in
            // Position handle at bottom-right corner with small offset
            // Adjusted: moved down 15px and right 15px
            let handleX = geometry.size.width - handleOffset + 15
            let handleY = geometry.size.height - handleOffset + 15
            
            ZStack {
                // Precise hover area - small square at bottom-right corner
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: handleSize, height: handleSize)
                    .contentShape(Rectangle())
                    .position(x: handleX, y: handleY)
                    .allowsHitTesting(true)
                    .onHover { hovering in
                        isHovering = hovering
                        if hovering && !isDragging {
                            NSCursor.openHand.push()
                        } else if !hovering {
                            NSCursor.pop()
                            NSCursor.arrow.set()
                        }
                    }
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    initialFrame = frame
                                    NSCursor.closedHand.push()
                                }
                                
                                let deltaX = value.translation.width
                                let deltaY = value.translation.height
                                
                                var newFrame = initialFrame
                                
                                // Only resize from bottom-right (keep origin, change size)
                                newFrame.size.width += deltaX
                                newFrame.size.height += deltaY
                                
                                // Enforce minimum size
                                if newFrame.size.width < minPaneSize {
                                    newFrame.size.width = minPaneSize
                                }
                                if newFrame.size.height < minPaneSize {
                                    newFrame.size.height = minPaneSize
                                }
                                
                                onResize(newFrame)
                            }
                            .onEnded { _ in
                                isDragging = false
                                NSCursor.pop()
                                if isHovering {
                                    NSCursor.openHand.push()
                                } else {
                                    NSCursor.arrow.set()
                                }
                            }
                    )
                
                // Visual indicator circle
                if isHovering || isDragging {
                    Circle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: circleRadius * 2, height: circleRadius * 2)
                        .position(x: handleX, y: handleY)
                        .transition(.opacity)
                }
            }
        }
    }
}

