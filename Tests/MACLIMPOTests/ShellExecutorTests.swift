import XCTest
@testable import MAC_LIMPO

final class ShellExecutorTests: XCTestCase {
    private let shell = ShellExecutor.shared

    func testBasicOutputAndExitCode() {
        let r = shell.execute("echo hello")
        XCTAssertEqual(r.output.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
        XCTAssertEqual(r.exitCode, 0)
    }

    func testNonZeroExitCodeIsPropagated() {
        let r = shell.execute("exit 3")
        XCTAssertEqual(r.exitCode, 3)
    }

    /// Regressão do deadlock: saída > 64KB (buffer do pipe) não pode travar.
    func testLargeOutputDoesNotDeadlock() {
        let r = shell.execute("head -c 300000 /dev/zero | base64", timeout: 30)
        XCTAssertEqual(r.exitCode, 0)
        XCTAssertGreaterThan(r.output.count, 300_000, "saída grande deve ser lida por completo")
    }

    func testTimeoutTerminatesAndReports() {
        let r = shell.execute("sleep 5", timeout: 1)
        XCTAssertEqual(r.exitCode, -1)
        XCTAssertTrue(r.error.contains("timed out"))
    }

    func testCheckCommandExists() {
        XCTAssertTrue(shell.checkCommandExists("ls"))
        XCTAssertFalse(shell.checkCommandExists("definitely-not-a-real-command-xyz"))
    }
}
