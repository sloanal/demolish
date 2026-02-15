//
//  TooltipView.swift
//  Demolish
//
//  Reusable tooltip component with debounce
//

import SwiftUI

struct TooltipModifier: ViewModifier {
    let text: String
    let delay: TimeInterval
    let position: TooltipPosition
    let verticalOffset: CGFloat
    
    enum TooltipPosition {
        case top
        case bottom
    }
    
    @State private var showTooltip = false
    @State private var hoverTask: Task<Void, Never>?
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: position == .top ? .top : .bottom) {
                if showTooltip {
                    Text(text)
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .fixedSize()
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(red: 0.2, green: 0.2, blue: 0.25))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                        .offset(y: (position == .top ? -8 : 43) + verticalOffset)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        .zIndex(Double.greatestFiniteMagnitude)
                        .allowsHitTesting(false)
                        .compositingGroup()
                }
            }
            .compositingGroup()
            .onHover { hovering in
                hoverTask?.cancel()
                
                if hovering {
                    let task = Task {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        if !Task.isCancelled {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showTooltip = true
                            }
                        }
                    }
                    hoverTask = task
                } else {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        showTooltip = false
                    }
                }
            }
    }
}

extension View {
    func tooltip(_ text: String, delay: TimeInterval = 0.5, position: TooltipModifier.TooltipPosition = .top, verticalOffset: CGFloat = 0) -> some View {
        modifier(TooltipModifier(text: text, delay: delay, position: position, verticalOffset: verticalOffset))
    }
}

