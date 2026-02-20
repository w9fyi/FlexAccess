//
//  FlexProtocol.swift
//  FlexAccess
//
//  Static command builders for the SmartSDR TCP/IP API, and a parser for unsolicited
//  S-line status messages. All commands are plain ASCII strings sent via FlexConnection.send().
//

import Foundation

// MARK: - Operating modes

enum FlexMode: String, CaseIterable, Identifiable {
    case lsb   = "LSB"
    case usb   = "USB"
    case cw    = "CW"
    case cwl   = "CWL"
    case am    = "AM"
    case sam   = "SAM"
    case fm    = "FM"
    case nfm   = "NFM"
    case digu  = "DIGU"
    case digl  = "DIGL"
    case rtty  = "RTTY"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lsb:  return "LSB"
        case .usb:  return "USB"
        case .cw:   return "CW"
        case .cwl:  return "CW-R"
        case .am:   return "AM"
        case .sam:  return "SAM"
        case .fm:   return "FM"
        case .nfm:  return "FM-N"
        case .digu: return "DIGU"
        case .digl: return "DIGL"
        case .rtty: return "RTTY"
        }
    }
}

// MARK: - AGC modes

enum FlexAGCMode: String, CaseIterable, Identifiable {
    case off  = "off"
    case slow = "slow"
    case med  = "med"
    case fast = "fast"

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

// MARK: - EQ type

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
        case meter
        case panadapter
        case unknown
    }
    let kind: Kind
    let properties: [String: String]
}

// MARK: - FlexProtocol

enum FlexProtocol {

    // MARK: Subscriptions

    static func subSliceAll()   -> String { "sub slice all" }
    static func subRadio()      -> String { "sub radio" }
    static func subMeterList()  -> String { "sub meter list" }

    // MARK: Slice commands

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
    static func sliceList()             -> String { "slice list" }

    // MARK: PTT

    static func pttDown() -> String { "xmit 1" }
    static func pttUp()   -> String { "xmit 0" }

    // MARK: DSP (per-slice)

    static func setNR(index: Int, enabled: Bool)  -> String { sliceSet(index: index, key: "nr",  value: enabled ? "1" : "0") }
    static func setNB(index: Int, enabled: Bool)  -> String { sliceSet(index: index, key: "nb",  value: enabled ? "1" : "0") }
    static func setANF(index: Int, enabled: Bool) -> String { sliceSet(index: index, key: "anf", value: enabled ? "1" : "0") }
    static func setAGC(index: Int, mode: FlexAGCMode) -> String { sliceSet(index: index, key: "agc_mode", value: mode.rawValue) }
    static func setMode(index: Int, mode: FlexMode)   -> String { sliceSet(index: index, key: "mode",     value: mode.rawValue) }
    static func setFilter(index: Int, lo: Int, hi: Int) -> String {
        "slice set \(index) filter_lo=\(lo) filter_hi=\(hi)"
    }

    // MARK: DAX

    static func setDAX(index: Int, channel: Int) -> String { sliceSet(index: index, key: "dax", value: "\(channel)") }
    static func audioStreamCreate(daxChannel: Int) -> String { "audio stream create \(daxChannel)" }

    // MARK: Equalizer

    /// Enable or disable the specified EQ.
    static func eqMode(type: FlexEQType, enabled: Bool) -> String {
        "eq \(type.rawValue) mode=\(enabled ? 1 : 0)"
    }

    /// Set one EQ band. hz must be one of: 63, 125, 250, 500, 1000, 2000, 4000, 8000.
    /// value is −10…+10 dB (integer).
    static func eqBand(type: FlexEQType, hz: Int, value: Int) -> String {
        "eq \(type.rawValue) \(hz)Hz=\(value)"
    }

    /// Reset all 8 bands to 0.
    static func eqFlat(type: FlexEQType) -> String {
        "eq \(type.rawValue) 63Hz=0 125Hz=0 250Hz=0 500Hz=0 1000Hz=0 2000Hz=0 4000Hz=0 8000Hz=0"
    }

