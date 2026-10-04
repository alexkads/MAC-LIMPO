import XCTest
@testable import MAC_LIMPO

/// Confere o port do treemap do WinDirStat contra valores calculados à mão a
/// partir de TreeMap.cpp / TreeMapLayout.cpp.
final class CushionTreemapTests: XCTestCase {
    private typealias T = CushionTreemap

    // MARK: - Cor

    func testMakeBrightColorDistributesOverflowLikeWinDirStat() {
        // Azul puro com brilho 0.6: f = 3·0.6/1 = 1.8 → b = Int(1.8·255) = 458
        // (458,99… truncado, como o static_cast<int> do C++) → excesso 203,
        // metade (101) para r e g.
        XCTAssertEqual(T.makeBrightColor(T.RGB(r: 0, g: 0, b: 255), 0.6), T.RGB(r: 101, g: 101, b: 255))
        // Branco já tem brilho 1.0 → escala para 0.6 sem estourar.
        XCTAssertEqual(T.makeBrightColor(T.RGB(r: 255, g: 255, b: 255), 0.6), T.RGB(r: 153, g: 153, b: 153))
    }

    func testDefaultPaletteMatchesWinDirStatValues() {
        // Valores de MakeBrightColor(c, 0.6) sobre DefaultCushionColors.
        let expected: [(Int, Int, Int)] = [
            (101, 101, 255), (255, 101, 101), (101, 255, 101), (229, 229, 0), (0, 229, 229), (229, 0, 229),
            (255, 193, 10), (44, 158, 255), (255, 44, 158), (158, 255, 44), (193, 10, 255), (44, 255, 158),
            (255, 10, 193), (10, 193, 255), (255, 158, 44), (10, 255, 193), (158, 44, 255), (153, 153, 153)
        ]
        XCTAssertEqual(T.defaultPalette, expected.map { T.RGB(r: $0.0, g: $0.1, b: $0.2) })
    }

    func testDefaultPaletteHasEighteenColorsAllAtBrightnessPointSix() {
        XCTAssertEqual(T.defaultPalette.count, 18)
        for color in T.defaultPalette {
            let brightness = Double(color.r + color.g + color.b) / 3 / 255
            XCTAssertEqual(brightness, 0.6, accuracy: 0.01)
        }
    }

    func testNormalizeColorPushesSecondOverflowToThird() {
        var r = 400, g = 250, b = 0
        T.normalizeColor(&r, &g, &b)
        // h = 72 → g = 322 → excesso 67 vai para b.
        XCTAssertEqual([r, g, b], [255, 255, 139])
    }

    // MARK: - Layout Rows

    func testArrangeRowsTilesBoundsExactlyWithoutGapsOrOverlap() {
        let bounds = T.IntRect(left: 0, top: 0, right: 400, bottom: 300)
        let weights: [UInt64] = [500, 300, 100, 60, 30, 10]
        let regions = T.arrangeRows(weights: weights, parentWeight: weights.reduce(0, +), bounds: bounds)

        XCTAssertEqual(regions.reduce(0) { $0 + $1.width * $1.height }, 400 * 300)
        for (i, a) in regions.enumerated() {
            XCTAssertFalse(a.isEmpty)
            XCTAssertGreaterThanOrEqual(a.left, 0)
            XCTAssertLessThanOrEqual(a.right, 400)
            for b in regions[(i + 1)...] {
                let overlaps = a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom
                XCTAssertFalse(overlaps, "\(a) sobrepõe \(b)")
            }
        }
    }

    func testArrangeRowsGivesZeroWeightsEmptyRegions() {
        let regions = T.arrangeRows(
            weights: [10, 0], parentWeight: 10, bounds: T.IntRect(left: 0, top: 0, right: 100, bottom: 50)
        )
        XCTAssertEqual(regions[0], T.IntRect(left: 0, top: 0, right: 100, bottom: 50))
        XCTAssertTrue(regions[1].isEmpty)
    }

    func testArrangeRowsUsesHorizontalRowsWhenWiderThanTall() {
        // Um único filho ocupa tudo.
        let wide = T.arrangeRows(weights: [1], parentWeight: 1, bounds: T.IntRect(left: 0, top: 0, right: 200, bottom: 100))
        XCTAssertEqual(wide, [T.IntRect(left: 0, top: 0, right: 200, bottom: 100)])
        // Dois iguais num retângulo largo: lado a lado na mesma linha.
        let pair = T.arrangeRows(weights: [1, 1], parentWeight: 2, bounds: T.IntRect(left: 0, top: 0, right: 200, bottom: 100))
        XCTAssertEqual(pair, [
            T.IntRect(left: 0, top: 0, right: 100, bottom: 100),
            T.IntRect(left: 100, top: 0, right: 200, bottom: 100)
        ])
    }

    // MARK: - Superfície

    func testAddRidgeMatchesWinDirStatFormula() {
        var surface: T.Surface = (0, 0, 0, 0)
        T.addRidge(T.IntRect(left: 10, top: 20, right: 30, bottom: 60), &surface, 0.38)
        let h4 = 4 * 0.38
        XCTAssertEqual(surface.0, -h4 / 20, accuracy: 1e-12)
        XCTAssertEqual(surface.2, h4 / 20 * 40, accuracy: 1e-12)
        XCTAssertEqual(surface.1, -h4 / 40, accuracy: 1e-12)
        XCTAssertEqual(surface.3, h4 / 40 * 80, accuracy: 1e-12)
    }
}
