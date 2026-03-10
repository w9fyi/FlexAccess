//
//  PanadapterTests.swift
//  FlexAccessTests
//
//  Tests for Panadapter.applyProperties and signal-analysis helpers.
//

import XCTest

@MainActor
final class PanadapterTests: XCTestCase {

    private func make(center: Double = 14.0, bw: Double = 0.200) -> Panadapter {
        let p = Panadapter(id: "0x40000000")
        p.centerMHz    = center
        p.bandwidthMHz = bw
        return p
    }

    // MARK: - applyProperties

    func testApplyCenter() {
        let p = make()
        p.applyProperties(["center": "7.125"])
        XCTAssertEqual(p.centerMHz, 7.125, accuracy: 1e-9)
    }

    func testApplyBandwidth() {
        let p = make()
        p.applyProperties(["bandwidth": "0.400"])
        XCTAssertEqual(p.bandwidthMHz, 0.400, accuracy: 1e-9)
    }

    func testApplyAntenna() {
        let p = make()
        p.applyProperties(["rxant": "ANT2"])
        XCTAssertEqual(p.antenna, "ANT2")
    }

    func testApplyAutoBlackEnabled() {
        let p = make(); p.autoBlackLevel = false
        p.applyProperties(["auto_black": "1"])
        XCTAssertTrue(p.autoBlackLevel)
    }

    func testApplyAutoBlackDisabled() {
        let p = make(); p.autoBlackLevel = true
        p.applyProperties(["auto_black": "0"])
        XCTAssertFalse(p.autoBlackLevel)
    }

    func testApplyBlackLevel() {
        let p = make()
        p.applyProperties(["black_level": "42"])
        XCTAssertEqual(p.blackLevel, 42)
    }

    func testApplyColorGain() {
        let p = make()
        p.applyProperties(["color_gain": "75"])
        XCTAssertEqual(p.colorGain, 75)
    }

    func testUnknownKeyIgnored() {
        let p = make()
        XCTAssertNoThrow(p.applyProperties(["unknown_key": "val"]))
        XCTAssertEqual(p.centerMHz, 14.0)
    }

    func testEmptyPropsIgnored() {
        let p = make()
        p.applyProperties([:])
        XCTAssertEqual(p.centerMHz, 14.0)
    }

    // MARK: - freqMHz(forBin:)

    func testFreqForSingleBinReturnsCenterMHz() {
        let p = make(center: 14.225, bw: 0.200)
        p.fftData = [-80]   // N = 1 → bin 0 fraction = 0.5/1 - 0.5 = 0 → centerMHz
        XCTAssertEqual(p.freqMHz(forBin: 0), 14.225, accuracy: 1e-9)
    }

    func testFreqForBinsSymmetricAroundCenter() {
        // N=4, center=14.0, bw=0.4: bin0 + bin3 should sum to 2 * center
        let p = make(center: 14.0, bw: 0.4)
        p.fftData = [Float](repeating: 0, count: 4)
        let f0 = p.freqMHz(forBin: 0)
        let f3 = p.freqMHz(forBin: 3)
        XCTAssertEqual(f0 + f3, 2 * 14.0, accuracy: 1e-9)
    }

    func testFreqIncreasesWithBinIndex() {
        let p = make(center: 14.0, bw: 0.200)
        p.fftData = [Float](repeating: 0, count: 8)
        for i in 1..<8 {
            XCTAssertGreaterThan(p.freqMHz(forBin: i), p.freqMHz(forBin: i - 1))
        }
    }

    func testFreqForEmptyDataReturnsCenterMHz() {
        let p = make(center: 14.225, bw: 0.200)
        // fftData is empty by default
        XCTAssertEqual(p.freqMHz(forBin: 0), 14.225, accuracy: 1e-9)
    }

    func testFreqSpanMatchesBandwidth() {
        // For N bins: span from first to last bin should be (N-1)/N * bandwidth
        let p = make(center: 14.0, bw: 0.200)
        let N = 10
        p.fftData = [Float](repeating: 0, count: N)
        let span = p.freqMHz(forBin: N - 1) - p.freqMHz(forBin: 0)
        let expected = Double(N - 1) / Double(N) * 0.200
        XCTAssertEqual(span, expected, accuracy: 1e-9)
    }

