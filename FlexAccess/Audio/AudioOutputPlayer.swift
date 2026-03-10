import Foundation
import AudioToolbox
import CoreAudio

final class AudioOutputPlayer {

    enum PlayerError: LocalizedError {
        case noDefaultOutput
        case audioUnitError(OSStatus, String)
        var errorDescription: String? {
            switch self {
            case .noDefaultOutput:              return "No default audio output device"
            case .audioUnitError(let s, let m): return "\(m) (OSStatus=\(s))"
            }
        }
    }

    var onLog:   ((String) -> Void)?
    var onError: ((String) -> Void)?
    var gain: Float = 1.0

    private let sampleRate: Double
    private let channels: UInt32 = 1
    private var unit: AudioUnit?
    private let fifo = AudioRingBuffer(capacitySamples: 48_000 * 4)

    init(sampleRate: Double = 48_000) { self.sampleRate = sampleRate }

    #if os(macOS)
    func start(outputDeviceID: AudioDeviceID? = nil) throws {
        stop()
        let devID: AudioDeviceID
        if let id = outputDeviceID { devID = id }
        else if let id = AudioDeviceManager.defaultOutputDeviceID() { devID = id }
        else { throw PlayerError.noDefaultOutput }
        try startUnit(try makeOutputUnit(deviceID: devID))
    }
    #else
    func start() throws {
        stop()
        try startUnit(try makeOutputUnit())
    }
    #endif

    private func startUnit(_ u: AudioUnit) throws {
        var status = AudioUnitInitialize(u)
        guard status == noErr else { throw PlayerError.audioUnitError(status, "AudioUnitInitialize") }
        status = AudioOutputUnitStart(u)
        guard status == noErr else { throw PlayerError.audioUnitError(status, "AudioOutputUnitStart") }
        unit = u
        fifo.clear()
        onLog?("Audio output started (\(Int(sampleRate)) Hz mono)")
    }

    func stop() {
        if let u = unit {
            AudioOutputUnitStop(u)
            AudioUnitUninitialize(u)
            AudioComponentInstanceDispose(u)
        }
        unit = nil
        fifo.clear()
    }

    func enqueue48kMono(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            _ = fifo.write(from: base, count: samples.count)
        }
    }

    #if os(macOS)
    private func makeOutputUnit(deviceID: AudioDeviceID) throws -> AudioUnit {
        let u = try makeBaseUnit(subType: kAudioUnitSubType_HALOutput)
        var dev = deviceID
        let status = AudioUnitSetProperty(u, kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global, 0,
                                          &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw PlayerError.audioUnitError(status, "Set device") }
        return try attachStreamFormatAndCallback(u)
    }
    #else
    private func makeOutputUnit() throws -> AudioUnit {
        let u = try makeBaseUnit(subType: kAudioUnitSubType_RemoteIO)
        return try attachStreamFormatAndCallback(u)
    }
    #endif

    private func makeBaseUnit(subType: OSType) throws -> AudioUnit {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: subType,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else {
            throw PlayerError.audioUnitError(-1, "AudioComponentFindNext failed")
        }
        var u: AudioUnit?
        var status = AudioComponentInstanceNew(comp, &u)
        guard status == noErr, let u else { throw PlayerError.audioUnitError(status, "AudioComponentInstanceNew") }

        var one: UInt32 = 1, zero: UInt32 = 0
        status = AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &one,  4)
        guard status == noErr else { throw PlayerError.audioUnitError(status, "EnableIO output") }
        status = AudioUnitSetProperty(u, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input,  1, &zero, 4)
        guard status == noErr else { throw PlayerError.audioUnitError(status, "Disable input") }
        return u
    }

    private func attachStreamFormatAndCallback(_ u: AudioUnit) throws -> AudioUnit {
        var asbd = makeASBD()
        var status = AudioUnitSetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                                          &asbd, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        guard status == noErr else { throw PlayerError.audioUnitError(status, "Set stream format") }

        var cb = AURenderCallbackStruct(
            inputProc: { refCon, _, _, _, inNumberFrames, ioData in
                let p = Unmanaged<AudioOutputPlayer>.fromOpaque(refCon).takeUnretainedValue()
                guard let ioData else { return noErr }
                let frames = Int(inNumberFrames)
                let bufs   = UnsafeMutableAudioBufferListPointer(ioData)
                guard let first = bufs.first,
                      first.mNumberChannels == 1,
                      let outPtr = first.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
                let got = p.fifo.read(into: outPtr, count: frames)
                if got < frames { outPtr.advanced(by: got).initialize(repeating: 0, count: frames - got) }
                if p.gain != 1 { for i in 0..<frames { outPtr[i] *= p.gain } }
                return noErr
            },
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
        status = AudioUnitSetProperty(u, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0,
                                      &cb, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        guard status == noErr else { throw PlayerError.audioUnitError(status, "Set render callback") }
        return u
    }

    private func makeASBD() -> AudioStreamBasicDescription {
        let bps = UInt32(MemoryLayout<Float>.size)
        return AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked,
            mBytesPerPacket: bps * channels, mFramesPerPacket: 1,
            mBytesPerFrame: bps * channels, mChannelsPerFrame: channels,
            mBitsPerChannel: 8 * bps, mReserved: 0)
    }
}
