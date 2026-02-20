//
//  OpusDecoder.swift
//  FlexAccess
//
//  Decodes Opus-encoded audio packets to 48 kHz mono float32 PCM using
//  AudioToolbox's kAudioFormatOpus AudioConverter (macOS 11+, iOS 15+).
//
//  Each call to decode() accepts one Opus packet (variable-length binary)
//  and returns 480 float32 samples at 48 kHz (10 ms frame).
//
//  The AudioConverter is stateful — keep one OpusDecoder alive for the
//  duration of a DAX session. Create a fresh one for each new session.
//

import Foundation
import AudioToolbox

// MARK: - Input callback context

/// Passed through the userData pointer into opusInputDataProc.
/// Must outlive the AudioConverterFillComplexBuffer call.
private struct OpusInputContext {
    var data: UnsafeRawPointer
    var size: Int
    var consumed: Bool = false
    /// Storage for the VBR packet description — kept here so its address
    /// is stable for the duration of the synchronous callback chain.
    var pktDesc: AudioStreamPacketDescription = .init(
        mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: 0
    )
}

// MARK: - C-compatible input data proc

/// AudioConverterComplexInputDataProc — non-capturing, usable as @convention(c).
/// The `outDataPacketDescription` parameter is a pointer-to-pointer; we point
/// it at the packet description stored inside OpusInputContext.
private func opusInputDataProc(
    _ converter: AudioConverterRef,
    _ ioNumPackets: UnsafeMutablePointer<UInt32>,
    _ ioData: UnsafeMutablePointer<AudioBufferList>,
    _ outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
    _ inUserData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let ptr = inUserData else {
        ioNumPackets.pointee = 0
        return kAudioConverterErr_InvalidInputSize
    }
    let ctx = ptr.bindMemory(to: OpusInputContext.self, capacity: 1)

    // Signal end-of-input on second call (converter asked for more than we have).
    if ctx.pointee.consumed {
        ioNumPackets.pointee = 0
        ioData.pointee.mNumberBuffers = 1
        ioData.pointee.mBuffers.mDataByteSize = 0
        ioData.pointee.mBuffers.mData = nil
        return noErr
    }

    // Provide the raw Opus packet bytes as the input buffer.
    ioData.pointee.mNumberBuffers = 1
    ioData.pointee.mBuffers.mDataByteSize = UInt32(ctx.pointee.size)
    ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: ctx.pointee.data)
    ioNumPackets.pointee = 1

    // Fill in the VBR packet description and point the caller's pointer at it.
    ctx.pointee.pktDesc.mStartOffset            = 0
    ctx.pointee.pktDesc.mVariableFramesInPacket = 0
    ctx.pointee.pktDesc.mDataByteSize           = UInt32(ctx.pointee.size)
    withUnsafeMutablePointer(to: &ctx.pointee.pktDesc) { pdPtr in
        outDataPacketDescription?.pointee = pdPtr
    }

    ctx.pointee.consumed = true
    return noErr
}

// MARK: - OpusDecoder

/// Stateful Opus → float32 PCM decoder. One instance per DAX session.
/// Returns nil from init() if the system doesn't support kAudioFormatOpus.
final class OpusDecoder {

    private let converter: AudioConverterRef

    init?() {
        // Opus input: 48 kHz mono VBR, 480 samples per 10 ms frame
        var inputFmt = AudioStreamBasicDescription(
            mSampleRate:       48_000,
            mFormatID:         kAudioFormatOpus,
            mFormatFlags:      0,
            mBytesPerPacket:   0,    // VBR — varies per packet
            mFramesPerPacket:  480,  // 10 ms at 48 kHz
            mBytesPerFrame:    0,
            mChannelsPerFrame: 1,
            mBitsPerChannel:   0,
            mReserved:         0
        )
        // float32 PCM output: native-endian, non-interleaved mono
        var outputFmt = AudioStreamBasicDescription(
            mSampleRate:       48_000,
            mFormatID:         kAudioFormatLinearPCM,
            mFormatFlags:      kAudioFormatFlagsNativeFloatPacked,
            mBytesPerPacket:   4,
            mFramesPerPacket:  1,
            mBytesPerFrame:    4,
            mChannelsPerFrame: 1,
            mBitsPerChannel:   32,
            mReserved:         0
        )

        var conv: AudioConverterRef?
        let status = AudioConverterNew(&inputFmt, &outputFmt, &conv)
        guard status == noErr, let c = conv else {
            AppFileLogger.shared.log("OpusDecoder: AudioConverterNew failed status=\(status)")
            return nil
        }
        converter = c
        AppFileLogger.shared.log("OpusDecoder: ready (kAudioFormatOpus → float32 48 kHz)")
    }

    deinit { AudioConverterDispose(converter) }

    // MARK: Decode

    /// Decode one Opus packet. Returns 480 float32 samples at 48 kHz, or nil on failure.
    func decode(bytes: UnsafePointer<UInt8>, count: Int) -> [Float]? {
        var ctx = OpusInputContext(
            data: UnsafeRawPointer(bytes),
            size: count,
            consumed: false
        )

        var numFrames: UInt32 = 480
        var output = [Float](repeating: 0, count: 480)

        // Use withUnsafeMutableBufferPointer so mData outlives the AudioBuffer init.
        let status: OSStatus = output.withUnsafeMutableBufferPointer { outBuf in
            var outputABL = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize:   UInt32(480 * MemoryLayout<Float>.size),
                    mData:           outBuf.baseAddress
                )
            )
            return withUnsafeMutablePointer(to: &ctx) { ctxPtr in
                AudioConverterFillComplexBuffer(
                    converter,
                    opusInputDataProc,
                    UnsafeMutableRawPointer(ctxPtr),
                    &numFrames,
                    &outputABL,
                    nil    // PCM output needs no packet descriptions
                )
            }
        }

        guard status == noErr, numFrames > 0 else { return nil }
        return Array(output.prefix(Int(numFrames)))
    }
}
