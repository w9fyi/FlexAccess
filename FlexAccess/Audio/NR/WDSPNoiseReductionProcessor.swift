import Foundation

enum WDSPMode { case emnr, anr }

final class WDSPNoiseReductionProcessor: NoiseReductionProcessor {
    private var emnrCtx: OpaquePointer?
    private var anrCtx:  OpaquePointer?
    private let mode: WDSPMode

    var isAvailable: Bool { emnrCtx != nil || anrCtx != nil }
    var isEnabled: Bool = false

    init?(mode: WDSPMode = .emnr, sampleRate: Int32 = 48000) {
        self.mode = mode
        switch mode {
        case .emnr:
            guard let ctx = wdsp_emnr_create(sampleRate) else {
                AppFileLogger.shared.log("WDSP EMNR: create failed")
                return nil
            }
            emnrCtx = ctx
        case .anr:
            guard let ctx = wdsp_anr_create(sampleRate) else {
                AppFileLogger.shared.log("WDSP ANR: create failed")
                return nil
            }
            anrCtx = ctx
        }
        AppFileLogger.shared.log("WDSP \(mode == .emnr ? "EMNR" : "ANR"): ready at \(sampleRate) Hz")
    }

    deinit {
        if let c = emnrCtx { wdsp_emnr_destroy(c) }
        if let c = anrCtx  { wdsp_anr_destroy(c) }
    }

    func processFrame48kMonoInPlace(_ frame: inout [Float]) {
        guard isEnabled else { return }
        frame.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            let n = Int32(buf.count)
            switch mode {
            case .emnr: if let c = emnrCtx { wdsp_emnr_process(c, base, n) }
            case .anr:  if let c = anrCtx  { wdsp_anr_process(c, base, n) }
            }
        }
    }
}