    // MARK: - peakBins()

    func testPeakBinsEmptyData() {
        let p = make()
        XCTAssertTrue(p.peakBins().isEmpty)
    }

    func testPeakBinsSingleBin() {
        let p = make()
        p.fftData = [-50]
        let peaks = p.peakBins()
        XCTAssertEqual(peaks.count, 1)
        XCTAssertEqual(peaks[0].levelDBm, -50, accuracy: 0.001)
    }

    func testPeakBinsTopNSortedDescending() {
        let p = make()
        p.fftData = [-80, -60, -70, -50, -90]
        let peaks = p.peakBins(count: 3)
        XCTAssertEqual(peaks.count, 3)
        XCTAssertEqual(peaks[0].levelDBm, -50, accuracy: 0.001)
        XCTAssertEqual(peaks[1].levelDBm, -60, accuracy: 0.001)
        XCTAssertEqual(peaks[2].levelDBm, -70, accuracy: 0.001)
    }

    func testPeakBinsCountCappedByDataSize() {
        let p = make()
        p.fftData = [-80, -60]
        XCTAssertEqual(p.peakBins(count: 10).count, 2)
    }

    func testPeakBinsDefaultCountFive() {
        let p = make()
        p.fftData = [Float](repeating: -80, count: 10)
        XCTAssertEqual(p.peakBins().count, 5)
    }

    func testPeakBinsFrequencyMatchesForBin() {
        // bin 1 is highest → its freq should match freqMHz(forBin: 1)
        let p = make(center: 14.0, bw: 0.200)
        p.fftData = [-80, -50]
        let peaks = p.peakBins(count: 1)
        XCTAssertEqual(peaks[0].freqMHz, p.freqMHz(forBin: 1), accuracy: 1e-9)
    }

    // MARK: - levelAtFrequency(_:)

    func testLevelEmptyDataReturnsNil() {
        let p = make()
        XCTAssertNil(p.levelAtFrequency(14.0))
    }

    func testLevelBelowRangeReturnsNil() {
        let p = make(center: 14.0, bw: 0.200)
        p.fftData = [-80, -60]
        XCTAssertNil(p.levelAtFrequency(13.0))
    }

    func testLevelAboveRangeReturnsNil() {
        let p = make(center: 14.0, bw: 0.200)
        p.fftData = [-80, -60]
        XCTAssertNil(p.levelAtFrequency(15.0))
    }

    func testLevelAtKnownBin() {
        // N=4, center=14.0, bw=0.200, half=0.100
        // bins: [-80, -60, -50, -70]
        // bin 3 → freq = center - half + (3.5/4)*bw = 13.9 + 0.175 = 14.075
        // levelAtFrequency(14.075): binF = (14.075-13.9)/0.2*4 - 0.5 = 3.0 → bin 3 = -70
        let p = make(center: 14.0, bw: 0.200)
        p.fftData = [-80, -60, -50, -70]
        let level = p.levelAtFrequency(14.075)
        XCTAssertNotNil(level)
        XCTAssertEqual(level!, -70, accuracy: 0.001)
    }

    func testLevelAtCenterBin() {
        // N=1, center=14.225 → single bin → any in-range freq returns it
        let p = make(center: 14.225, bw: 0.200)
        p.fftData = [-85]
        let level = p.levelAtFrequency(14.225)
        XCTAssertNotNil(level)
        XCTAssertEqual(level!, -85, accuracy: 0.001)
    }

    func testLevelAtEdgeDoesNotCrash() {
        let p = make(center: 14.0, bw: 0.200)
        p.fftData = [-80, -70]
        // Exact lower edge
        let lower = p.levelAtFrequency(14.0 - 0.100)
        XCTAssertNotNil(lower)
        // Exact upper edge
        let upper = p.levelAtFrequency(14.0 + 0.100)
        XCTAssertNotNil(upper)
    }
}
