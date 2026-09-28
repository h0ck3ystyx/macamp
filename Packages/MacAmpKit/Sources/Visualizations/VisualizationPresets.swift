import Contracts
import Foundation

public enum BuiltInVisualizationEffect: String, Codable, CaseIterable, Sendable {
    case classicBars = "classic-bars"
    case stereoScope = "stereo-scope"
    case orbit
    case phosphor
    case tunnel
    case aurora
}

public struct VisualizationPresetDescriptor: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var author: String
    public var effect: BuiltInVisualizationEffect

    public init(id: String, name: String, author: String = "MacAmp", effect: BuiltInVisualizationEffect) {
        self.id = id; self.name = name; self.author = author; self.effect = effect
    }
}

public enum BuiltInVisualizationCatalog {
    public static let presets: [VisualizationPresetDescriptor] = [
        .init(id: "builtin.classic-bars", name: "Classic Bars", effect: .classicBars),
        .init(id: "builtin.stereo-scope", name: "Stereo Scope", effect: .stereoScope),
        .init(id: "builtin.orbit", name: "Orbit", effect: .orbit),
        .init(id: "builtin.phosphor", name: "Phosphor", effect: .phosphor),
        .init(id: "builtin.tunnel", name: "Tunnel", effect: .tunnel),
        .init(id: "builtin.aurora", name: "Aurora", effect: .aurora),
    ]

    public static func preset(id: String) -> VisualizationPresetDescriptor? { presets.first { $0.id == id } }
}
