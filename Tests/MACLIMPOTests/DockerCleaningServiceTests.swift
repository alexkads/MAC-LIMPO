import XCTest
@testable import MAC_LIMPO

/// Testes do parser de tamanhos do `docker system df`.
/// Todas as strings abaixo são saída real do Docker capturada da máquina.
final class DockerCleaningServiceTests: XCTestCase {
    // MARK: - Unidades

    func testParsesDecimalUnits() {
        // O Docker usa unidades decimais (go-units), não binárias.
        XCTAssertEqual(DockerCleaningService.parseDockerSize("6.869GB"), 6_869_000_000)
        XCTAssertEqual(DockerCleaningService.parseDockerSize("148MB"), 148_000_000)
        XCTAssertEqual(DockerCleaningService.parseDockerSize("1.5TB"), 1_500_000_000_000)
    }

    func testParsesLowercaseKilobyte() {
        // O Docker escreve "kB" com k minúsculo; o parser antigo checava "KB"
        // e devolvia 0 para toda a coluna de containers.
        XCTAssertEqual(DockerCleaningService.parseDockerSize("479.2kB"), 479_200)
        XCTAssertEqual(DockerCleaningService.parseDockerSize("24.6kB"), 24600)
    }

    func testParsesBareBytes() {
        XCTAssertEqual(DockerCleaningService.parseDockerSize("0B"), 0)
        XCTAssertEqual(DockerCleaningService.parseDockerSize("512B"), 512)
    }

    // MARK: - Campo Reclaimable

    func testStripsPercentageSuffix() {
        // Regressão: `{{.Reclaimable}}` vem com o percentual junto. O parser
        // antigo removia só o literal "GB", sobrava "3.913 (56%)", o Double
        // falhava e o card do Docker reportava zero.
        XCTAssertEqual(DockerCleaningService.parseDockerSize("3.913GB (56%)"), 3_913_000_000)
        XCTAssertEqual(DockerCleaningService.parseDockerSize("34.55GB (99%)"), 34_550_000_000)
        XCTAssertEqual(DockerCleaningService.parseDockerSize("0B (0%)"), 0)
    }

    // MARK: - Entradas degeneradas

    func testHandlesWhitespaceAndEmptyInput() {
        XCTAssertEqual(DockerCleaningService.parseDockerSize("  2GB \n"), 2_000_000_000)
        XCTAssertEqual(DockerCleaningService.parseDockerSize(""), 0)
        XCTAssertEqual(DockerCleaningService.parseDockerSize("N/A"), 0)
        XCTAssertEqual(DockerCleaningService.parseDockerSize("garbage"), 0)
    }

    func testUnitOrderingDoesNotMisreadSuffixes() {
        // "B" é sufixo de "GB"/"MB"/"kB"/"TB": se fosse testado primeiro,
        // "6.869GB" viraria 6 bytes.
        XCTAssertEqual(DockerCleaningService.parseDockerSize("2GB"), 2_000_000_000)
        XCTAssertNotEqual(DockerCleaningService.parseDockerSize("2GB"), 2)
    }
}
