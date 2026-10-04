// SPDX-License-Identifier: GPL-3.0-or-later
// MAC-LIMPO — Copyright (C) 2025-2026 Alex S S Fonseca and contributors.

import Foundation

/// Textos do Disk X-Ray no padrão do Finder: tamanhos decimais (GB), datas
/// curtas da localidade, contagens com separador de milhar.
enum SizeFormat {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, value), countStyle: .file)
    }

    static func percent(_ fraction: Double) -> String {
        let value = fraction * 100
        if value > 0, value < 0.1 { return "<0.1%" }
        return value.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    static func count(_ value: Int) -> String {
        value.formatted(.number)
    }

    static func date(_ secondsSince1970: UInt32) -> String {
        guard secondsSince1970 > 0 else { return "" }
        return Date(timeIntervalSince1970: TimeInterval(secondsSince1970))
            .formatted(date: .abbreviated, time: .shortened)
    }
}
