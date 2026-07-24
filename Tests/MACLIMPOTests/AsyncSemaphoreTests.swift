import XCTest
@testable import MAC_LIMPO

/// Garante que o AsyncSemaphore realmente limita a concorrência — a regressão
/// que ele corrige era um fan-out de scan que estourava em 64 `du` simultâneos.
final class AsyncSemaphoreTests: XCTestCase {
    /// Sob muito mais tarefas que permits, o pico de execução simultânea nunca
    /// pode ultrapassar o valor do semáforo.
    func testNeverExceedsLimit() async {
        let limit = 4
        let semaphore = AsyncSemaphore(value: limit)
        let counter = ConcurrencyCounter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    await semaphore.acquire()
                    await counter.enter()
                    // Cede a vez algumas vezes para dar chance de outras tarefas
                    // rodarem enquanto esta segura o permit.
                    for _ in 0 ..< 5 { await Task.yield() }
                    await counter.leave()
                    semaphore.release()
                }
            }
        }

        let peak = await counter.peak
        XCTAssertLessThanOrEqual(peak, limit, "pico de concorrência \(peak) passou do limite \(limit)")
        XCTAssertGreaterThan(peak, 1, "concorrência nunca aconteceu — teste não exercitou o paralelismo")
    }

    /// Todas as tarefas terminam: nenhum permit vaza e nenhuma fica presa.
    func testAllTasksComplete() async {
        let semaphore = AsyncSemaphore(value: 2)
        let done = ConcurrencyCounter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 50 {
                group.addTask {
                    await semaphore.acquire()
                    await done.enter()
                    await done.leave()
                    semaphore.release()
                }
            }
        }

        let total = await done.totalEntered
        XCTAssertEqual(total, 50)
    }

    /// value: 1 é exclusão mútua — nunca mais de uma tarefa na região crítica.
    func testValueOneIsMutualExclusion() async {
        let semaphore = AsyncSemaphore(value: 1)
        let counter = ConcurrencyCounter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 30 {
                group.addTask {
                    await semaphore.acquire()
                    await counter.enter()
                    await Task.yield()
                    await counter.leave()
                    semaphore.release()
                }
            }
        }

        let peak = await counter.peak
        XCTAssertEqual(peak, 1, "value:1 deveria serializar, mas houve \(peak) simultâneas")
    }
}

/// Rastreia concorrência: quantas tarefas estão na região crítica ao mesmo
/// tempo (current), o máximo observado (peak) e o total que entrou.
private actor ConcurrencyCounter {
    private(set) var current = 0
    private(set) var peak = 0
    private(set) var totalEntered = 0

    func enter() {
        current += 1
        totalEntered += 1
        if current > peak { peak = current }
    }

    func leave() {
        current -= 1
    }
}
