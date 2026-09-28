import AudioAnalysis
import Contracts
import Foundation
import Testing

@Test func silenceStaysAtTheDisplayFloor() throws {
    let analyzer = try VisualizationAnalyzer()
    let features = try analyzer.analyze(header: header(), interleavedSamples: stereo { _ in (0, 0) })
    #expect(features.spectrum.allSatisfy { $0 == 0 })
    #expect(features.channelRMSDBFS == [-120, -120])
    #expect(features.onsetStrength == 0)
}

@Test func oneKilohertzToneLandsInItsLogBand() throws {
    let analyzer = try VisualizationAnalyzer()
    let features = try analyzer.analyze(header: header(), interleavedSamples: stereo { frame in
        let sample = Float(sin(2 * Double.pi * 1_000 * Double(frame) / 48_000)) * 0.5
        return (sample, sample)
    })
    let peak = try #require(features.spectrum.indices.max(by: { features.spectrum[$0] < features.spectrum[$1] }))
    let lower = 30 * pow(16_000.0 / 30, Double(peak) / 32)
    let upper = 30 * pow(16_000.0 / 30, Double(peak + 1) / 32)
    #expect(lower <= 1_000 && upper >= 1_000)
}

@Test func antiphaseStereoDoesNotCancelSpectrum() throws {
    let analyzer = try VisualizationAnalyzer()
    let features = try analyzer.analyze(header: header(), interleavedSamples: stereo { frame in
        let sample = Float(sin(2 * Double.pi * 440 * Double(frame) / 48_000)) * 0.5
        return (sample, -sample)
    })
    #expect((features.spectrum.max() ?? 0) > 0.7)
}

@Test func halvingAmplitudeMeasuresApproximatelyMinusSixDB() throws {
    let analyzer = try VisualizationAnalyzer()
    let full = try analyzer.analyze(header: header(sequence: 1), interleavedSamples: stereo { frame in
        let sample = Float(sin(2 * Double.pi * 440 * Double(frame) / 48_000)) * 0.8
        return (sample, sample)
    })
    let half = try analyzer.analyze(header: header(sequence: 2), interleavedSamples: stereo { frame in
        let sample = Float(sin(2 * Double.pi * 440 * Double(frame) / 48_000)) * 0.4
        return (sample, sample)
    })
    #expect(abs((half.channelRMSDBFS[0] - full.channelRMSDBFS[0]) + 6.0206) < 0.1)
}

@Test func sequenceGapResetsOnsetHistory() throws {
    let analyzer = try VisualizationAnalyzer()
    _ = try analyzer.analyze(header: header(sequence: 1), interleavedSamples: stereo { _ in (0.8, 0.8) })
    let afterGap = try analyzer.analyze(header: header(sequence: 3), interleavedSamples: stereo { _ in (0, 0) })
    #expect(afterGap.onsetStrength == 0)
    #expect(afterGap.smoothedBassEnergy == 0)
}

private func header(sequence: UInt64 = 1) -> VisualizationPCMHeader {
    VisualizationPCMHeader(sequence: sequence, epoch: 1, sampleTime: 0, sampleRate: 48_000, channelCount: 2, frameCount: 2_048)
}

private func stereo(_ sample: (Int) -> (Float, Float)) -> [Float] {
    (0..<2_048).flatMap { frame in let pair = sample(frame); return [pair.0, pair.1] }
}
