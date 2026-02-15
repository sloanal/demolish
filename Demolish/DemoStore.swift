//
//  DemoStore.swift
//  Demolish
//
//  Persisted demo layouts for pane configurations
//

import SwiftUI
import Combine

struct DemoFrame: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    
    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    
    init(rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.size.width
        self.height = rect.size.height
    }
    
    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct DemoPaneSnapshot: Codable, Equatable {
    var title: String
    var showBorder: Bool
    var borderColorIndex: Int
    var zoomSetting: ZoomSetting
    var displayNumber: Int
    var url: String
    var frame: DemoFrame
}

struct DemoLayout: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var displayConfiguration: DisplayConfiguration
    var panes: [DemoPaneSnapshot]
    var createdAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        displayConfiguration: DisplayConfiguration,
        panes: [DemoPaneSnapshot],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.displayConfiguration = displayConfiguration
        self.panes = panes
        self.createdAt = createdAt
    }
}

final class DemoStore: ObservableObject {
    @Published private(set) var demos: [DemoLayout] = []
    
    private let storageKey = "savedDemoLayouts"
    
    init() {
        load()
    }
    
    func save(name: String, displayConfiguration: DisplayConfiguration, panes: [DemoPaneSnapshot]) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        if let index = demos.firstIndex(where: { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }) {
            let existing = demos[index]
            let updated = DemoLayout(
                id: existing.id,
                name: trimmedName,
                displayConfiguration: displayConfiguration,
                panes: panes,
                createdAt: existing.createdAt
            )
            demos.remove(at: index)
            demos.insert(updated, at: 0)
        } else {
            let demo = DemoLayout(
                name: trimmedName,
                displayConfiguration: displayConfiguration,
                panes: panes
            )
            demos.insert(demo, at: 0)
        }
        
        persist()
    }
    
    func remove(id: UUID) {
        demos.removeAll { $0.id == id }
        persist()
    }
    
    private func persist() {
        guard let data = try? JSONEncoder().encode(demos) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([DemoLayout].self, from: data) else {
            demos = []
            return
        }
        demos = saved
    }
}
