// SPDX-License-Identifier: GPL-3.0-or-later
// MAC-LIMPO — Copyright (C) 2025-2026 Alex S S Fonseca and contributors.

import Foundation

/// A conta do container APFS (para o nome do drive, <Free Space> e
/// <Unknown>) e a Lixeira. A varredura dos arquivos fica no `DiskScanner`.
final class DiskXRayService: @unchecked Sendable {
    static let shared = DiskXRayService()

    /// Raiz real do volume de dados — o "drive" do WinDirStat no macOS.
    static let dataRoot = "/System/Volumes/Data"

    // MARK: - APFS

    func overview() -> DiskOverview? {
        guard let device = Self.device(of: Self.dataRoot) else { return nil }
        let result = ShellExecutor.shared.run("/usr/sbin/diskutil", ["apfs", "list", "-plist"], timeout: 30)
        guard result.exitCode == 0, let data = result.output.data(using: .utf8) else { return nil }
        return DiskOverview.parse(plist: data, dataDevice: device)
    }

    /// "disk3s5" para o volume montado em `path`.
    private static func device(of path: String) -> String? {
        var stats = statfs()
        guard statfs(path, &stats) == 0 else { return nil }
        let from = withUnsafeBytes(of: stats.f_mntfromname) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return from.hasPrefix("/dev/") ? String(from.dropFirst(5)) : from
    }

    // MARK: - Ações

    func trash(path: String) -> Bool {
        FileSystemHelper.shared.trashItem(atPath: path)
    }
}
