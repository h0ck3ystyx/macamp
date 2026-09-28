import Accelerate
import Contracts
import Foundation

public enum VisualizationAnalysisError: Error, Equatable, Sendable {
    case unsupportedChannelCount(Int)
    case invalidSampleRate(Double)
    case insufficientFrames(required: Int, supplied: Int)
    case malformedPCM
    case unavailableFFT
}

/// Serialized DSP state for the V0 visualization path. The audio render callback
/// must only copy into the bounded bridge; this analyzer runs on its consumer.
public final class VisualizationAnalyzer: @unchecked Sendable {
    public static let fftSize = 2_048
    public static let bandCount = 32
    public static let waveformPointCount = 512

    private let fftSetup: vDSP_DFT_Setup
    private let window: [Float]
    private var previousPower = [Float](repeating: 0, count: fftSize / 2)
    private var smoothedBroad: (Float, Float, Float) = (0, 0, 0)
    private var lastSequence: UInt64?
    private var lastEpoch: UInt64?

    public init() throws {
        guard let setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(Self.fftSize), vDSP_DFT_Direction.FORWARD) else {
            throw VisualizationAnalysisError.unavailableFFT
        }
        fftSetup = setup
        window = (0..<Self.fftSize).map { index in
            0.5 - 0.5 * cos(2 * .pi * Float(index) / Float(Self.fftSize - 1))
        }
    }

    deinit { vDSP_DFT_DestroySetup(fftSetup) }

    public func reset() {
        previousPower = [Float](repeating: 0, count: Self.fftSize / 2)
        smoothedBroad = (0, 0, 0)
        lastSequence = nil
        lastEpoch = nil
    }

    public func analyze(header: VisualizationPCMHeader, interleavedSamples: [Float]) throws -> VisualizationFeatures {
        guard header.sampleRate.isFinite, header.sampleRate > 0 else { throw VisualizationAnalysisError.invalidSampleRate(header.sampleRate) }
        guard (1...2).contains(header.channelCount) else { throw VisualizationAnalysisError.unsupportedChannelCount(header.channelCount) }
        guard header.frameCount >= Self.fftSize else {
            throw VisualizationAnalysisError.insufficientFrames(required: Self.fftSize, supplied: header.frameCount)
        }
        guard interleavedSamples.count >= header.frameCount * header.channelCount else { throw VisualizationAnalysisError.malformedPCM }

        if lastEpoch != header.epoch || lastSequence.map({ header.sequence != $0 + 1 }) == true { reset() }
        lastEpoch = header.epoch
        lastSequence = header.sequence

        let start = header.frameCount - Self.fftSize
        var left = [Float](repeating: 0, count: Self.fftSize)
        var right = [Float](repeating: 0, count: Self.fftSize)
        for frame in 0..<Self.fftSize {
            let source = (start + frame) * header.channelCount
            left[frame] = finite(interleavedSamples[source])
            right[frame] = header.channelCount == 1 ? left[frame] : finite(interleavedSamples[source + 1])
        }

        let leftMetrics = levelMetrics(left)
        let rightMetrics = levelMetrics(right)
        let leftPower = spectralPower(left)
        let rightPower = spectralPower(right)
        let power = zip(leftPower, rightPower).map { max(0, ($0 + $1) * 0.5) }
        let bandDB = logarithmicBands(power: power, sampleRate: header.sampleRate)
        let normalized = bandDB.map { min(1, max(0, ($0 + 72) / 72)) }
        let broad = (
            normalizedEnergy(power, sampleRate: header.sampleRate, lower: 30, upper: 250),
            normalizedEnergy(power, sampleRate: header.sampleRate, lower: 250, upper: 4_000),
            normalizedEnergy(power, sampleRate: header.sampleRate, lower: 4_000, upper: 16_000)
        )
        let hopSeconds = 512.0 / header.sampleRate
        let smoothing = Float(1 - exp(-hopSeconds / 0.3))
        smoothedBroad = (
            smoothedBroad.0 + smoothing * (broad.0 - smoothedBroad.0),
            smoothedBroad.1 + smoothing * (broad.1 - smoothedBroad.1),
            smoothedBroad.2 + smoothing * (broad.2 - smoothedBroad.2)
        )
        let rmsGate = max(leftMetrics.rmsDB, rightMetrics.rmsDB) > -60
        let flux = zip(power, previousPower).reduce(Float.zero) { $0 + max(0, $1.0 - $1.1) }
        let baseline = max(Float.leastNonzeroMagnitude, previousPower.reduce(0, +))
        let onset = rmsGate ? min(1, flux / baseline) : 0
        previousPower = power

        return VisualizationFeatures(
            sequence: header.sequence, epoch: header.epoch, sampleTime: header.sampleTime, hostTime: header.hostTime, sampleRate: header.sampleRate,
            leftWaveform: reducedWaveform(left), rightWaveform: reducedWaveform(right), spectrum: normalized, spectrumDBFS: bandDB,
            channelRMSDBFS: [leftMetrics.rmsDB, rightMetrics.rmsDB], channelPeakDBFS: [leftMetrics.peakDB, rightMetrics.peakDB],
            bassEnergy: broad.0, midEnergy: broad.1, trebleEnergy: broad.2,
            smoothedBassEnergy: smoothedBroad.0, smoothedMidEnergy: smoothedBroad.1, smoothedTrebleEnergy: smoothedBroad.2,
            onsetStrength: onset
        )
    }

    private func spectralPower(_ samples: [Float]) -> [Float] {
        var inputReal = zip(samples, window).map(*)
        var inputImag = [Float](repeating: 0, count: Self.fftSize)
        var outputReal = [Float](repeating: 0, count: Self.fftSize)
        var outputImag = [Float](repeating: 0, count: Self.fftSize)
        inputReal.withUnsafeMutableBufferPointer { ir in
            inputImag.withUnsafeMutableBufferPointer { ii in
                outputReal.withUnsafeMutableBufferPointer { or in
                    outputImag.withUnsafeMutableBufferPointer { oi in
                        vDSP_DFT_Execute(fftSetup, ir.baseAddress!, ii.baseAddress!, or.baseAddress!, oi.baseAddress!)
                    }
                }
            }
        }
        let scale = Float(2.0 / (Double(Self.fftSize) * 0.5))
        return (0..<(Self.fftSize / 2)).map { bin in
            let real = outputReal[bin] * scale
            let imag = outputImag[bin] * scale
            return real * real + imag * imag
        }
    }

    private func logarithmicBands(power: [Float], sampleRate: Double) -> [Float] {
        let upper = min(16_000, sampleRate / 2)
        return (0..<Self.bandCount).map { band in
            let lowerFrequency = 30 * pow(upper / 30, Double(band) / Double(Self.bandCount))
            let upperFrequency = 30 * pow(upper / 30, Double(band + 1) / Double(Self.bandCount))
            let lowerBin = max(1, Int(floor(lowerFrequency * Double(Self.fftSize) / sampleRate)))
            let upperBin = min(power.count - 1, max(lowerBin, Int(ceil(upperFrequency * Double(Self.fftSize) / sampleRate))))
            guard lowerBin <= upperBin else { return -72 }
            let mean = power[lowerBin...upperBin].reduce(0, +) / Float(upperBin - lowerBin + 1)
            return max(-72, min(0, 10 * log10(max(mean, 1e-12))))
        }
    }

    private func normalizedEnergy(_ power: [Float], sampleRate: Double, lower: Double, upper: Double) -> Float {
        let high = min(upper, sampleRate / 2)
        guard high > lower else { return 0 }
        let first = max(1, Int(floor(lower * Double(Self.fftSize) / sampleRate)))
        let last = min(power.count - 1, Int(ceil(high * Double(Self.fftSize) / sampleRate)))
        guard first <= last else { return 0 }
        let mean = power[first...last].reduce(0, +) / Float(last - first + 1)
        let db = max(-72, min(0, 10 * log10(max(mean, 1e-12))))
        return min(1, max(0, (db + 72) / 72))
    }

    private func levelMetrics(_ samples: [Float]) -> (rmsDB: Float, peakDB: Float) {
        var sum: Float = 0
        var peak: Float = 0
        for sample in samples { sum += sample * sample; peak = max(peak, abs(sample)) }
        let rms = sqrt(sum / Float(samples.count))
        return (max(-120, 20 * log10(max(rms, 1e-6))), max(-120, 20 * log10(max(peak, 1e-6))))
    }

    private func reducedWaveform(_ samples: [Float]) -> [Float] {
        let bucket = max(1, samples.count / Self.waveformPointCount)
        return (0..<Self.waveformPointCount).map { point in
            let start = point * bucket
            let end = min(samples.count, start + bucket)
            guard start < end else { return 0 }
            return samples[start..<end].max(by: { abs($0) < abs($1) }) ?? 0
        }
    }

    private func finite(_ sample: Float) -> Float { sample.isFinite ? min(1, max(-1, sample)) : 0 }
}

public actor VisualizationFeatureMailbox {
    private var value: VisualizationFeatures?
    public init() {}
    public func publish(_ features: VisualizationFeatures) { value = features }
    public func latest(after sequence: UInt64?) -> VisualizationFeatures? {
        guard let value, sequence == nil || value.sequence > sequence! else { return nil }
        return value
    }
    public func clear() { value = nil }
}
