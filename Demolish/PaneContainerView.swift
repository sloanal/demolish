//
//  PaneContainerView.swift
//  Demolish
//
//  Container view for a pane with drag and resize capabilities
//

import SwiftUI
import AppKit

struct PaneContainerView: View {
    @ObservedObject var pane: BrowserPaneViewModel
    let frame: CGRect
    let onResize: (CGRect) -> Void
    let onDrag: (CGPoint) -> Void
    let onDragEnd: (() -> Void)?
    let onClose: () -> Void
    let onNumberClick: (() -> Void)?
    let totalPanes: Int
    let isPrimary: Bool
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Main content - toolbar has priority for hit testing
            BrowserPaneView(viewModel: pane, onClose: onClose, onNumberClick: onNumberClick, totalPanes: totalPanes, paneFrame: frame, isPrimary: isPrimary)
                .frame(width: frame.width, height: frame.height)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 0.35, green: 0.40, blue: 0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            pane.showBorder ? pane.borderColor : Color(NSColor.separatorColor).opacity(0.3),
                            lineWidth: pane.showBorder ? 6 : 1
                        )
                        .animation(.easeInOut(duration: 0.2), value: pane.showBorder)
                        .animation(.easeInOut(duration: 0.2), value: pane.borderColorIndex)
                )
                .compositingGroup()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.15), radius: 16, x: 0, y: 4)
                .zIndex(1) // Toolbar content has higher priority
            
            // Drag handle - positioned below toolbar, only responds to direct hover
            DragHandleView(
                paneId: pane.id,
                frame: frame,
                onDrag: onDrag,
                onDragEnd: onDragEnd
            )
            .zIndex(0) // Lower priority than toolbar
            
            // Resize handle - positioned at bottom-right corner
            ResizeHandleView(
                paneId: pane.id,
                frame: frame,
                onResize: onResize
            )
            .zIndex(0) // Lower priority than toolbar
        }
        .frame(width: frame.width, height: frame.height)
        .overlay(alignment: .bottomTrailing) {
            // Title tab hanging off bottom right edge
            if !pane.paneTitle.isEmpty || pane.showAvatar {
                PaneTitleTab(
                    title: pane.paneTitle,
                    showAvatar: pane.showAvatar,
                    borderColor: pane.showBorder ? pane.borderColor : Color.gray,
                    borderColorIndex: pane.borderColorIndex,
                    onClick: !isPrimary ? onNumberClick : nil
                )
                .offset(x: -12, y: 15) // Position below pane, right edge flush with pane's corner radius (12px)
                .animation(.easeInOut(duration: 0.2), value: pane.paneTitle)
                .animation(.easeInOut(duration: 0.2), value: pane.showAvatar)
                .animation(.easeInOut(duration: 0.2), value: pane.borderColorIndex)
                .animation(.easeInOut(duration: 0.2), value: pane.showBorder)
            }
        }
    }
}

// Tab-style title view hanging off bottom right
struct PaneTitleTab: View {
    let title: String
    let showAvatar: Bool
    let borderColor: Color
    let borderColorIndex: Int
    let onClick: (() -> Void)?
    
    @State private var isHovered = false
    
    private let tabHeight: CGFloat = 15
    
    var body: some View {
        Button(action: {
            onClick?()
        }) {
            HStack(spacing: 6) {
                if showAvatar {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [borderColor.opacity(0.9), borderColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 18, height: 18)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.white)
                        )
                }
                
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .frame(maxWidth: 200) // Allow about 40-50 characters
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: tabHeight)
            .background(
                // Custom shape with rounded bottom corners only
                TabShape()
                    .fill(borderColor.opacity(onClick != nil && isHovered ? 0.9 : 1.0))
            )
        }
        .buttonStyle(.plain)
        .disabled(onClick == nil)
        .help(onClick != nil ? "Bring pane to front" : "")
        .onHover { hovering in
            if onClick != nil {
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

// Custom shape with rounded bottom corners, square top corners
struct TabShape: Shape {
    private let cornerRadius: CGFloat = 8
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Start at top-left (square corner)
        path.move(to: CGPoint(x: 0, y: 0))
        
        // Line to top-right (square corner)
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        
        // Line to bottom-right, then rounded corner
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.width - cornerRadius, y: rect.height),
            control: CGPoint(x: rect.width, y: rect.height)
        )
        
        // Line to bottom-left, then rounded corner
        path.addLine(to: CGPoint(x: cornerRadius, y: rect.height))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.height - cornerRadius),
            control: CGPoint(x: 0, y: rect.height)
        )
        
        // Close path back to start
        path.closeSubpath()
        
        return path
    }
}


