//
//  PaneFrameManager.swift
//  Demolish
//
//  Observable manager for pane frames
//

import SwiftUI
import Combine

class PaneFrameManager: ObservableObject {
    @Published var frames: [UUID: PaneFrame] = [:]
    
    func updateFrame(id: UUID, frame: CGRect) {
        if var paneFrame = frames[id] {
            paneFrame.frame = frame
            frames[id] = paneFrame
        }
    }
    
    func setFrame(id: UUID, frame: PaneFrame) {
        objectWillChange.send()
        frames[id] = frame
    }
    
    func setFrameImmediate(id: UUID, frame: PaneFrame) {
        // For drag operations - update immediately without animation delays
        frames[id] = frame
        objectWillChange.send()
    }
    
    func removeFrame(id: UUID) {
        frames.removeValue(forKey: id)
    }
}

