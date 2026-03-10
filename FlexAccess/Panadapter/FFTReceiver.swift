//
//  FFTReceiver.swift
//  FlexAccess
//
//  Processes VITA-49 Extension Data packets carrying panadapter FFT bins.
//
//  Integration:
//    The FlexRadio sends all UDP streams (DAX audio + panadapter FFT) to the
//    single port registered via `client udpport`. VITAReceiver handles audio
//    packets filtered by the DAX stream ID. Panadapter packets arrive on the
//    same port with stream IDs in the 0x40000000 range.
//
//    To receive FFT data, VITAReceiver's `onRawPacket` callback (added when
//    panadapter support is enabled) routes non-audio type-3 packets here.
//
//  FFT payload format (SmartSDR API):
//    Signed 16-bit big-endian integers, one per FFT bin.
//    Value units: dBm × 128  (divide by 128 to get dBm float).
//    Bin count varies by bandwidth setting (typically 512 or 1024).
//
//  One FFTReceiver instance per panadapter. Radio creates/removes them
//  in response to panadapter status lines.
//

import Foundation

final class FFTReceiver {

    // MARK: Configuration

    /// Hex stream ID of the panadapter this receiver handles, e.g. "0x40000000".
    let panID: String

    /// Panadapter model to update with new FFT data.
    weak var panadapter: Panadapter?

    // MARK: Init

    init(panID: String, panadapter: Panadapter) {
        self.panID       = panID
        self.panadapter  = panadapter
    }

    // MARK: Process

    /// Called by Radio when a VITA-49 packet arrives whose stream ID matches this panadapter.
    /// `payload` points to the packet payload (after VITA header); `count` is byte count.
    func process(payload bytes: UnsafePointer<UInt8>, count: Int) {
        guard count >= 2 else { return }
        let binCount = count / 2
        var bins = [Float](repeating: 0, count: binCount)
        for i in 0..<binCount {
            let hi   = Int16(bitPattern: UInt16(bytes[i * 2]) << 8 | UInt16(bytes[i * 2 + 1]))
            bins[i]  = Float(hi) / 128.0   // convert to dBm
        }
        Task { @MainActor [weak self] in
            self?.panadapter?.fftData = bins
        }
    }

    // MARK: Stream ID helper

    /// Returns the UInt32 stream ID parsed from `panID`, or nil if unparseable.
    var streamID: UInt32? {
        let hex = panID.hasPrefix("0x") || panID.hasPrefix("0X") ? String(panID.dropFirst(2)) : panID
        return UInt32(hex, radix: 16)
    }
}
