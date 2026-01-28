//
//  PaneTransitionEffect.swift
//  Demolish
//
//  Custom geometry effect for smooth pane transitions with guaranteed translate and scale
//

import SwiftUI

struct PaneCarouselEffect: GeometryEffect {
    var position: CGPoint
    var scale: CGFloat
    var zIndex: Int
    var totalPanes: Int
    
    var animatableData: AnimatablePair<CGPoint.AnimatableData, CGFloat> {
        get {
            AnimatablePair(
                CGPoint.AnimatableData(position.x, position.y),
                scale
            )
        }
        set {
            position = CGPoint(x: newValue.first.first, y: newValue.first.second)
            scale = newValue.second
        }
    }
    
    func effectValue(size: CGSize) -> ProjectionTransform {
        // No rotation - all panes stay horizontal
        // This effect is kept for future extensibility but currently applies no transform
        // All positioning and scaling is handled by offset() and scaleEffect() modifiers
        return ProjectionTransform(.identity)
    }
}

