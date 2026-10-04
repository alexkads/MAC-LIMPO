import Foundation

/// Resolve uma continuation no máximo uma vez, qualquer que seja a ordem de
/// quem chegar primeiro.
private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

/// Executa `operation` e devolve o resultado, ou `nil` se passar de `seconds`.
///
/// Não usa `withTaskGroup` de propósito: o grupo só retorna quando *todos* os
/// filhos terminam, e um scan preso em `du` bloqueante não coopera com o
/// cancelamento — o prazo nunca valeria. Aqui o chamador é liberado no prazo e a
/// operação, se ainda estiver rodando, termina sozinha em segundo plano.
func withDeadline<T: Sendable>(
    _ seconds: TimeInterval,
    _ operation: @escaping @Sendable () async -> T
) async -> T? {
    await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let gate = OnceGate()
        Task {
            let value = await operation()
            if gate.claim() { continuation.resume(returning: value) }
        }
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if gate.claim() { continuation.resume(returning: nil) }
        }
    }
}

/// Roda trabalho **bloqueante** (varredura de diretório, `du`, `tmutil`) numa
/// thread do GCD em vez de no pool cooperativo do Swift.
///
/// Um `scan` declarado `async` mas que bloqueia no corpo prende uma das poucas
/// threads cooperativas (uma por core). Com vários scans assim em paralelo o pool
/// esgota e até as tarefas que só precisam retomar após um `await` ficam
/// esperando — os cards giram sem andar.
func runBlocking<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
            continuation.resume(returning: work())
        }
    }
}
