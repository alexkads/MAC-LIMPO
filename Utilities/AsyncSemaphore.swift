import Foundation

/// Semáforo de contagem para `async/await`.
///
/// `DispatchSemaphore.wait()` bloqueia a thread, o que num contexto `async`
/// prende uma thread do pool cooperativo — exatamente o que causa a explosão de
/// threads que este tipo existe para evitar. Aqui `acquire()` *suspende* a
/// tarefa (via continuation) em vez de bloquear a thread, então limitar a
/// concorrência não custa threads presas.
///
/// `release()` é síncrono de propósito, para poder ser chamado de um `defer`
/// (que não permite `await`).
final class AsyncSemaphore: @unchecked Sendable {
    private let lock = NSLock()
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        precondition(value >= 0, "valor inicial do semáforo não pode ser negativo")
        permits = value
    }

    /// Toma um permit, suspendendo a tarefa se não houver nenhum livre.
    func acquire() async {
        // Todo o trabalho com o lock fica dentro deste closure, que
        // withCheckedContinuation invoca de forma síncrona — travar/destravar
        // um NSLock direto no corpo de uma função async é proibido (erro no
        // Swift 6). Se houver permit, a continuation é retomada aqui mesmo; caso
        // contrário fica na fila e é retomada por um release() futuro.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if permits > 0 {
                permits -= 1
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    /// Devolve um permit. Se houver alguém esperando, entrega o permit direto a
    /// ela (retomando sua tarefa) em vez de incrementar a contagem.
    func release() {
        lock.lock()
        if waiters.isEmpty {
            permits += 1
            lock.unlock()
        } else {
            let next = waiters.removeFirst()
            lock.unlock() // solta o lock antes de retomar — evita reentrância sob lock
            next.resume()
        }
    }
}
