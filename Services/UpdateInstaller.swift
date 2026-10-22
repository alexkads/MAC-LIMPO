// SPDX-License-Identifier: GPL-3.0-or-later
// MAC-LIMPO — Copyright (C) 2025-2026 Alex S S Fonseca and contributors.

import Foundation

/// O que a atualização automática precisa saber do ambiente: se este Mac
/// compila, se dá para trocar este app sem senha, e onde fica a trava do
/// instalador em segundo plano — e se o processo dela ainda está vivo.
extension UpdateChecker {
    /// Quem tem o Swift (Xcode ou Command Line Tools) atualiza como instalou:
    /// o install.sh compila a versão nova neste Mac, sem quarentena. Sem
    /// ferramentas de compilação (instalou pelo .pkg), abre a página da versão.
    nonisolated static let canBuildFromSource: Bool = {
        // Só olha arquivos — nada de Process aqui: esperar um processo roda o
        // run loop da thread principal, o SwiftUI redesenha a faixa no meio, a
        // faixa lê esta mesma constante ainda sendo inicializada e o app cai
        // (dispatch_once recursivo). Nem xcrun, que abre o diálogo "instalar
        // ferramentas". A pasta ativa é a do DEVELOPER_DIR, a escolhida com
        // xcode-select -s (/var/db/xcode_select_link) ou as padrão.
        let fm = FileManager.default
        let candidates = [
            ProcessInfo.processInfo.environment["DEVELOPER_DIR"],
            try? fm.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link"),
            "/Applications/Xcode.app/Contents/Developer",
            "/Library/Developer/CommandLineTools",
        ].compactMap(\.self)
        return candidates.contains { developerDir in
            fm.isExecutableFile(atPath: "\(developerDir)/usr/bin/swift")
                || fm.isExecutableFile(atPath: "\(developerDir)/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift")
        }
    }()

    /// Dá para trocar este app sem senha — o install.sh em segundo plano não tem
    /// como pedir uma. A cópia do .pkg é do root: com o Swift instalado, a
    /// atualização compilava 2–5 min, falhava no `sudo` sem terminal e tentava
    /// de novo a cada 24 h. Essa vai para a página da versão, como quem não tem
    /// o Swift.
    nonisolated static let canUpdateInPlace = canBuildFromSource && isReplaceable(bundle: Bundle.main.bundleURL)

    /// A pasta do bundle aceita escrita e tudo no bundle é de `user` — a mesma
    /// conta do `can_remove` do install.sh.
    nonisolated static func isReplaceable(bundle: URL, user: uid_t = getuid()) -> Bool {
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: bundle.deletingLastPathComponent().path) else { return false }
        func owned(_ url: URL) -> Bool {
            ((try? fm.attributesOfItem(atPath: url.path))?[.ownerAccountID] as? NSNumber)?.uint32Value == user
        }
        guard owned(bundle) else { return false }
        let items = fm.enumerator(at: bundle, includingPropertiesForKeys: nil)
        while let item = items?.nextObject() as? URL {
            if !owned(item) { return false }
        }
        return true
    }

    /// Trava de um instalador em andamento; vence depois disto (build travado).
    nonisolated static let lockLifetime: TimeInterval = 3 * 60 * 60

    struct InstallerRun {
        let log: URL
        let status: URL
    }

    nonisolated static let updateFolder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MAC-LIMPO-build/update", isDirectory: true)
    nonisolated static let installerRun = InstallerRun(
        log: updateFolder.appendingPathComponent("install.log"),
        status: updateFolder.appendingPathComponent("install.status")
    )
    nonisolated static let lockFile = updateFolder.appendingPathComponent("install.lock")
    /// PID do subshell que roda o install.sh e grava o status no fim.
    nonisolated static let pidFile = updateFolder.appendingPathComponent("install.pid")

    /// Há um instalador nosso em andamento: trava recente, sem status final e
    /// com o processo vivo. Só a trava não bastava — um logout ou reinício mata
    /// o instalador sem deixar status, e a faixa ficava em "atualizando" sem
    /// nenhuma checagem até a trava vencer, 3 h depois.
    nonisolated static func installerIsRunning(
        lock: URL = lockFile,
        status: URL = installerRun.status,
        pid: URL = pidFile,
        now: Date = Date()
    ) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: lock.path),
              let created = attributes[.modificationDate] as? Date,
              now.timeIntervalSince(created) < lockLifetime,
              !FileManager.default.fileExists(atPath: status.path)
        else { return false }
        return installerProcessIsAlive(pidFile: pid)
    }

    /// O processo de `pidFile` existe e é o mesmo que o gravou: ele começou
    /// antes do arquivo. Depois de um reinício o número pode ser de outro.
    nonisolated static func installerProcessIsAlive(pidFile: URL = pidFile) -> Bool {
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let written = (try? FileManager.default.attributesOfItem(atPath: pidFile.path))?[.modificationDate] as? Date,
              let started = processStart(pid)
        else { return false }
        return started <= written.addingTimeInterval(1)
    }

    /// Quando `pid` começou, ou `nil` se ele não existe.
    nonisolated static func processStart(_ pid: pid_t) -> Date? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1_000_000)
    }

    /// A versão que o instalador em andamento está instalando (gravada na trava).
    nonisolated static func runningInstallManifest() -> UpdateManifest? {
        guard let data = try? Data(contentsOf: lockFile) else { return nil }
        return try? JSONDecoder().decode(UpdateManifest.self, from: data)
    }

    nonisolated static func releaseLock() {
        try? FileManager.default.removeItem(at: lockFile)
        try? FileManager.default.removeItem(at: pidFile)
    }
}
