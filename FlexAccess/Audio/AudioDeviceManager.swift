#if os(macOS)
import Foundation
import CoreAudio

struct AudioDeviceInfo: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let nominalSampleRate: Double
    let inputChannelCount: UInt32
    let outputChannelCount: UInt32

    var displayName: String {
        "\(name) (\(Int(nominalSampleRate)) Hz)"
    }
}

enum AudioDeviceManager {

    static func inputDevices() -> [AudioDeviceInfo] {
        allDevices().compactMap { deviceInfo($0) }.filter { $0.inputChannelCount > 0 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func outputDevices() -> [AudioDeviceInfo] {
        allDevices().compactMap { deviceInfo($0) }.filter { $0.outputChannelCount > 0 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func defaultInputDeviceID() -> AudioDeviceID? { systemDevice(kAudioHardwarePropertyDefaultInputDevice) }
    static func defaultOutputDeviceID() -> AudioDeviceID? { systemDevice(kAudioHardwarePropertyDefaultOutputDevice) }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        allDevices().first { getStringProp($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    // MARK: Private

    private static func systemDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(mSelector: selector,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr && id != 0 ? id : nil
    }

    private static func allDevices() -> [AudioDeviceID] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = Array(repeating: AudioDeviceID(0), count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
        return ids
    }

    private static func deviceInfo(_ id: AudioDeviceID) -> AudioDeviceInfo? {
        guard let uid  = getStringProp(id, kAudioDevicePropertyDeviceUID),
              let name = getStringProp(id, kAudioObjectPropertyName) else { return nil }
        let rate      = getDoubleProp(id, kAudioDevicePropertyNominalSampleRate) ?? 0
        let inCh      = channelCount(id, scope: kAudioDevicePropertyScopeInput)
        let outCh     = channelCount(id, scope: kAudioDevicePropertyScopeOutput)
        return AudioDeviceInfo(id: id, uid: uid, name: name, nominalSampleRate: rate,
                               inputChannelCount: inCh, outputChannelCount: outCh)
    }

    private static func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> UInt32 {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                              mScope: scope,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr else { return 0 }
        let ptr = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { ptr.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(ptr.assumingMemoryBound(to: AudioBufferList.self))
            .reduce(0) { $0 + $1.mNumberChannels }
    }

    private static func getStringProp(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var unmanaged: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &unmanaged) == noErr,
              let u = unmanaged else { return nil }
        return u.takeUnretainedValue() as String
    }

    private static func getDoubleProp(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Double? {
        var addr = AudioObjectPropertyAddress(mSelector: selector,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var value: Double = 0
        var size = UInt32(MemoryLayout<Double>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }
}

#else

// iOS stub — CoreAudio HAL is macOS-only; no device enumeration on iOS.
import Foundation

struct AudioDeviceInfo: Identifiable, Hashable {
    let id: String
    let uid: String
    let name: String
    let nominalSampleRate: Double
    let inputChannelCount: UInt32
    let outputChannelCount: UInt32
    var displayName: String { "\(name) (\(Int(nominalSampleRate)) Hz)" }
}

enum AudioDeviceManager {
    static func inputDevices()  -> [AudioDeviceInfo] { [] }
    static func outputDevices() -> [AudioDeviceInfo] { [] }
    static func defaultInputDeviceID()  -> String? { nil }
    static func defaultOutputDeviceID() -> String? { nil }
    static func deviceID(forUID uid: String) -> String? { nil }
}

#endif
