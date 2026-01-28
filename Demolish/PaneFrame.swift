//
//  PaneFrame.swift
//  Demolish
//
//  Model for managing pane frame sizes and positions
//

import SwiftUI

struct PaneFrame: Identifiable, Equatable {
    let id: UUID
    var frame: CGRect
    
    init(id: UUID = UUID(), frame: CGRect) {
        self.id = id
        self.frame = frame
    }
    
    static func == (lhs: PaneFrame, rhs: PaneFrame) -> Bool {
        lhs.id == rhs.id && lhs.frame == rhs.frame
    }
    
    // Calculate 16:9 aspect ratio size based on available width
    static func initial16x9Size(in containerSize: CGSize, padding: CGFloat) -> CGSize {
        let availableWidth = containerSize.width - (padding * 2)
        let availableHeight = containerSize.height - (padding * 2)
        
        // Calculate width and height maintaining 16:9 ratio
        let width = min(availableWidth, availableHeight * 16 / 9)
        let height = width * 9 / 16
        
        return CGSize(width: width, height: height)
    }
}

