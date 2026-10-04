import Foundation

// MARK: - Container APFS

/// Papel de um volume no container APFS do disco interno.
enum VolumeRole: String, Sendable {
    case data = "Data"
    case system = "System"
    case preboot = "Preboot"
    case recovery = "Recovery"
    case vm = "VM"
    case update = "Update"
    case other

    init(roles: [String]) {
        self = roles.first.flatMap(VolumeRole.init(rawValue:)) ?? .other
    }

    /// O que é, em uma frase — e se dá para fazer algo a respeito.
    var explanation: String {
        switch self {
        case .data: "Your files, apps and their data. Drill down below."
        case .system: "macOS itself, sealed and read-only. Not cleanable."
        case .preboot: "Boot files and OS cryptexes (Safari, system libraries). Managed by macOS."
        case .recovery: "Recovery system. Managed by macOS."
        case .vm: "Swap and sleep image. Grows under memory pressure; a restart frees it."
        case .update: "Staged macOS update. Freed when the update finishes."
        case .other: "Other APFS volume in this container."
        }
    }
}

/// Um volume do container, com o espaço que o APFS diz que ele consome.
struct VolumeSlice: Identifiable, Sendable, Equatable {
    let id: String // DeviceIdentifier, ex.: "disk3s5"
    let name: String
    let role: VolumeRole
    let bytes: Int64
}

/// A conta do disco inteiro, como o APFS a vê. É a fonte da verdade: a soma
/// das fatias, do livre e do overhead dá exatamente `capacity`.
struct DiskOverview: Sendable, Equatable {
    let capacity: Int64
    let free: Int64
    /// Volumes do container, maiores primeiro.
    let volumes: [VolumeSlice]

    var used: Int64 { capacity - free }
    var dataVolume: VolumeSlice? { volumes.first { $0.role == .data } }
    /// Metadados e reservas do próprio container, fora de qualquer volume.
    var containerOverhead: Int64 { max(0, used - volumes.reduce(0) { $0 + $1.bytes }) }

    /// Interpreta `diskutil apfs list -plist` e devolve o container que contém
    /// o volume `dataDevice` (ex.: "disk3s5", o volume montado em
    /// /System/Volumes/Data). Função pura (testável).
    static func parse(plist data: Data, dataDevice: String) -> DiskOverview? {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let containers = root["Containers"] as? [[String: Any]]
        else { return nil }

        for container in containers {
            let volumes = (container["Volumes"] as? [[String: Any]]) ?? []
            guard volumes.contains(where: { ($0["DeviceIdentifier"] as? String) == dataDevice }) else { continue }

            let slices = volumes.compactMap { volume -> VolumeSlice? in
                guard let device = volume["DeviceIdentifier"] as? String else { return nil }
                return VolumeSlice(
                    id: device,
                    name: volume["Name"] as? String ?? device,
                    role: VolumeRole(roles: volume["Roles"] as? [String] ?? []),
                    bytes: (volume["CapacityInUse"] as? NSNumber)?.int64Value ?? 0
                )
            }
            guard let capacity = (container["CapacityCeiling"] as? NSNumber)?.int64Value else { return nil }
            return DiskOverview(
                capacity: capacity,
                free: (container["CapacityFree"] as? NSNumber)?.int64Value ?? 0,
                volumes: slices.sorted { $0.bytes > $1.bytes }
            )
        }
        return nil
    }
}

// MARK: - Árvore de tamanhos

/// Um item da lista do Raio-X. Classe porque a árvore é carregada aos poucos
/// (descer num nível além do medido dispara um novo `du` só daquele ramo).
@MainActor
final class XRayNode: Identifiable {
    enum Kind: Equatable, Sendable {
        /// Diretório real.
        case directory
        /// Arquivo real (listado ao abrir a pasta).
        case file
        /// Arquivos soltos da pasta, agregados: tamanho da pasta menos as subpastas.
        case looseFiles
        /// O que o APFS diz que existe e o `du` não conseguiu ler.
        case unmeasured
    }

    /// Caminho real no volume Data (ex.: /System/Volumes/Data/Users/x).
    let path: String
    /// Caminho como o usuário o conhece (firmlinks resolvidos: /Users/x).
    let displayPath: String
    let name: String
    let kind: Kind
    var size: Int64
    /// `nil` = ainda não medido abaixo deste nível.
    var children: [XRayNode]?
    /// Alguma subpasta não pôde ser lida (precisa de Full Disk Access ou root).
    var isPartial: Bool
    weak var parent: XRayNode?

    nonisolated var id: String { "\(kind)|\(path)" }
    var isNavigable: Bool { kind == .directory }

    init(
        path: String,
        displayPath: String,
        name: String,
        kind: Kind,
        size: Int64,
        children: [XRayNode]? = nil,
        isPartial: Bool = false
    ) {
        self.path = path
        self.displayPath = displayPath
        self.name = name
        self.kind = kind
        self.size = size
        self.children = children
        self.isPartial = isPartial
        children?.forEach { $0.parent = self }
    }

