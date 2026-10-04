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

    /// Processo que ignora SIGTERM não pode prender o chamador (nem o slot do
    /// `duGate`): após o prazo de graça vem SIGKILL e, no pior caso, abandona-se a leitura.
    func testTimeoutReturnsEvenWhenProcessIgnoresSigterm() {
        let started = Date()
        let r = shell.execute("trap '' TERM; sleep 20", timeout: 1)
        XCTAssertEqual(r.exitCode, -1)
        XCTAssertLessThan(
            Date().timeIntervalSince(started),
            1 + 2 * ShellExecutor.terminateGrace + 2,
            "deve voltar logo após timeout + graça"
        )
    }

    func testCheckCommandExists() {
        XCTAssertTrue(shell.checkCommandExists("ls"))
        XCTAssertFalse(shell.checkCommandExists("definitely-not-a-real-command-xyz"))
    }
}
