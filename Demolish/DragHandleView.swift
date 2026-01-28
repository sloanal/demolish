//
//  DragHandleView.swift
//  Demolish
//
//  Drag handle for top-left corner of panes
//

import SwiftUI

struct DragHandleView: View {
    let paneId: UUID
    let frame: CGRect
    let onDrag: (CGPoint) -> Void
    let onDragEnd: (() -> Void)?
    
    @State private var isDragging = false
    @State private var isHovering = false
    @State private var initialOrigin: CGPoint = .zero
    
    // Small, precise hover area positioned well below toolbar
    private let handleSize: CGFloat = 30
    private let toolbarExclusionHeight: CGFloat = 60 // Toolbar area to exclude
    private let handleOffsetX: CGFloat = 12 // Offset from left edge
    private let handleOffsetY: CGFloat = 12 // Offset from top edge (below toolbar)
    private let circleRadius: CGFloat = 4
    
    var body: some View {
        GeometryReader { geometry in
            // Position handle well below toolbar, in top-left corner area
            // Adjusted: moved up 75px and left 15px
            let handleX = handleOffsetX - 15
            let handleY = toolbarExclusionHeight + handleOffsetY - 75
            
            ZStack {
                // Precise hover area - small square positioned below toolbar
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
                                    initialOrigin = frame.origin
                                    NSCursor.closedHand.push()
                                }
                                
                                let deltaX = value.translation.width
                                let deltaY = value.translation.height
                                
                                let newX = initialOrigin.x + deltaX
                                let newY = initialOrigin.y + deltaY
                                
                                onDrag(CGPoint(x: newX, y: newY))
                            }
                            .onEnded { _ in
                                if isDragging {
                                    isDragging = false
                                    NSCursor.pop()
                                    if isHovering {
                                        NSCursor.openHand.push()
                                    } else {
                                        NSCursor.arrow.set()
                                    }
                                    onDragEnd?()
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
