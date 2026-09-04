import Foundation

/// Limpa cache de registry, index e git do Cargo/Rust, além de toolchains
/// rustup fixadas em versão (`1.92.0-…`) que já foram superadas.
final class CargoCleaningService: PathBasedCleaningService {
    init() {
        super.init(category: .cargo, targets: [
            CleanTarget("~/.cargo/registry/cache"),
            CleanTarget("~/.cargo/registry/index"),
            CleanTarget("~/.cargo/git"),
            // Downloads parciais/temporários do rustup
            CleanTarget("~/.rustup/downloads", label: "rustup downloads", strategy: .removeContents),
            CleanTarget("~/.rustup/tmp", label: "rustup tmp", strategy: .removeContents)
        ] + Self.obsoleteToolchainTargets())
    }

    /// Toolchains do rustup que podem ser removidas com segurança. Regras:
    ///
    /// - Canais (`stable-*`, `beta-*`, `nightly-*`) nunca entram — o rustup os
    ///   atualiza no lugar, então cada um é a única cópia da sua linha.
    /// - A toolchain `default_toolchain` e as listadas em `[overrides]` do
    ///   `settings.toml` (`rustup override set`) são protegidas.
    /// - Entre as fixadas em versão (`1.92.0-aarch64-apple-darwin`), a mais nova
    ///   fica; as anteriores são removidas. Um projeto com `rust-toolchain.toml`
    ///   apontando para uma removida faz o rustup re-baixá-la no próximo build.
    ///
    /// Remover a pasta é o que `rustup toolchain uninstall` faz; como vai para a
    /// Lixeira, ainda dá para restaurar.
    static func obsoleteToolchainTargets(
        toolchainsDir: String = "~/.rustup/toolchains",
        settingsFile: String = "~/.rustup/settings.toml"
    ) -> [CleanTarget] {
        let helper = FileSystemHelper.shared
        let expandedDir = helper.expandPath(toolchainsDir)
        guard helper.fileExists(atPath: expandedDir) else { return [] }

        let settings = (try? String(contentsOfFile: helper.expandPath(settingsFile), encoding: .utf8)) ?? ""
        let protected = protectedToolchains(fromSettings: settings)

        let installed = helper.contentsOfDirectory(atPath: expandedDir).filter { !$0.hasPrefix(".") }
        return obsoletePinnedToolchains(among: installed, protected: protected)
            .map { CleanTarget("\(toolchainsDir)/\($0)", label: "Rust toolchain \($0) (superseded)") }
    }

    /// Versão numérica de uma toolchain fixada ("1.92.0-aarch64-apple-darwin" →
    /// [1, 92, 0]); `nil` para canais e nomes não reconhecidos.
    static func pinnedVersionNumbers(_ name: String) -> [Int]? {
        guard let dash = name.firstIndex(of: "-") else { return nil }
        let parts = name[..<dash].split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber), let value = Int(part) else { return nil }
            numbers.append(value)
        }
        return numbers
    }

    /// Lê `default_toolchain` e os valores de `[overrides]` do settings.toml.
    static func protectedToolchains(fromSettings text: String) -> Set<String> {
        var result = Set<String>()
        var inOverrides = false
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inOverrides = line == "[overrides]"
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if key == "default_toolchain" || inOverrides, !value.isEmpty {
                result.insert(value)
            }
        }
        return result
    }

    /// Entre as toolchains fixadas em versão, devolve todas menos a mais nova e
    /// menos as protegidas. Canais nunca aparecem no resultado.
    static func obsoletePinnedToolchains(among names: [String], protected: Set<String>) -> [String] {
        let pinned = names.compactMap { name -> (name: String, numbers: [Int])? in
            guard let numbers = pinnedVersionNumbers(name) else { return nil }
            return (name, numbers)
        }
        guard let newest = pinned.max(by: { $0.numbers.lexicographicallyPrecedes($1.numbers) }) else { return [] }
        return pinned
            .filter { $0.name != newest.name && !protected.contains($0.name) }
            .sorted { $0.numbers.lexicographicallyPrecedes($1.numbers) }
            .map(\.name)
    }
}
