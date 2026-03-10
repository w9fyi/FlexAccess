//
//  FlexProtocol.swift
//  FlexAccess
//
//  Static command builders and status line parser for the SmartSDR TCP API.
//  Covers: slices, panadapters, DAX streams, PTT, DSP, EQ, meters, radio props.
//

import Foundation

// MARK: - Enumerations

enum FlexMode: String, CaseIterable, Identifiable, Codable {
    case lsb = "LSB", usb = "USB", cw = "CW", cwl = "CWL"
    case am = "AM", sam = "SAM", fm = "FM", nfm = "NFM"
    case digu = "DIGU", digl = "DIGL", rtty = "RTTY"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cwl: return "CW-R"
        case .nfm: return "FM-N"
        default:   return rawValue
        }
    }
}

enum FlexAGCMode: String, CaseIterable, Identifiable {
    case off = "off", slow = "slow", med = "med", fast = "fast"
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum FlexEQType: String {
    case rx = "rxsc"
    case tx = "txsc"
}

// MARK: - Parsed status message

struct FlexStatusMessage {
    enum Kind {
        case radio
        case slice(index: Int)
        case eq(type: FlexEQType)
        case audioStream
        case panadapter(id: String)
        case waterfall(id: String)
        case sliceList
        case meter
        case unknown
    }
    let kind: Kind
    let properties: [String: String]
}

// MARK: - FlexProtocol

enum FlexProtocol {

    // MARK: Client registration

    static func clientProgram(_ name: String) -> String { "client program \(name)" }
    static func clientUDPPort(_ port: UInt16)  -> String { "client udpport \(port)" }
    static func clientIP()                     -> String { "client ip" }
    static func ping()                         -> String { "ping" }

    // MARK: Subscriptions

    static func subRadio()        -> String { "sub radio all" }
    static func subSliceAll()     -> String { "sub slice all" }
    static func subMeterList()    -> String { "sub meter list" }
    static func subPanadapter()   -> String { "sub pan all" }
    static func subAudioStream()  -> String { "sub audio_stream all" }

    // MARK: Slice

    static func sliceList() -> String { "slice list" }

    static func sliceCreate(freqMHz: Double, ant: String = "ANT1", mode: FlexMode = .usb) -> String {
        String(format: "slice create freq=%.6f ant=%@ mode=%@", freqMHz, ant, mode.rawValue)
    }
    static func sliceTune(index: Int, freqMHz: Double) -> String {
        String(format: "slice t %d %.6f", index, freqMHz)
    }
    static func sliceSet(index: Int, key: String, value: String) -> String {
        "slice set \(index) \(key)=\(value)"
    }
    static func sliceRemove(index: Int) -> String { "slice r \(index)" }
    static func setMode(index: Int, mode: FlexMode)       -> String { sliceSet(index: index, key: "mode",     value: mode.rawValue) }
    static func setFilter(index: Int, lo: Int, hi: Int)   -> String { "slice set \(index) filter_lo=\(lo) filter_hi=\(hi)" }
    static func setNR(index: Int, enabled: Bool)          -> String { sliceSet(index: index, key: "nr",          value: enabled ? "1" : "0") }
    static func setNB(index: Int, enabled: Bool)          -> String { sliceSet(index: index, key: "nb",          value: enabled ? "1" : "0") }
    static func setANF(index: Int, enabled: Bool)         -> String { sliceSet(index: index, key: "anf",         value: enabled ? "1" : "0") }
    static func setAGC(index: Int, mode: FlexAGCMode)     -> String { sliceSet(index: index, key: "agc_mode",    value: mode.rawValue) }
    static func setAGCThreshold(index: Int, level: Int)   -> String { sliceSet(index: index, key: "agc_threshold", value: "\(level)") }
    static func setRFGain(index: Int, db: Int)            -> String { sliceSet(index: index, key: "rfgain",      value: "\(db)") }
    static func setAudioLevel(index: Int, level: Int)     -> String { sliceSet(index: index, key: "audio_level", value: "\(level)") }
    static func setRxAnt(index: Int, ant: String)         -> String { sliceSet(index: index, key: "rxant",       value: ant) }
    static func setTxAnt(ant: String)                     -> String { "transmit set tx_ant=\(ant)" }
    static func setDAX(index: Int, channel: Int)          -> String { sliceSet(index: index, key: "dax",         value: "\(channel)") }
    static func setDAXTX(index: Int, enabled: Bool)       -> String { sliceSet(index: index, key: "dax_tx",      value: enabled ? "1" : "0") }

    // MARK: Slice — RIT / XIT

