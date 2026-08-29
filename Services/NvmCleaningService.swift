import Foundation

/// Remove versões antigas do Node.js instaladas pelo nvm, preservando a versão
/// do alias `default` e a mais nova de cada linha major (18.x, 20.x, 22.x…).
/// Qualquer versão removida pode voltar com `nvm install <versão>`.
final class NvmCleaningService: PathBasedCleaningService {
    init() {
        super.init(category: .nvmVersions, targets: Self.obsoleteVersionTargets())
    }

    /// Calcula os alvos no launch; paths que deixarem de existir são ignorados
    /// pelo scan/clean (checagem de `fileExists` na base).
    static func obsoleteVersionTargets(
        versionsDir: String = "~/.nvm/versions/node",
        defaultAliasFile: String = "~/.nvm/alias/default"
    ) -> [CleanTarget] {
        let helper = FileSystemHelper.shared
        let expandedDir = helper.expandPath(versionsDir)
        guard helper.fileExists(atPath: expandedDir) else { return [] }

        let installed = helper.contentsOfDirectory(atPath: expandedDir)
            .filter { $0.hasPrefix("v") }

        // Alias default pode ser uma versão exata ("v22.23.2"), um major ("22")
        // ou algo como "lts/*"/"node" — os dois últimos já ficam protegidos pela
        // regra de "mais nova de cada major".
        let defaultAlias = (try? String(
            contentsOfFile: helper.expandPath(defaultAliasFile),
            encoding: .utf8
        ))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        func numbers(_ version: String) -> [Int] {
            version.dropFirst().split(separator: ".").map { Int($0) ?? 0 }
        }

        // Mais nova de cada major
        var newestPerMajor: [Int: String] = [:]
        for version in installed {
            let major = numbers(version).first ?? 0
            if let current = newestPerMajor[major] {
                if numbers(version).lexicographicallyPrecedes(numbers(current)) == false {
                    newestPerMajor[major] = version
                }
            } else {
                newestPerMajor[major] = version
            }
        }

        let protected = Set(newestPerMajor.values)
        return installed
            .filter { !protected.contains($0) }
            .filter { $0 != defaultAlias && $0 != "v\(defaultAlias)" }
            .sorted()
            .map { CleanTarget("\(versionsDir)/\($0)", label: "Node \($0) (old)") }
    }
}
