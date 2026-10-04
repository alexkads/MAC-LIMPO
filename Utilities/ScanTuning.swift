// SPDX-License-Identifier: GPL-3.0-or-later
// MAC-LIMPO — Copyright (C) 2025-2026 Alex S S Fonseca and contributors.

import Foundation
import IOKit

/// Quantas threads e que buffer usar para varrer um volume, decidido pelo
/// hardware da máquina e pelo tipo do volume — o programa roda em Macs
/// diferentes, então nada é fixo.
///
/// - SSD local: uma thread por núcleo ativo, entre 4 e 16 (a faixa do
///   `ScanningThreads` do WinDirStat). No APFS o limite é o disco responder os
///   metadados: num M-series de 10 núcleos, 8 a 16 threads rendem o mesmo
///   (15–16 s para 2,9 milhões de itens), contra 52 s com 1.
/// - HD mecânico: 2 threads — leituras paralelas viram saltos da cabeça.
/// - Volume de rede: 4 threads e buffer de 64 KiB, como o WinDirStat faz para
///   volumes remotos (FinderBasic.cpp: REMOTE_BUFFER_SIZE).
struct ScanTuning: Equatable, Sendable {
    let threads: Int
    let bufferSize: Int

    enum Medium: Equatable, Sendable {
        case solidState, rotational, unknown
    }

    static let localBufferSize = 4 * 1024 * 1024 // FinderBasic.cpp: LOCAL_BUFFER_SIZE
    static let remoteBufferSize = 64 * 1024 // FinderBasic.cpp: REMOTE_BUFFER_SIZE
    static let threadRange = 4 ... 16

    /// Regra pura (testável).
    static func decide(isLocal: Bool, medium: Medium, activeCores: Int) -> ScanTuning {
        guard isLocal else { return ScanTuning(threads: 4, bufferSize: remoteBufferSize) }
        if medium == .rotational { return ScanTuning(threads: 2, bufferSize: localBufferSize) }
        let threads = min(threadRange.upperBound, max(threadRange.lowerBound, activeCores))
        return ScanTuning(threads: threads, bufferSize: localBufferSize)
    }

    /// Ajuste para o volume onde `path` está, nesta máquina.
    static func recommended(for path: String) -> ScanTuning {
        var stats = statfs()
        guard statfs(path, &stats) == 0 else {
            return decide(isLocal: true, medium: .unknown, activeCores: ProcessInfo.processInfo.activeProcessorCount)
        }
        let isLocal = stats.f_flags & UInt32(MNT_LOCAL) != 0
        let device = withUnsafeBytes(of: stats.f_mntfromname) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        let medium = isLocal ? self.medium(ofBSDDevice: device) : .unknown
        return decide(isLocal: isLocal, medium: medium, activeCores: ProcessInfo.processInfo.activeProcessorCount)
    }

    /// "Medium Type" ("Solid State" / "Rotational") do dispositivo físico por
    /// trás de "/dev/diskNsM", subindo pela árvore do IOKit (volume APFS →
    /// container → disco → controlador).
    static func medium(ofBSDDevice device: String) -> Medium {
        let bsdName = device.hasPrefix("/dev/") ? String(device.dropFirst(5)) : device
        guard !bsdName.isEmpty,
              let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName)
        else { return .unknown }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return .unknown }
        defer { IOObjectRelease(service) }

        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        guard let characteristics = IORegistryEntrySearchCFProperty(
            service, kIOServicePlane, "Device Characteristics" as CFString, kCFAllocatorDefault, options
        ) as? [String: Any],
            let mediumType = characteristics["Medium Type"] as? String
        else { return .unknown }

        switch mediumType {
        case "Solid State": return .solidState
        case "Rotational": return .rotational
        default: return .unknown
        }
    }
}