    func setChildren(_ nodes: [XRayNode]) {
        children = nodes.sorted { $0.size > $1.size }
        children?.forEach { $0.parent = self }
    }

    /// Remove um filho (ex.: movido para a Lixeira) e desconta o tamanho de
    /// todos os ancestrais.
    func remove(_ child: XRayNode) {
        children?.removeAll { $0 === child }
        var node: XRayNode? = self
        while let current = node {
            current.size = max(0, current.size - child.size)
            node = current.parent
        }
    }
}

// MARK: - Saída do du

enum DuOutput {
    /// Linhas "KB\tcaminho" de `du -k` → caminho → bytes. Ignora lixo.
    static func parseSizes(_ output: String) -> [String: Int64] {
        var sizes: [String: Int64] = [:]
        for line in output.split(separator: "\n") {
            guard let tab = line.firstIndex(of: "\t"),
                  let kb = Int64(line[line.startIndex ..< tab].trimmingCharacters(in: .whitespaces))
            else { continue }
            let path = String(line[line.index(after: tab)...])
            guard !path.isEmpty else { continue }
            sizes[path] = kb * 1024
        }
        return sizes
    }

    /// Caminhos que o `du` não conseguiu ler, a partir do stderr
    /// ("du: /x/y: Permission denied" / "Operation not permitted").
    static func parseUnreadable(_ stderr: String) -> Set<String> {
        var paths = Set<String>()
        for line in stderr.split(separator: "\n") where line.hasPrefix("du: ") {
            let body = line.dropFirst(4)
            guard let separator = body.range(of: ": ", options: .backwards) else { continue }
            let reason = body[separator.upperBound...]
            guard reason.contains("denied") || reason.contains("not permitted") else { continue }
            paths.insert(String(body[..<separator.lowerBound]))
        }
        return paths
    }

    /// Monta a árvore a partir de `du -k -d N root`. Diretórios no limite de
    /// profundidade ficam com `children == nil` (carregados sob demanda).
    /// Cada pasta medida ganha uma linha "arquivos soltos" com o que sobra.
    @MainActor
    static func buildTree(
        root: String,
        sizes: [String: Int64],
        unreadable: Set<String>,
        maxDepth: Int,
        displayPath: (String) -> String
    ) -> XRayNode? {
        guard let rootSize = sizes[root] else { return nil }

        var childrenByParent: [String: [String]] = [:]
        for path in sizes.keys where path != root && path.hasPrefix(root) {
            childrenByParent[(path as NSString).deletingLastPathComponent, default: []].append(path)
        }

        // Ancestrais de caminhos ilegíveis também são "parciais".
        var partial = Set<String>()
        for path in unreadable {
            var current = path
            while current.count >= root.count {
                partial.insert(current)
                let parentPath = (current as NSString).deletingLastPathComponent
                if parentPath == current { break }
                current = parentPath
            }
        }

        func node(for path: String, depth: Int) -> XRayNode {
            let size = sizes[path] ?? 0
            let shown = displayPath(path)
            let name = depth == 0 ? shown : (path as NSString).lastPathComponent
            let result = XRayNode(
                path: path, displayPath: shown, name: name, kind: .directory,
                size: size, isPartial: partial.contains(path)
            )
            guard depth < maxDepth else { return result }

            var kids = (childrenByParent[path] ?? []).map { node(for: $0, depth: depth + 1) }
            let loose = size - kids.reduce(0) { $0 + $1.size }
            if loose > 0 {
                kids.append(XRayNode(
                    path: path, displayPath: shown, name: "Files in this folder",
                    kind: .looseFiles, size: loose
                ))
            }
            result.setChildren(kids)
            return result
        }

        let tree = node(for: root, depth: 0)
        tree.size = rootSize
        return tree
    }
}

// MARK: - Firmlinks

/// Traduz caminhos do volume Data para o caminho que o usuário conhece. O
/// macOS junta System e Data com firmlinks (/usr/share/firmlinks):
/// /System/Volumes/Data/Users aparece como /Users.
struct Firmlinks: Sendable {
    let dataRoot: String
    /// (caminho visível, caminho relativo no Data), mais específicos primeiro.
    let links: [(visible: String, relative: String)]

    init(dataRoot: String = "/System/Volumes/Data", contents: String) {
        self.dataRoot = dataRoot
        links = contents.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0], parts[1])
        }
        .sorted { $0.relative.count > $1.relative.count }
    }

    static func system() -> Firmlinks {
        Firmlinks(contents: (try? String(contentsOfFile: "/usr/share/firmlinks", encoding: .utf8)) ?? "")
    }

    func displayPath(_ path: String) -> String {
        guard path.hasPrefix(dataRoot + "/") else { return path }
        let relative = String(path.dropFirst(dataRoot.count + 1))
        for link in links where relative == link.relative || relative.hasPrefix(link.relative + "/") {
            return link.visible + relative.dropFirst(link.relative.count)
        }
        return path
    }
}
