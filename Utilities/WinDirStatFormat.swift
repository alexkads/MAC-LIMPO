import Foundation

/// Formatação de textos do WinDirStat (windirstat/HelpersInterface.cpp), com a
/// localidade do sistema no lugar da do Windows.
enum WinDirStatFormat {
    private static let ki: UInt64 = 1024
    private static let mi: UInt64 = 1024 * 1024
    private static let gi: UInt64 = 1024 * 1024 * 1024
    private static let ti: UInt64 = 1024 * 1024 * 1024 * 1024

    /// FormatBytes com UseSizeSuffixes (o padrão): unidades binárias KiB/MiB/GiB/TiB.
    static func bytes(_ value: Int64) -> String {
        let n = UInt64(max(0, value))
        let units: [(bytes: UInt64, threshold: UInt64, suffix: String)] = [
            (ti, ti - gi / 2, "TiB"),
            (gi, gi - mi / 2, "GiB"),
            (mi, mi - ki / 2, "MiB"),
            (ki, ki, "KiB")
        ]
        for unit in units where n >= unit.threshold {
            return double(Double(n) / Double(unit.bytes)) + " " + unit.suffix
        }
        return "\(n) bytes"
    }

    /// FormatDouble: sempre duas casas, separador decimal da localidade.
    static func double(_ value: Double) -> String {
        let x = Int((max(0, value) * 100).rounded(.toNearestOrAwayFromZero))
        let i = x / 100
        let r = x % 100
        return "\(i)\(decimalSeparator)\(r / 10)\(r % 10)"
    }

    /// FormatDouble(f * 100) + "%".
    static func percent(_ fraction: Double) -> String {
        double(fraction * 100) + "%"
    }

    /// FormatCount: inteiro com separador de milhar.
    static func count(_ value: Int) -> String {
        countFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// FormatFileTime: data curta + dois espaços + hora sem segundos.
    static func fileTime(_ secondsSince1970: UInt32) -> String {
        guard secondsSince1970 > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(secondsSince1970))
        return dateFormatter.string(from: date) + "  " + timeFormatter.string(from: date)
    }

    static var decimalSeparator: String { Locale.current.decimalSeparator ?? "." }

    private static let countFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
