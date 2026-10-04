import XCTest
@testable import MAC_LIMPO

final class ScanTuningTests: XCTestCase {
    func testSolidStateUsesOneThreadPerCoreWithinWinDirStatRange() {
        XCTAssertEqual(ScanTuning.decide(isLocal: true, medium: .solidState, activeCores: 10).threads, 10)
        XCTAssertEqual(ScanTuning.decide(isLocal: true, medium: .solidState, activeCores: 2).threads, 4, "mínimo 4")
        XCTAssertEqual(ScanTuning.decide(isLocal: true, medium: .solidState, activeCores: 28).threads, 16, "máximo 16")
        XCTAssertEqual(ScanTuning.decide(isLocal: true, medium: .solidState, activeCores: 10).bufferSize, 4 * 1024 * 1024)
    }

    func testUnknownLocalMediumIsTreatedLikeSolidState() {
        XCTAssertEqual(ScanTuning.decide(isLocal: true, medium: .unknown, activeCores: 8).threads, 8)
    }

    func testRotationalDiskUsesTwoThreads() {
        XCTAssertEqual(ScanTuning.decide(isLocal: true, medium: .rotational, activeCores: 10).threads, 2)
    }

    func testNetworkVolumeUsesFourThreadsAndSmallBuffer() {
        let tuning = ScanTuning.decide(isLocal: false, medium: .unknown, activeCores: 10)
        XCTAssertEqual(tuning.threads, 4)
        XCTAssertEqual(tuning.bufferSize, 64 * 1024)
    }

    /// No disco interno de qualquer Mac atual o volume Data é local e SSD.
    func testInternalDataVolumeIsDetectedAsLocalSolidState() {
        var stats = statfs()
        XCTAssertEqual(statfs("/System/Volumes/Data", &stats), 0)
        let device = withUnsafeBytes(of: stats.f_mntfromname) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        XCTAssertEqual(ScanTuning.medium(ofBSDDevice: device), .solidState, "dispositivo \(device)")
        let tuning = ScanTuning.recommended(for: "/System/Volumes/Data")
        print("TUNING \(device): \(tuning.threads) threads, buffer \(tuning.bufferSize), cores \(ProcessInfo.processInfo.activeProcessorCount)")
        XCTAssertEqual(tuning.threads, min(16, max(4, ProcessInfo.processInfo.activeProcessorCount)))
    }
}
