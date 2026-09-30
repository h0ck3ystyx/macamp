import Contracts
import Testing
import Visualizations

@Test func builtInCatalogContainsSixDistinctOriginalEffects() {
    #expect(BuiltInVisualizationCatalog.presets.count == 6)
    #expect(Set(BuiltInVisualizationCatalog.presets.map(\.id)).count == 6)
    #expect(Set(BuiltInVisualizationCatalog.presets.map(\.effect)).count == 6)
    #expect(BuiltInVisualizationCatalog.preset(id: VisualizationSettings().presetID) != nil)
}
