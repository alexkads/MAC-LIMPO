import XCTest
@testable import MAC_LIMPO

final class DeadlineTests: XCTestCase {
    func testReturnsValueWhenOperationFinishesInTime() async {
        let value = await withDeadline(5) { 42 }
        XCTAssertEqual(value, 42)
    }

    /// O ponto do helper: a operação NÃO coopera com cancelamento (como um scan
    /// preso em `du` bloqueante) e mesmo assim o chamador é liberado no prazo.
    func testReturnsNilOnDeadlineEvenIfOperationIgnoresCancellation() async {
        let started = Date()
        let value: Int? = await withDeadline(0.3) {
            // Bloqueia a thread sem checar cancelamento (como um `du` síncrono).
            usleep(3_000_000)
            return 1
        }
        XCTAssertNil(value)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "não deve esperar a operação terminar")
    }

    /// No prazo a operação é cancelada, não só abandonada: um `du` em andamento
    /// recebe o cancelamento e para em vez de seguir lendo o disco.
    func testDeadlineCancelsTheOperation() async {
        let finished = expectation(description: "operação parou")
        let started = Date()
        let value: Int? = await withDeadline(0.3) {
            let r = await runBlockingCancellable { flag in
                ShellExecutor.shared.run("/bin/sleep", ["20"], timeout: 60, cancellation: flag)
            }
            finished.fulfill()
            return Int(r.exitCode)
        }
        XCTAssertNil(value)
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "o sleep de 20s deve ter sido encerrado")
    }
}
