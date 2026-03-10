import Foundation

#if RNNOISE_C

final class RNNoiseProcessor: NoiseReductionProcessor {
    private var state: OpaquePointer?
    private let frameSize: Int
    private var inBuf: [Float]
    private var outBuf: [Float]

    var isAvailable: Bool { state != nil }
    var isEnabled: Bool = false

    init?() {
        let sz = Int(rnnoise_get_frame_size())
        guard sz > 0 else {
            AppFileLogger.shared.log("RNNoise: rnnoise_get_frame_size() = \(sz)")
            return nil
        }
        frameSize = sz
        inBuf  = Array(repeating: 0, count: sz)
        outBuf = Array(repeating: 0, count: sz)
        state  = rnnoise_create(nil)
        guard state != nil else {
            AppFileLogger.shared.log("RNNoise: rnnoise_create() returned nil")
            return nil
        }
        AppFileLogger.shared.log("RNNoise: ready, frameSize=\(frameSize)")
    }

    deinit { if let s = state { rnnoise_destroy(s) } }

    func processFrame48kMonoInPlace(_ frame: inout [Float]) {
        guard isEnabled, let state, frame.count == frameSize else { return }
        for i in 0..<frameSize { inBuf[i] = frame[i] * 32768.0 }
        inBuf.withUnsafeBufferPointer { inPtr in
            outBuf.withUnsafeMutableBufferPointer { outPtr in
                guard let i = inPtr.baseAddress, let o = outPtr.baseAddress else { return }
                _ = rnnoise_process_frame(state, o, i)
            }
        }
        for i in 0..<frameSize { frame[i] = outBuf[i] / 32768.0 }
    }
}

#else

final class RNNoiseProcessor: NoiseReductionProcessor {
    var isAvailable: Bool { false }
    var isEnabled: Bool = false
    init?() { return nil }
    func processFrame48kMonoInPlace(_ frame: inout [Float]) {}
}

#endif
