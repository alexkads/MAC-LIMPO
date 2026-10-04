// SPDX-License-Identifier: GPL-3.0-or-later
// MAC-LIMPO — Copyright (C) 2025-2026 Alex S S Fonseca and contributors.

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
