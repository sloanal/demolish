//
//  CursorHighlightManager.swift
//  Demolish
//
//  Manages cursor highlight settings and state
//

import SwiftUI
import Combine

enum CursorHighlightColor: String, CaseIterable {
    case yellow = "Yellow"
    case red = "Red"
    case blue = "Blue"
    
    var color: Color {
        switch self {
        case .yellow:
            return .yellow
        case .red:
            return .red
        case .blue:
            return .blue
        }
    }
}

class CursorHighlightManager: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "cursorHighlightEnabled")
        }
    }
    
    @Published var selectedColor: CursorHighlightColor {
        didSet {
            UserDefaults.standard.set(selectedColor.rawValue, forKey: "cursorHighlightColor")
        }
    }
    
    @Published var size: CGFloat {
        didSet {
            UserDefaults.standard.set(size, forKey: "cursorHighlightSize")
        }
    }
    
    @Published var hideCursor: Bool {
        didSet {
            UserDefaults.standard.set(hideCursor, forKey: "cursorHighlightHideCursor")
        }
    }
    
    private let enabledKey = "cursorHighlightEnabled"
    private let colorKey = "cursorHighlightColor"
    private let sizeKey = "cursorHighlightSize"
    private let hideCursorKey = "cursorHighlightHideCursor"
    
    init() {
        // Load saved settings or use defaults
        self.isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        
        if let savedColor = UserDefaults.standard.string(forKey: colorKey),
           let color = CursorHighlightColor(rawValue: savedColor) {
            self.selectedColor = color
        } else {
            self.selectedColor = .yellow
        }
        
        let savedSize = UserDefaults.standard.double(forKey: sizeKey)
        self.size = savedSize > 0 ? savedSize : 50.0 // Default size: 50
        
        self.hideCursor = UserDefaults.standard.bool(forKey: hideCursorKey)
    }
}

