//
//  CWDecoder.swift
//  FlexAccess
//
//  Goertzel-based CW (Morse code) decoder.
//  Processes 48 kHz mono Float samples block by block,
//  tracks mark/space timing, and emits decoded characters.
//

import Foundation

@Observable
@MainActor
final class CWDecoder {

    // MARK: - Public state

    var decodedText: String = ""
    var isActive:    Bool   = false

    /// Called on MainActor each time a character or space is decoded.
    var onCharacter: ((String) -> Void)?

    // MARK: - Configuration

    var targetFreq: Double = 750     // Hz — should match sidetone frequency
    var sampleRate: Double = 48_000
    var wpm:        Int    = 20      // informs timing thresholds

    // MARK: - Static Goertzel

    /// Compute the Goertzel magnitude for `targetFreq` across `samples`.
    /// Returns 0.0 for empty input.
    nonisolated static func goertzelEnergy(samples: [Float],
                               targetFreq: Double,
                               sampleRate: Double) -> Float {
        let N = samples.count
        guard N > 0 else { return 0.0 }

        let k     = Double(N) * targetFreq / sampleRate
        let omega = 2.0 * Double.pi * k / Double(N)
        let coeff = Float(2.0 * cos(omega))

        var q1: Float = 0
        var q2: Float = 0

        for x in samples {
            let q0 = coeff * q1 - q2 + x
            q2 = q1
            q1 = q0
        }

        // |X[k]|² = q1² + q2² - q1·q2·coeff  (always ≥ 0)
        let mag2 = q1 * q1 + q2 * q2 - q1 * q2 * coeff
        return mag2 > 0 ? mag2.squareRoot() : 0.0
    }

    // MARK: - Block processing

    private let blockSize: Int = 256
    private var sampleBuffer: [Float] = []

    private var energyHistory: [Float] = []
    private let historyLength: Int = 20
    private var threshold:     Float  = 50.0

    private var markBlocks:     Int    = 0
    private var spaceBlocks:    Int    = 0
    private var currentMorse:   String = ""
    private var wordSpaceArmed: Bool   = false

    // MARK: - Audio tap entry point

    /// Feed raw 48 kHz mono Float samples (may be called from any thread).
    nonisolated func processSamples(_ samples: [Float]) {
        Task { @MainActor [weak self] in
            self?.enqueue(samples)
        }
    }

    private func enqueue(_ samples: [Float]) {
        sampleBuffer.append(contentsOf: samples)
        drainBlocks()
    }

    private func drainBlocks() {
        while sampleBuffer.count >= blockSize {
            let block = Array(sampleBuffer.prefix(blockSize))
            sampleBuffer.removeFirst(blockSize)
            processBlock(block)
        }
    }

    private func processBlock(_ block: [Float]) {
        guard isActive else { return }

        let energy = Self.goertzelEnergy(samples: block,
                                         targetFreq: targetFreq,
                                         sampleRate: sampleRate)

        energyHistory.append(energy)
        if energyHistory.count > historyLength { energyHistory.removeFirst() }
        let mean = energyHistory.reduce(0, +) / Float(energyHistory.count)
        threshold = Swift.max(10.0, mean * 0.5)

        let isMark = energy > threshold

        if isMark {
            if spaceBlocks > 0 { handleSpaceEnd(spaceBlocks) }
            spaceBlocks = 0
            markBlocks += 1
        } else {
            if markBlocks > 0 { handleMarkEnd(markBlocks) }
            markBlocks = 0
            spaceBlocks += 1

            if spaceBlocks == wordSpaceBlocks && !wordSpaceArmed {
                wordSpaceArmed = true
                if !currentMorse.isEmpty { emitChar() }
                appendDecoded(" ")
            }
        }
    }

    // MARK: - Timing

    private var blocksPerDit: Int {
        let ditMs          = 1200.0 / Double(Swift.max(1, wpm))
        let blockDurationMs = Double(blockSize) / sampleRate * 1000.0
        return Swift.max(1, Int((ditMs / blockDurationMs).rounded()))
    }

    private var wordSpaceBlocks: Int { blocksPerDit * 7 }

    private func handleMarkEnd(_ blocks: Int) {
        currentMorse  += blocks >= blocksPerDit * 2 ? "-" : "."
        wordSpaceArmed = false
    }

    private func handleSpaceEnd(_ blocks: Int) {
        guard blocks >= blocksPerDit * 3, !currentMorse.isEmpty else { return }
        emitChar()
    }

    private func emitChar() {
        guard !currentMorse.isEmpty else { return }
        let char = MorseTable.decode(currentMorse).map { String($0) } ?? "?"
        currentMorse = ""
        appendDecoded(char)
    }

    private func appendDecoded(_ s: String) {
        decodedText += s
        if decodedText.count > 500 {
            decodedText.removeFirst(decodedText.count - 500)
        }
        onCharacter?(s)
    }

    // MARK: - Control

    func start() { isActive = true; reset() }
    func stop()  { isActive = false; reset() }

    func reset() {
        sampleBuffer.removeAll()
        energyHistory.removeAll()
        markBlocks     = 0
        spaceBlocks    = 0
        currentMorse   = ""
        wordSpaceArmed = false
    }

    func clearText() { decodedText = "" }

    // Prevent isolated deinit crash on macOS 26 / Swift 6.1
    nonisolated deinit {}
}
