import CVisualizationBridge
import Contracts
import Foundation

public final class VisualizationAnalysisPipeline: @unchecked Sendable {
    public let features: AsyncStream<VisualizationFeatures>
    private let continuation: AsyncStream<VisualizationFeatures>.Continuation
    private let bridge: OpaquePointer
    private let worker = DispatchQueue(label: "io.github.h0ck3ystyx.mioamp.visualization-analysis", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var epoch: UInt64 = 0

    public init() {
        let stream = AsyncStream.makeStream(of: VisualizationFeatures.self, bufferingPolicy: .bufferingNewest(2))
        features = stream.stream; continuation = stream.continuation
        bridge = VisualizationBridgeCreate()!
    }

    deinit {
        timer?.cancel(); continuation.finish(); VisualizationBridgeDestroy(bridge)
    }

    public func setActive(_ active: Bool) {
        VisualizationBridgeSetActive(bridge, active)
        worker.async { [weak self] in
            guard let self else { return }
            if active { self.startWorker() } else { self.stopWorker() }
        }
    }

    public func reset() {
        worker.async { [weak self] in
            guard let self else { return }
            self.epoch &+= 1
            VisualizationBridgeReset(self.bridge, self.epoch)
        }
    }

    /// Safe for the audio render callback: fixed copies and atomics only.
    public func push(left: UnsafePointer<Float>, right: UnsafePointer<Float>?, channels: Int, frames: Int,
                     sampleRate: Double, sampleTime: Int64, hostTime: UInt64) {
        _ = VisualizationBridgePush(bridge, left, right, UInt32(channels), UInt32(frames), sampleRate, sampleTime, hostTime)
    }

    public var droppedFrameCount: UInt64 { VisualizationBridgeDroppedCount(bridge) }

    private func startWorker() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: worker)
        source.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(3))
        let analyzer = try? VisualizationAnalyzer()
        var accumulated = [Float](); accumulated.reserveCapacity(8_192)
        var lastHeader: VisualizationPCMHeader?
        source.setEventHandler { [weak self] in
            guard let self, let analyzer else { return }
            var samples = [Float](repeating: 0, count: 4_096)
            var sequence: UInt64 = 0, epoch: UInt64 = 0, hostTime: UInt64 = 0
            var rate: Double = 0; var sampleTime: Int64 = 0; var channels: UInt32 = 0
            while true {
                let frames = VisualizationBridgePop(self.bridge, &samples, 2_048, &sequence, &epoch, &rate, &sampleTime, &hostTime, &channels)
                guard frames > 0 else { break }
                let count = Int(frames * channels)
                if lastHeader?.epoch != epoch || lastHeader?.channelCount != Int(channels) || lastHeader?.sampleRate != rate { accumulated.removeAll(keepingCapacity: true) }
                accumulated.append(contentsOf: samples.prefix(count))
                lastHeader = VisualizationPCMHeader(sequence: sequence, epoch: epoch, sampleTime: sampleTime, hostTime: hostTime == 0 ? nil : hostTime, sampleRate: rate, channelCount: Int(channels), frameCount: 0)
            }
            guard var header = lastHeader else { return }
            let needed = VisualizationAnalyzer.fftSize * header.channelCount
            guard accumulated.count >= needed else { return }
            if accumulated.count > needed { accumulated.removeFirst(accumulated.count - needed) }
            header.frameCount = VisualizationAnalyzer.fftSize
            if let result = try? analyzer.analyze(header: header, interleavedSamples: accumulated) { self.continuation.yield(result) }
        }
        timer = source; source.resume()
    }

    private func stopWorker() { timer?.cancel(); timer = nil }
}
