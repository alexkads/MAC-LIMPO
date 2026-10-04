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
}
