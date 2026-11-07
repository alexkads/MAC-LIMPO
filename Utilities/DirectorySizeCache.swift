import Foundation

/// Tamanhos de diretório já medidos, válidos enquanto a pasta não mudar.
///
/// Medir de novo cada `node_modules` a cada scan (hoje são centenas em
/// `~/Projects`) relia os metadados de milhões de arquivos toda vez. Aqui a
/// medição é reaproveitada enquanto a data de modificação do diretório for a
/// mesma — `npm`, `pnpm` e `yarn` regravam um arquivo de controle na raiz do
/// `node_modules` a cada instalação (`.package-lock.json`, `.modules.yaml`,
/// `.yarn-integrity`), o que muda essa data. Mudanças que não tocam a raiz não
/// são vistas, então toda entrada expira depois de `lifetime` de qualquer forma.
final class DirectorySizeCache: @unchecked Sendable {
    private struct Entry {
        let size: Int64
        let modifiedAt: Date
        let measuredAt: Date
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private let lifetime: TimeInterval
    private let now: @Sendable () -> Date

    init(lifetime: TimeInterval = 6 * 3600, now: @escaping @Sendable () -> Date = Date.init) {
        self.lifetime = lifetime
        self.now = now
    }

    /// Tamanho guardado para `path`, se a pasta não mudou e a medição não expirou.
    func size(for path: String, modifiedAt: Date) -> Int64? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[path],
              entry.modifiedAt == modifiedAt,
              now().timeIntervalSince(entry.measuredAt) < lifetime
        else { return nil }
        return entry.size
    }

    func store(_ size: Int64, for path: String, modifiedAt: Date) {
        lock.lock()
        entries[path] = Entry(size: size, modifiedAt: modifiedAt, measuredAt: now())
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}
