//
//  CWKeyer.swift
//  FlexAccess
//
//  Observable model for the CW keyboard keyer.
//  Holds speed, sidetone, macros, and send state.
//  The Radio object is responsible for wiring send/abort to TCP commands.
//

import Foundation

@Observable
@MainActor
final class CWKeyer {

    // MARK: - Keyer state

    var speed:           Int  = 20   // WPM (5–60)
    var sidetoneLevel:   Int  = 50   // 0–100
    var pitch:           Int  = 700  // Hz (300–1000)
    var isSending:       Bool = false

    // MARK: - Macros (user-configurable short strings)

    var macros: [String] = [
        "CQ CQ CQ DE AI5OS AI5OS K",
        "TU 73 DE AI5OS SK",
        "QRZ? DE AI5OS",
        "PSE QRS",
        "BK"
    ]

    // MARK: - Callbacks wired by Radio

    /// Send the given text string via CW.  Wired to `radio.cwSendText(_:)`.
    var onSend:  ((String) -> Void)?
    /// Abort the current transmission. Wired to `radio.cwAbort()`.
    var onAbort: (() -> Void)?

    // MARK: - Actions

    func send(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSending = true
        onSend?(text)
    }

    func abort() {
        isSending = false
        onAbort?()
    }

    func sendMacro(at index: Int) {
        guard macros.indices.contains(index) else { return }
        send(macros[index])
    }

    // MARK: - Clamped setters

    func setSpeed(_ wpm: Int) {
        speed = Swift.min(Swift.max(wpm, FlexProtocol.cwSpeedRange.lowerBound),
                         FlexProtocol.cwSpeedRange.upperBound)
    }

    func setSidetoneLevel(_ level: Int) {
        sidetoneLevel = Swift.min(Swift.max(level, FlexProtocol.cwSidetoneRange.lowerBound),
                                  FlexProtocol.cwSidetoneRange.upperBound)
    }

    func setPitch(_ hz: Int) {
        pitch = Swift.min(Swift.max(hz, FlexProtocol.cwPitchRange.lowerBound),
                         FlexProtocol.cwPitchRange.upperBound)
    }

    nonisolated deinit {}
}
