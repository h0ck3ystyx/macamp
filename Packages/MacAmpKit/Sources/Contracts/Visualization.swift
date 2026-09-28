import Foundation

public struct VisualizationPCMHeader: Equatable, Sendable {
    public var sequence: UInt64
    public var epoch: UInt64
    public var sampleTime: Int64
    public var hostTime: UInt64?
    public var sampleRate: Double
    public var channelCount: Int
    public var frameCount: Int

    public init(sequence: UInt64, epoch: UInt64, sampleTime: Int64, hostTime: UInt64? = nil, sampleRate: Double, channelCount: Int, frameCount: Int) {
        self.sequence = sequence
        self.epoch = epoch
        self.sampleTime = sampleTime
        self.hostTime = hostTime
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.frameCount = frameCount
    }
}

public struct VisualizationFeatures: Equatable, Sendable {
    public var sequence: UInt64
    public var epoch: UInt64
    public var sampleTime: Int64
    public var hostTime: UInt64?
    public var sampleRate: Double
    public var leftWaveform: [Float]
    public var rightWaveform: [Float]
    public var spectrum: [Float]
    public var spectrumDBFS: [Float]
    public var channelRMSDBFS: [Float]
    public var channelPeakDBFS: [Float]
    public var bassEnergy: Float
    public var midEnergy: Float
    public var trebleEnergy: Float
    public var smoothedBassEnergy: Float
    public var smoothedMidEnergy: Float
    public var smoothedTrebleEnergy: Float
    public var onsetStrength: Float
    public var isValid: Bool
    public var isStale: Bool

    public init(
        sequence: UInt64,
        epoch: UInt64,
        sampleTime: Int64,
        hostTime: UInt64? = nil,
        sampleRate: Double,
        leftWaveform: [Float],
        rightWaveform: [Float],
        spectrum: [Float],
        spectrumDBFS: [Float],
        channelRMSDBFS: [Float],
        channelPeakDBFS: [Float],
        bassEnergy: Float,
        midEnergy: Float,
        trebleEnergy: Float,
        smoothedBassEnergy: Float,
        smoothedMidEnergy: Float,
        smoothedTrebleEnergy: Float,
        onsetStrength: Float,
        isValid: Bool = true,
        isStale: Bool = false
    ) {
        self.sequence = sequence; self.epoch = epoch; self.sampleTime = sampleTime; self.hostTime = hostTime; self.sampleRate = sampleRate
        self.leftWaveform = leftWaveform; self.rightWaveform = rightWaveform
        self.spectrum = spectrum; self.spectrumDBFS = spectrumDBFS
        self.channelRMSDBFS = channelRMSDBFS; self.channelPeakDBFS = channelPeakDBFS
        self.bassEnergy = bassEnergy; self.midEnergy = midEnergy; self.trebleEnergy = trebleEnergy
        self.smoothedBassEnergy = smoothedBassEnergy; self.smoothedMidEnergy = smoothedMidEnergy; self.smoothedTrebleEnergy = smoothedTrebleEnergy
        self.onsetStrength = onsetStrength; self.isValid = isValid; self.isStale = isStale
    }
}

public enum MiniVisualizationMode: String, Codable, CaseIterable, Sendable { case spectrum, oscilloscope, off }
public enum VisualizationQuality: String, Codable, CaseIterable, Sendable { case low, balanced, high }
public enum VisualizationPresetFilter: String, Codable, CaseIterable, Sendable { case all, favorites }

public struct VisualizationSettings: Codable, Equatable, Sendable {
    public var miniMode: MiniVisualizationMode
    public var presetID: String
    public var favoritePresetIDs: Set<String>
    public var filter: VisualizationPresetFilter
    public var isCycling: Bool
    public var isLocked: Bool
    public var dwellSeconds: Double
    public var transitionSeconds: Double
    public var quality: VisualizationQuality
    public var sensitivity: Double
    public var reduceMotionSessionOverride: Bool

    public init(
        miniMode: MiniVisualizationMode = .spectrum,
        presetID: String = "builtin.classic-bars",
        favoritePresetIDs: Set<String> = [],
        filter: VisualizationPresetFilter = .all,
        isCycling: Bool = false,
        isLocked: Bool = false,
        dwellSeconds: Double = 30,
        transitionSeconds: Double = 2,
        quality: VisualizationQuality = .balanced,
        sensitivity: Double = 1,
        reduceMotionSessionOverride: Bool = false
    ) {
        self.miniMode = miniMode; self.presetID = presetID; self.favoritePresetIDs = favoritePresetIDs; self.filter = filter
        self.isCycling = isCycling; self.isLocked = isLocked; self.dwellSeconds = dwellSeconds; self.transitionSeconds = transitionSeconds
        self.quality = quality; self.sensitivity = sensitivity; self.reduceMotionSessionOverride = reduceMotionSessionOverride
    }
}

public enum VisualizationCommand: Equatable, Sendable {
    case show, hide
    case selectPreset(String), previousPreset, nextPreset
    case setFavorite(String, Bool), setLocked(Bool), setCycling(Bool)
    case setSensitivity(Double), setQuality(VisualizationQuality)
}

public struct VisualizationSurfaceSize: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }
}

public protocol VisualizationRenderer: Sendable {
    func prepare(presetID: String) async throws
    func resize(to size: VisualizationSurfaceSize) async
    func render(features: VisualizationFeatures, time: TimeInterval) async throws
    func reset(epoch: UInt64) async
    func suspend() async
    func release() async
}
