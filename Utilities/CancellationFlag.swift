import Foundation

/// Sinal de cancelamento que atravessa a fronteira entre Swift Concurrency e o
/// trabalho bloqueante no GCD (`du`, enumeradores).
///
/// O cancelamento de uma `Task` não chega sozinho a um `Process` rodando numa
/// thread do GCD: `withTaskCancellationHandler` liga esta flag e o
/// `ShellExecutor` a consulta enquanto espera, encerrando o processo. Sem isso,
/// um scan abandonado pelo prazo seguia rodando `du` em segundo plano, e cada
/// novo refresh empilhava mais uma varredura completa do disco.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

/// Roda `work` (bloqueante) no GCD passando uma `CancellationFlag` que é ligada
/// quando a `Task` atual for cancelada.
func runBlockingCancellable<T: Sendable>(
    qos: DispatchQoS.QoSClass = .utility,
    _ work: @escaping @Sendable (CancellationFlag) -> T
) async -> T {
    let flag = CancellationFlag()
    return await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: qos).async {
                continuation.resume(returning: work(flag))
            }
        }
    } onCancel: {
        flag.cancel()
    }
}
