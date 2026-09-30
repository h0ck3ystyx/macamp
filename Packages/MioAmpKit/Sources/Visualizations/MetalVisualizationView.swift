@preconcurrency import AppKit
import Contracts
import MetalKit
import simd

public final class MetalVisualizationView: MTKView, MTKViewDelegate {
    private struct Vertex { var position: SIMD2<Float>; var color: SIMD4<Float> }
    private let queue: MTLCommandQueue?
    private let pipeline: MTLRenderPipelineState?
    private var latest: VisualizationFeatures?
    private var traces: [[Float]] = []
    private var previousPresetID: String?
    private var transitionStart: TimeInterval?
    public var transitionDuration: TimeInterval = 2
    public var isAnimationSuppressed = false
    public var presetID = "builtin.classic-bars" {
        didSet {
            guard presetID != oldValue else { return }
            previousPresetID = oldValue; transitionStart = ProcessInfo.processInfo.systemUptime
            traces.removeAll(); setNeedsDisplay(bounds)
        }
    }
    public var sensitivity: Float = 1 { didSet { setNeedsDisplay(bounds) } }
    public var openHandler: (() -> Void)?

    public init(frame: NSRect = .zero) {
        let metalDevice = MTLCreateSystemDefaultDevice()
        var commandQueue: MTLCommandQueue?
        var pipelineState: MTLRenderPipelineState?
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct V { float2 position; float4 color; };
        struct O { float4 position [[position]]; float4 color; };
        vertex O vertexMain(const device V *v [[buffer(0)]], uint i [[vertex_id]]) { O o; o.position=float4(v[i].position,0,1); o.color=v[i].color; return o; }
        fragment float4 fragmentMain(O in [[stage_in]]) { return in.color; }
        """
        if let metalDevice,
           let candidateQueue = metalDevice.makeCommandQueue(),
           let library = try? metalDevice.makeLibrary(source: source, options: nil),
           let vertex = library.makeFunction(name: "vertexMain"),
           let fragment = library.makeFunction(name: "fragmentMain") {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            if let candidatePipeline = try? metalDevice.makeRenderPipelineState(descriptor: descriptor) {
                commandQueue = candidateQueue
                pipelineState = candidatePipeline
            }
        }
        queue = commandQueue
        pipeline = pipelineState
        super.init(frame: frame, device: pipelineState == nil ? nil : metalDevice)
        colorPixelFormat = .bgra8Unorm; framebufferOnly = true; enableSetNeedsDisplay = true; isPaused = true
        clearColor = MTLClearColor(red: 0.015, green: 0.02, blue: 0.025, alpha: 1)
        setAccessibilityRole(.image)
        if pipelineState == nil {
            setAccessibilityLabel("Audio visualization unavailable")
            let fallback = NSTextField(labelWithString: "VISUALIZATION UNAVAILABLE")
            fallback.translatesAutoresizingMaskIntoConstraints = false
            fallback.textColor = .secondaryLabelColor
            fallback.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            addSubview(fallback)
            NSLayoutConstraint.activate([
                fallback.centerXAnchor.constraint(equalTo: centerXAnchor),
                fallback.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        } else {
            delegate = self
            setAccessibilityLabel("Audio visualization")
        }
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func update(features: VisualizationFeatures) {
        if isAnimationSuppressed, latest != nil { return }
        latest = features
        if presetID.hasSuffix("phosphor") {
            traces.append(features.leftWaveform)
            if traces.count > 12 { traces.removeFirst() }
        }
        setNeedsDisplay(bounds)
    }

    public func clearVisualization() { latest = nil; traces.removeAll(); setNeedsDisplay(bounds) }
    public override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { openHandler?() } else { super.mouseDown(with: event) }
    }
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let queue, let pipeline,
              let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let buffer = queue.makeCommandBuffer(), let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        if let features = latest {
            var groups: [Group]
            if let previousPresetID, let start = transitionStart, transitionDuration > 0 {
                let fraction = min(1, Float((ProcessInfo.processInfo.systemUptime - start) / transitionDuration))
                groups = faded(geometry(features, presetID: previousPresetID), alpha: 1 - fraction) + faded(geometry(features, presetID: presetID), alpha: fraction)
                if fraction >= 1 { self.previousPresetID = nil; transitionStart = nil }
            } else { groups = geometry(features, presetID: presetID) }
            for group in groups where !group.vertices.isEmpty {
                let byteCount = group.vertices.count * MemoryLayout<Vertex>.stride
                group.vertices.withUnsafeBytes { bytes in
                    if let vertexBuffer = device?.makeBuffer(bytes: bytes.baseAddress!, length: byteCount) {
                        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                        encoder.drawPrimitives(type: group.type, vertexStart: 0, vertexCount: group.vertices.count)
                    }
                }
            }
        }
        encoder.endEncoding(); buffer.present(drawable); buffer.commit()
    }

    private typealias Group = (type: MTLPrimitiveType, vertices: [Vertex])
    private func geometry(_ f: VisualizationFeatures, presetID id: String) -> [Group] {
        if id.hasSuffix("stereo-scope") { return scope(f) }
        if id.hasSuffix("orbit") { return orbit(f) }
        if id.hasSuffix("phosphor") { return phosphor(f) }
        if id.hasSuffix("tunnel") { return tunnel(f) }
        if id.hasSuffix("aurora") { return aurora(f) }
        return bars(f)
    }
    private func faded(_ groups: [Group], alpha: Float) -> [Group] {
        groups.map { group in (group.type, group.vertices.map { vertex in var copy = vertex; copy.color.w *= alpha; return copy }) }
    }

    private func bars(_ f: VisualizationFeatures) -> [Group] {
        var v: [Vertex] = []; let n = max(1, f.spectrum.count); let gap = 0.012
        for (i, raw) in f.spectrum.enumerated() {
            let x0 = -1 + 2 * Float(i) / Float(n) + Float(gap), x1 = -1 + 2 * Float(i + 1) / Float(n) - Float(gap)
            let y = -0.92 + min(1, raw * sensitivity) * 1.84
            let c = SIMD4<Float>(0.18 + raw * 0.8, 0.72, 0.22, 0.9)
            v += [Vertex(position:[x0,-0.92],color:c), Vertex(position:[x1,-0.92],color:c), Vertex(position:[x0,y],color:c), Vertex(position:[x0,y],color:c), Vertex(position:[x1,-0.92],color:c), Vertex(position:[x1,y],color:c)]
        }
        return [(.triangle, v)]
    }

    private func line(_ values: [Float], yScale: Float, yOffset: Float, color: SIMD4<Float>) -> Group {
        let count = max(values.count, 2)
        return (.lineStrip, values.enumerated().map { i, value in Vertex(position: [-1 + 2 * Float(i) / Float(count - 1), yOffset + value * yScale * sensitivity], color: color) })
    }
    private func scope(_ f: VisualizationFeatures) -> [Group] { [line(f.leftWaveform, yScale: 0.42, yOffset: 0.45, color: [0.2,0.95,0.65,0.95]), line(f.rightWaveform, yScale: 0.42, yOffset: -0.45, color: [1,0.45,0.18,0.95])] }
    private func orbit(_ f: VisualizationFeatures) -> [Group] {
        let n = f.leftWaveform.count; let pulse = 0.35 + f.smoothedBassEnergy * 0.28
        let vertices = (0...n).map { i -> Vertex in
            let index = i % max(1,n), a = Float(i) / Float(max(1,n)) * 2 * .pi
            let r = pulse + f.leftWaveform[index] * 0.16 * sensitivity
            return Vertex(position: [cos(a)*r, sin(a)*r], color: [0.55 + 0.4*sin(a),0.35 + f.midEnergy*0.55,1,0.92])
        }
        return [(.lineStrip, vertices)]
    }
    private func phosphor(_ f: VisualizationFeatures) -> [Group] {
        let source = traces.isEmpty ? [f.leftWaveform] : traces
        return source.enumerated().map { index, trace in
            let alpha = Float(index + 1) / Float(source.count) * 0.75
            return line(trace, yScale: 0.65, yOffset: 0, color: [0.25,1,0.35,alpha])
        }
    }
    private func tunnel(_ f: VisualizationFeatures) -> [Group] {
        (1...8).map { ring in
            let n = 64; let phase = f.midEnergy * Float(ring) * 0.5; let radius = Float(ring) / 9 * (0.72 + f.bassEnergy * 0.2)
            return (.lineStrip, (0...n).map { i in
                let a = Float(i)/Float(n)*2*Float.pi + phase
                return Vertex(position:[cos(a)*radius, sin(a)*radius], color:[0.22,0.45+Float(ring)/16,1,0.75])
            })
        }
    }
    private func aurora(_ f: VisualizationFeatures) -> [Group] {
        let bands: [(Float,Float,SIMD4<Float>)] = [(-0.42,f.bassEnergy,[0.2,0.85,0.75,0.72]),(0,f.midEnergy,[0.55,0.3,1,0.68]),(0.42,f.trebleEnergy,[1,0.35,0.65,0.65])]
        return bands.map { offset, energy, color in
            let values = f.leftWaveform.enumerated().map { i, value in value * 0.35 + sin(Float(i) * 0.045 + energy * 4) * energy * 0.3 }
            return line(values, yScale: 0.65, yOffset: offset, color: color)
        }
    }
}
