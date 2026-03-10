//
//  OpusDecoder.swift
//  FlexAccess
//
//  Decodes Opus packets → 48 kHz mono float32 PCM (480 samples / 10 ms frame)
//  using AudioToolbox's kAudioFormatOpus converter (macOS 11+, iOS 15+).
//

import Foundation
import AudioToolbox

private struct OpusInputContext {
    var data: UnsafeRawPointer
    var size: Int
    var consumed: Bool = false
    var pktDesc = AudioStreamPacketDescription(mStartOffset: 0,
                                               mVariableFramesInPacket: 0,
                                               mDataByteSize: 0)
}

private func opusInputDataProc(
    _ converter: AudioConverterRef,
    _ ioNumPackets: UnsafeMutablePointer<UInt32>,
    _ ioData: UnsafeMutablePointer<AudioBufferList>,
    _ outPktDesc: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let ptr = userData else {
        ioNumPackets.pointee = 0
        return kAudioConverterErr_InvalidInputSize
    }
    let ctx = ptr.bindMemory(to: OpusInputContext.self, capacity: 1)
    if ctx.pointee.consumed {
        ioNumPackets.pointee = 0
        ioData.pointee.mNumberBuffers = 1
        ioData.pointee.mBuffers.mDataByteSize = 0
        ioData.pointee.mBuffers.mData = nil
        return noErr
    }
    ioData.pointee.mNumberBuffers = 1
    ioData.pointee.mBuffers.mDataByteSize = UInt32(ctx.pointee.size)
    ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(mutating: ctx.pointee.data)
    ioNumPackets.pointee = 1
    ctx.pointee.pktDesc.mDataByteSize = UInt32(ctx.pointee.size)
    withUnsafeMutablePointer(to: &ctx.pointee.pktDesc) { outPktDesc?.pointee = $0 }
    ctx.pointee.consumed = true
    return noErr
}

final class OpusDecoder {
    private let converter: AudioConverterRef

    init?() {
        var inFmt = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatOpus, mFormatFlags: 0,
            mBytesPerPacket: 0, mFramesPerPacket: 480, mBytesPerFrame: 0,
            mChannelsPerFrame: 1, mBitsPerChannel: 0, mReserved: 0)
        var outFmt = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        var conv: AudioConverterRef?
        let status = AudioConverterNew(&inFmt, &outFmt, &conv)
        guard status == noErr, let c = conv else {
            AppFileLogger.shared.log("OpusDecoder: AudioConverterNew failed \(status)")
            return nil
        }
        converter = c
        AppFileLogger.shared.log("OpusDecoder: ready")
    }

    deinit { AudioConverterDispose(converter) }

    func decode(bytes: UnsafePointer<UInt8>, count: Int) -> [Float]? {
        var ctx = OpusInputContext(data: UnsafeRawPointer(bytes), size: count)
        var numFrames: UInt32 = 480
        var output = [Float](repeating: 0, count: 480)
        let status: OSStatus = output.withUnsafeMutableBufferPointer { outBuf in
            var abl = AudioBufferList(mNumberBuffers: 1,
                mBuffers: AudioBuffer(mNumberChannels: 1,
                                      mDataByteSize: UInt32(480 * 4),
                                      mData: outBuf.baseAddress))
            return withUnsafeMutablePointer(to: &ctx) { ctxPtr in
                AudioConverterFillComplexBuffer(converter, opusInputDataProc,
                                                UnsafeMutableRawPointer(ctxPtr),
                                                &numFrames, &abl, nil)
            }
        }
        guard status == noErr, numFrames > 0 else { return nil }
        return Array(output.prefix(Int(numFrames)))
    }
}