    static func setRIT(index: Int, enabled: Bool)         -> String { sliceSet(index: index, key: "rit_on",      value: enabled ? "1" : "0") }
    static func setRITOffset(index: Int, hz: Int)         -> String { sliceSet(index: index, key: "rit_freq",    value: "\(hz)") }
    static func setXIT(index: Int, enabled: Bool)         -> String { sliceSet(index: index, key: "xit_on",      value: enabled ? "1" : "0") }
    static func setXITOffset(index: Int, hz: Int)         -> String { sliceSet(index: index, key: "xit_freq",    value: "\(hz)") }

    // MARK: Slice — Squelch

    static func setSquelch(index: Int, enabled: Bool)     -> String { sliceSet(index: index, key: "squelch",       value: enabled ? "1" : "0") }
    static func setSquelchLevel(index: Int, level: Int)   -> String { sliceSet(index: index, key: "squelch_level", value: "\(level)") }

    // MARK: Slice — APF (Audio Peaking Filter)

    static func setAPF(index: Int, enabled: Bool)         -> String { sliceSet(index: index, key: "apf_on",      value: enabled ? "1" : "0") }
    static func setAPFQFactor(index: Int, q: Int)         -> String { sliceSet(index: index, key: "apf_qfactor", value: "\(q)") }
    static func setAPFGain(index: Int, gain: Int)         -> String { sliceSet(index: index, key: "apf_gain",    value: "\(gain)") }

    // MARK: Slice — Tuning step

    /// Standard step sizes accepted by the SmartSDR API (Hz).
    static let stepValues: [Int] = [1, 10, 50, 100, 500, 1_000, 5_000, 10_000, 100_000]
    static func setStep(index: Int, hz: Int)              -> String { sliceSet(index: index, key: "step",        value: "\(hz)") }

    // MARK: PTT

    static func pttDown() -> String { "xmit 1" }
    static func pttUp()   -> String { "xmit 0" }

    // MARK: CW Keyer

    static let cwSpeedRange:    ClosedRange<Int> = 5...60
    static let cwSidetoneRange: ClosedRange<Int> = 0...100
    static let cwPitchRange:    ClosedRange<Int> = 300...1000

    static func cwSend(_ text: String)          -> String { "cw send \(text)" }
    static func cwAbort()                       -> String { "cw abort" }
    static func cwSpeed(_ wpm: Int)             -> String { "cw keyer_speed \(wpm)" }
    static func cwSidetoneLevel(_ level: Int)   -> String { "cw sidetone_level \(level)" }
    static func cwSidetoneFrequency(_ hz: Int)  -> String { "cw sidetone_frequency \(hz)" }

    // MARK: DAX streams (firmware 3.x+)

    static func streamCreateDAXRX(daxChannel: Int, port: UInt16? = nil) -> String {
        if let port { return "stream create type=dax_rx dax_channel=\(daxChannel) port=\(port)" }
        return "stream create type=dax_rx dax_channel=\(daxChannel)"
    }
    static func streamCreateDAXTX()          -> String { "stream create type=dax_tx" }
    static func streamRemove(streamID: String) -> String { "stream remove \(streamID)" }

    // MARK: Panadapter

    /// Create a new panadapter. The radio replies R<seq>|0|<pan_id>.
    static func panadapterCreate(freqMHz: Double, ant: String = "ANT1") -> String {
        String(format: "display pan create freq=%.6f ant=%@", freqMHz, ant)
    }
    static func panadapterRemove(id: String) -> String { "display pan remove \(id)" }
    static func panadapterSet(id: String, key: String, value: String) -> String {
        "display pan set \(id) \(key)=\(value)"
    }
    static func panadapterSetBandwidth(id: String, bwMHz: Double) -> String {
        String(format: "display pan set %@ bandwidth=%.6f", id, bwMHz)
    }
    static func panadapterSetCenter(id: String, freqMHz: Double) -> String {
        String(format: "display pan set %@ center=%.6f", id, freqMHz)
    }

    // MARK: Waterfall

    static func waterfallSet(id: String, key: String, value: String) -> String {
        "display waterfall set \(id) \(key)=\(value)"
    }
    static func waterfallSetAutoBlackLevel(id: String, enabled: Bool) -> String {
        waterfallSet(id: id, key: "auto_black", value: enabled ? "1" : "0")
    }

    // MARK: Equalizer