    // MARK: DAX TX (transmit audio from computer to radio)

    /// Enable or disable the DAX TX channel on a slice.
    /// Must be called before the radio will accept VITA-49 mic audio on UDP.
    static func setDAXTX(index: Int, enabled: Bool) -> String {
        sliceSet(index: index, key: "dax_tx", value: enabled ? "1" : "0")
    }

    // MARK: Radio

    static func clientUDPRegister(handle: String) -> String { "client udp_register handle=\(handle)" }
    static func clientIP()                         -> String { "client ip" }
    static func ping()                             -> String { "ping" }

    // MARK: Status line parser

    /// Parse an unsolicited S-line body (everything after S<handle>|).
    /// Returns a FlexStatusMessage with kind and a key→value dictionary.
    static func parseStatusLine(_ body: String) -> FlexStatusMessage {
        let tokens = body.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !tokens.isEmpty else {
            return FlexStatusMessage(kind: .unknown, properties: [:])
        }

        var props: [String: String] = [:]
        // tokens[0] is object type, tokens[1] may be index, rest are key=value
        let objectType = tokens[0].lowercased()

        var startIndex = 1
        var sliceIndex: Int? = nil

        switch objectType {

        case "slice":
            if tokens.count > 1, let idx = Int(tokens[1]) {
                sliceIndex = idx
                startIndex = 2
            }
            parseKV(from: tokens, startingAt: startIndex, into: &props)
            return FlexStatusMessage(kind: .slice(index: sliceIndex ?? 0), properties: props)

        case "eq":
            // eq rxsc mode=1 63hz=0 ...
            let eqTypeStr = tokens.count > 1 ? tokens[1].lowercased() : "rxsc"
            startIndex = 2
            let eqType: FlexEQType = eqTypeStr == "txsc" ? .tx : .rx
            parseKV(from: tokens, startingAt: startIndex, into: &props)
            return FlexStatusMessage(kind: .eq(type: eqType), properties: props)

        case "radio":
            parseKV(from: tokens, startingAt: startIndex, into: &props)
            return FlexStatusMessage(kind: .radio, properties: props)

        case "audio_stream", "dax_audio", "audio":
            // tokens[1] may be the hex stream ID (e.g. "0xC0000001"), not a key=value pair.
            if tokens.count > 1, tokens[1].hasPrefix("0x") || tokens[1].hasPrefix("0X") {
                props["_streamid"] = tokens[1]
                startIndex = 2
            }
            parseKV(from: tokens, startingAt: startIndex, into: &props)
            return FlexStatusMessage(kind: .audioStream, properties: props)

        case "meter":
            parseKV(from: tokens, startingAt: startIndex, into: &props)
            return FlexStatusMessage(kind: .meter, properties: props)

        case "panadapter", "waterfall":
            parseKV(from: tokens, startingAt: startIndex, into: &props)
            return FlexStatusMessage(kind: .panadapter, properties: props)

        default:
            parseKV(from: tokens, startingAt: 0, into: &props)
            return FlexStatusMessage(kind: .unknown, properties: props)
        }
    }

    // MARK: Private helpers

    private static func parseKV(from tokens: [String], startingAt start: Int, into props: inout [String: String]) {
        for token in tokens[start...] {
            let parts = token.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                props[String(parts[0]).lowercased()] = String(parts[1])
            }
        }
    }
}

// MARK: - EQ band frequencies

extension FlexProtocol {
    static let eqBandHz: [Int] = [63, 125, 250, 500, 1000, 2000, 4000, 8000]

    /// Parse all EQ band values from a status properties dict.
    /// Status keys are lowercase (63hz=, 125hz=, etc.).
    static func parseEQBands(from props: [String: String]) -> [Int: Int] {
        var bands: [Int: Int] = [:]
        for hz in eqBandHz {
            let key = "\(hz)hz"
            if let val = props[key], let v = Int(val) {
                bands[hz] = v
            }
        }
        return bands
    }
}
