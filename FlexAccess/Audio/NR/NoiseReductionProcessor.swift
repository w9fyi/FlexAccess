import Foundation

// MARK: - Protocol

protocol NoiseReductionProcessor: AnyObject {
    var isAvailable: Bool { get }
    var isEnabled: Bool { get set }
    func processFrame48kMonoInPlace(_ frame: inout [Float])
}

// MARK: - Passthrough

final class PassthroughNoiseReduction: NoiseReductionProcessor {
    var isAvailable: Bool { false }
    var isEnabled: Bool = false
    func processFrame48kMonoInPlace(_ frame: inout [Float]) {}
}

// MARK: - Proxy (swappable backend)

final class NoiseReductionProcessorProxy: NoiseReductionProcessor {
    var inner: any NoiseReductionProcessor

    init(inner: any NoiseReductionProcessor) { self.inner = inner }

    var isAvailable: Bool { inner.isAvailable }
    var isEnabled: Bool {
        get { inner.isEnabled }
        set { inner.isEnabled = newValue }
    }
    func processFrame48kMonoInPlace(_ frame: inout [Float]) {
        inner.processFrame48kMonoInPlace(&frame)
    }
}

// MARK: - NR pipeline (frames input samples, applies NR, calls completion)

final class NRPipeline {
    private let processor: any NoiseReductionProcessor
    private let frameSize: Int
    private var buffer: [Float] = []
    var wetDry: Float = 1.0

    init(processor: any NoiseReductionProcessor, frameSize: Int = 480) {
        self.processor = processor
        self.frameSize = frameSize
        buffer.reserveCapacity(frameSize * 4)
    }

    func reset() { buffer.removeAll(keepingCapacity: true) }

    func process(_ samples: [Float], onOutput: ([Float]) -> Void) {
        guard !samples.isEmpty else { return }
        buffer.append(contentsOf: samples)
        while buffer.count >= frameSize {
            var frame = Array(buffer.prefix(frameSize))
            buffer.removeFirst(frameSize)
            let dry = wetDry < 1 ? frame : []
            processor.processFrame48kMonoInPlace(&frame)
            if wetDry < 1 {
                let inv = 1 - wetDry
                for i in 0..<frameSize { frame[i] = dry[i] * inv + frame[i] * wetDry }
            }
            onOutput(frame)
        }
    }
}