    static func eqMode(type: FlexEQType, enabled: Bool)   -> String { "eq \(type.rawValue) mode=\(enabled ? 1 : 0)" }
    static func eqBand(type: FlexEQType, hz: Int, value: Int) -> String { "eq \(type.rawValue) \(hz)Hz=\(value)" }
    static func eqFlat(type: FlexEQType) -> String {
        "eq \(type.rawValue) 63Hz=0 125Hz=0 250Hz=0 500Hz=0 1000Hz=0 2000Hz=0 4000Hz=0 8000Hz=0"
    }
    static let eqBandHz: [Int] = [63, 125, 250, 500, 1000, 2000, 4000, 8000]
    static func parseEQBands(from props: [String: String]) -> [Int: Int] {
        var bands: [Int: Int] = [:]
        for hz in eqBandHz {
            if let val = props["\(hz)hz"], let v = Int(val) { bands[hz] = v }
        }
        return bands
    }

    // MARK: Meter definitions

    struct MeterDefinition {
        let id: Int
        let name: String
        let source: String
        let unit: String
        let low: Double
        let high: Double
        let fps: Int
    }

    /// Parse a meter status line's properties dictionary into an array of meter definitions.
    /// Meter properties arrive as `"<id>.<field>": "<value>"` pairs (e.g., `"1.nam": "SIGNAL"`).
    static func parseMeters(from props: [String: String]) -> [MeterDefinition] {
        var byID: [Int: [String: String]] = [:]
        for (rawKey, val) in props {
            let parts = rawKey.split(separator: ".", maxSplits: 1)
            guard parts.count == 2, let id = Int(parts[0]) else { continue }
            byID[id, default: [:]][String(parts[1])] = val
        }
        return byID.keys.sorted().compactMap { id in
            guard let fields = byID[id], let name = fields["nam"] else { return nil }
            return MeterDefinition(
                id:     id,
                name:   name,
                source: fields["src"]  ?? "",
                unit:   fields["unit"] ?? "",
                low:    Double(fields["low"]  ?? "0") ?? 0,
                high:   Double(fields["high"] ?? "0") ?? 0,
                fps:    Int(fields["fps"] ?? "0") ?? 0
            )
        }
    }

    // MARK: WAN

    static func wanValidate(handle: String) -> String { "wan validate handle=\(handle)" }

    // MARK: Status line parser

    static func parseStatusLine(_ body: String) -> FlexStatusMessage {
        let tokens = body.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !tokens.isEmpty else { return FlexStatusMessage(kind: .unknown, properties: [:]) }

        var props: [String: String] = [:]
        let objectType = tokens[0].lowercased()

        switch objectType {

        case "slice":
            var startIndex = 1
            var sliceIndex = 0
            if tokens.count > 1, let idx = Int(tokens[1]) {
                sliceIndex = idx; startIndex = 2
            }
            parseKV(from: tokens, startingAt: startIndex, into: &props)
            return FlexStatusMessage(kind: .slice(index: sliceIndex), properties: props)

        case "slice_list":
            props["_raw"] = tokens.dropFirst().joined(separator: " ")
            return FlexStatusMessage(kind: .sliceList, properties: props)

        case "eq":
            let eqTypeStr = tokens.count > 1 ? tokens[1].lowercased() : "rxsc"
            let eqType: FlexEQType = eqTypeStr == "txsc" ? .tx : .rx
            parseKV(from: tokens, startingAt: 2, into: &props)
            return FlexStatusMessage(kind: .eq(type: eqType), properties: props)

        case "radio":
            parseKV(from: tokens, startingAt: 1, into: &props)
            return FlexStatusMessage(kind: .radio, properties: props)

        case "audio_stream", "dax_audio", "audio":
            var start = 1
            if tokens.count > 1, tokens[1].hasPrefix("0x") || tokens[1].hasPrefix("0X") {
                props["_streamid"] = tokens[1]; start = 2
            }
            parseKV(from: tokens, startingAt: start, into: &props)
            return FlexStatusMessage(kind: .audioStream, properties: props)

        case "panadapter", "pan":
            // "panadapter <hex_id> key=val ..."
            let panID = tokens.count > 1 ? tokens[1] : ""
            parseKV(from: tokens, startingAt: 2, into: &props)
            return FlexStatusMessage(kind: .panadapter(id: panID), properties: props)

        case "waterfall":
            let wfID = tokens.count > 1 ? tokens[1] : ""
            parseKV(from: tokens, startingAt: 2, into: &props)
            return FlexStatusMessage(kind: .waterfall(id: wfID), properties: props)

        case "meter":
            parseKV(from: tokens, startingAt: 1, into: &props)
            return FlexStatusMessage(kind: .meter, properties: props)

        default:
            parseKV(from: tokens, startingAt: 0, into: &props)
            return FlexStatusMessage(kind: .unknown, properties: props)
        }
    }

    private static func parseKV(from tokens: [String], startingAt start: Int, into props: inout [String: String]) {
        guard start < tokens.count else { return }
        for token in tokens[start...] {
            let parts = token.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                props[String(parts[0]).lowercased()] = String(parts[1])
            }
        }
    }
}
