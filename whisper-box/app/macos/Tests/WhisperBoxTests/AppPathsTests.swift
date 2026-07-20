import XCTest
@testable import WhisperBox

@MainActor
final class AppPathsTests: XCTestCase {
    private var base: URL!

    override func setUp() {
        super.setUp()
        base = FileManager.default.temporaryDirectory.appendingPathComponent("wbtest_\(UUID().uuidString)")
        AppPaths.setBase(base.path)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: base)
        AppPaths.setBase("")   // restore default
        super.tearDown()
    }

    func testRecordingDestinationSuffixesOnCollision() {
        let first = AppPaths.recordingDestination(for: "rec.wav")
        XCTAssertEqual(first.lastPathComponent, "rec.wav")
        FileManager.default.createFile(atPath: first.path, contents: Data())
        let second = AppPaths.recordingDestination(for: "rec.wav")
        XCTAssertEqual(second.lastPathComponent, "rec-1.wav")
    }

    func testIsInRecordingsDirTrueForOurFiles() {
        let inside = AppPaths.recordingsDir.appendingPathComponent("x.wav").path
        XCTAssertTrue(AppPaths.isInRecordingsDir(inside))
    }

    func testIsInRecordingsDirFalseForForeignRecordingsFolder() {
        // A user's own file that merely sits in some folder named "recordings".
        XCTAssertFalse(AppPaths.isInRecordingsDir("/tmp/music/recordings/band.wav"))
    }

    func testStagingDirIsLocalNotUnderConfiguredBase() {
        // Staging must never be the (possibly cloud-synced) output base.
        XCTAssertFalse(AppPaths.stagingDir.path.hasPrefix(base.path))
    }

    // MARK: - adoptStaging (crash recovery) — uses isolated temp dirs, not the real staging dir

    func testAdoptStagingMovesRealWavAndDropsJunk() throws {
        let fm = FileManager.default
        let staging = base.appendingPathComponent("staging")
        let out = base.appendingPathComponent("out")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        let realWav = staging.appendingPathComponent("good.wav")
        let emptyWav = staging.appendingPathComponent("empty.wav")
        let strayMp4 = staging.appendingPathComponent("frag.mp4")
        try Data(count: 5_000).write(to: realWav)          // >44 B → recoverable
        try Data(count: 44).write(to: emptyWav)            // header-only → drop
        try Data(count: 9_000).write(to: strayMp4)         // unfinalized video → drop

        AppPaths.adoptStaging(from: staging, into: out)

        XCTAssertTrue(fm.fileExists(atPath: out.appendingPathComponent("good.wav").path),
                      "non-empty WAV should be adopted into the output dir")
        XCTAssertFalse(fm.fileExists(atPath: realWav.path), "adopted WAV should leave staging")
        XCTAssertFalse(fm.fileExists(atPath: emptyWav.path), "empty WAV should be dropped")
        XCTAssertFalse(fm.fileExists(atPath: strayMp4.path), "non-wav should be dropped")
        XCTAssertFalse(fm.fileExists(atPath: out.appendingPathComponent("frag.mp4").path),
                       "non-wav must never be adopted")
    }
}
