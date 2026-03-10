//
//  GoertzelTests.swift
//  FlexAccessTests
//
//  Tests for CWDecoder.goertzelEnergy().
//
//  Uses synthetic sine waves at frequencies chosen so that
//  k = N * f / Fs is exactly an integer (no spectral leakage).
//  With Fs = 48 000 Hz and N = 512:
//    f = 750 Hz  → k = 8  (exact)
//    f = 1500 Hz → k = 16 (exact)
//

import XCTest

final class GoertzelTests: XCTestCase {

    // MARK: Helpers

    /// Generate N samples of a pure sine wave: A * sin(2π * f * n / Fs)
    private func sine(freq: Double, sampleRate: Double = 48_000,
                      count: Int, amplitude: Float = 0.5) -> [Float] {
        (0..<count).map { n in
            amplitude * Float(sin(2.0 * .pi * freq * Double(n) / sampleRate))
        }
    }

    // MARK: Silence

    func testSilenceProducesZeroEnergy() {
        let silence = [Float](repeating: 0, count: 512)
        let energy = CWDecoder.goertzelEnergy(samples: silence,
                                              targetFreq: 750, sampleRate: 48_000)
        XCTAssertEqual(energy, 0.0, accuracy: 0.001)
    }

    // MARK: On-frequency detection

    func testOnFrequencyProducesHighEnergy() {
        // k = 8 exactly — no leakage; expected magnitude ≈ N * A / 2 = 128
        let signal = sine(freq: 750, count: 512)
        let energy = CWDecoder.goertzelEnergy(samples: signal,
                                              targetFreq: 750, sampleRate: 48_000)
        XCTAssertGreaterThan(energy, 100, "512-sample Goertzel at exact freq (A=0.5) should be ~128")
    }

    // MARK: Off-frequency rejection

    func testOffFrequencyProducesLowEnergy() {
        // Signal at 1500 Hz, detector tuned to 750 Hz
        // DFT orthogonality: energy at k=8 for a k=16 signal ≈ 0
        let offSignal  = sine(freq: 1500, count: 512)
        let offEnergy  = CWDecoder.goertzelEnergy(samples: offSignal,
                                                   targetFreq: 750, sampleRate: 48_000)

        let onSignal   = sine(freq: 750, count: 512)
        let onEnergy   = CWDecoder.goertzelEnergy(samples: onSignal,
                                                   targetFreq: 750, sampleRate: 48_000)

        XCTAssertGreaterThan(onEnergy, offEnergy * 10,
                             "On-frequency energy should be >> off-frequency energy")
    }

    // MARK: Frequency selectivity

    func testNeighbouringFrequencyRejected() {
        // Adjacent integer DFT bin (k=9 → 843.75 Hz) should be much weaker at the 750 Hz detector
        let nearFreq  = 9.0 * 48_000.0 / 512.0   // k=9 bin = 843.75 Hz
        let nearSignal = sine(freq: nearFreq, count: 512)
        let nearEnergy = CWDecoder.goertzelEnergy(samples: nearSignal,
                                                   targetFreq: 750, sampleRate: 48_000)
        let onSignal   = sine(freq: 750, count: 512)
        let onEnergy   = CWDecoder.goertzelEnergy(samples: onSignal,
                                                   targetFreq: 750, sampleRate: 48_000)
        XCTAssertGreaterThan(onEnergy, nearEnergy * 5,
                             "Adjacent bin should be substantially weaker")
    }

    // MARK: Amplitude proportionality

    func testEnergyScalesWithAmplitude() {
        // Goertzel magnitude is linear in amplitude: doubling A should double energy
        let low  = sine(freq: 750, count: 512, amplitude: 0.25)
        let high = sine(freq: 750, count: 512, amplitude: 0.50)
        let eLow  = CWDecoder.goertzelEnergy(samples: low,  targetFreq: 750, sampleRate: 48_000)
        let eHigh = CWDecoder.goertzelEnergy(samples: high, targetFreq: 750, sampleRate: 48_000)
        XCTAssertEqual(eHigh / eLow, 2.0, accuracy: 0.01,
                       "Energy should scale linearly with amplitude")
    }

    // MARK: Pitch independence

    func testDetectorTunedToDifferentPitch() {
        // Detector at 1500 Hz correctly identifies a 1500 Hz signal
        let signal = sine(freq: 1500, count: 512)
        let energy = CWDecoder.goertzelEnergy(samples: signal,
                                              targetFreq: 1500, sampleRate: 48_000)
        XCTAssertGreaterThan(energy, 100, "On-frequency detection should work at 1500 Hz too")
    }

    // MARK: Small block size

    func testSmallBlockStillWorks() {
        // 256 samples — still produces nonzero energy for on-frequency signal
        let signal = sine(freq: 750, count: 256)
        let energy = CWDecoder.goertzelEnergy(samples: signal,
                                              targetFreq: 750, sampleRate: 48_000)
        XCTAssertGreaterThan(energy, 0.0)
    }

    // MARK: Single sample

    func testSingleSampleIsHandled() {
        // Should not crash with 1 sample
        let result = CWDecoder.goertzelEnergy(samples: [1.0],
                                              targetFreq: 750, sampleRate: 48_000)
        XCTAssertFalse(result.isNaN)
        XCTAssertFalse(result.isInfinite)
    }

    // MARK: Empty samples

    func testEmptySamplesReturnsZero() {
        let result = CWDecoder.goertzelEnergy(samples: [],
                                              targetFreq: 750, sampleRate: 48_000)
        XCTAssertEqual(result, 0.0)
    }
}
