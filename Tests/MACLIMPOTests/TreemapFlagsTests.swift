import XCTest
@testable import MAC_LIMPO

@MainActor
final class TreemapFlagsTests: XCTestCase {
    private let view = CGSize(width: 400, height: 200)

    private func sprite() throws -> TreemapFlags.Sprite {
        try XCTUnwrap(TreemapFlags.sprite(title: "arquivo.bin", subtitle: "12 MB", folder: false,
                                          color: TreemapRenderer.RGB(r: 0.2, g: 0.6, b: 0.9), scale: 1))
    }

    /// No meio do mapa, a base do mastro fica exatamente no cursor.
    func testTooltipIsPlantedAtThePointer() throws {
        let sprite = try sprite()
        let point = CGPoint(x: 150, y: 120)
        let frame = TreemapFlags.tooltipFrame(for: sprite, at: point, in: view)
        XCTAssertEqual(frame.minX + sprite.base.x, point.x, accuracy: 1e-9)
        XCTAssertEqual(frame.minY + sprite.base.y, point.y, accuracy: 1e-9)
    }

    /// Perto das bordas, o tooltip é empurrado para dentro, inteiro.
    func testTooltipStaysInsideTheMapNearEdges() throws {
        let sprite = try sprite()
        let bounds = CGRect(origin: .zero, size: view)
        for point in [CGPoint(x: 395, y: 10), CGPoint(x: 3, y: 5), CGPoint(x: 398, y: 198)] {
            XCTAssertTrue(bounds.contains(TreemapFlags.tooltipFrame(for: sprite, at: point, in: view)), "\(point)")
        }
    }

    /// Mesmo conteúdo, mesmo sprite (em cache — o tooltip é pedido a cada movimento).
    func testSpriteIsCached() throws {
        XCTAssertTrue(try sprite().image === sprite().image)
    }
}

@MainActor
final class HoverTooltipTests: XCTestCase {
    /// Como um tooltip: nada enquanto o ponteiro se mexe; depois de parado um
    /// instante, a bandeira no ponto onde ele parou; tremida pequena mantém,
    /// movimento de verdade esconde.
    func testTooltipWaitsForThePointerToRest() async throws {
        let hover = HoverState()
        hover.pointerMoved(to: CGPoint(x: 10, y: 10), item: 1)
        hover.pointerMoved(to: CGPoint(x: 50, y: 40), item: 2)
        XCTAssertNil(hover.tooltip)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(hover.tooltip, "apareceu antes da pausa")
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(hover.tooltip, HoverState.Tooltip(item: 2, point: CGPoint(x: 50, y: 40)))

        hover.pointerMoved(to: CGPoint(x: 52, y: 41), item: 2)
        XCTAssertNotNil(hover.tooltip, "tremida pequena escondeu")
        hover.pointerMoved(to: CGPoint(x: 90, y: 40), item: 3)
        XCTAssertNil(hover.tooltip)
        hover.pointerMoved(to: nil, item: nil)
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertNil(hover.tooltip, "voltou depois de o ponteiro sair do mapa")
    }
}

@MainActor
final class TreemapFlagsSideTests: XCTestCase {
    /// Perto da borda direita a bandeira vira: o pano abre para a esquerda e o
    /// mastro continua no ponteiro (antes ela era empurrada e o mastro se afastava).
    func testFlagFlipsSideNearTheRightEdgeKeepingThePoleAtThePointer() throws {
        let view = CGSize(width: 400, height: 200)
        func sprite(_ mirrored: Bool) -> TreemapFlags.Sprite? {
            TreemapFlags.sprite(title: "daily_hammer00.fst", subtitle: "30,1 MB", folder: false,
                                color: TreemapRenderer.RGB(r: 0.6, g: 0.4, b: 0.9), scale: 1, mirrored: mirrored)
        }
        for point in [CGPoint(x: 120, y: 120), CGPoint(x: 380, y: 120)] {
            let flag = try XCTUnwrap(TreemapFlags.tooltip(at: point, in: view, sprite: sprite))
            XCTAssertEqual(flag.frame.minX + flag.sprite.base.x, point.x, accuracy: 1e-9, "mastro longe do ponteiro em \(point)")
            XCTAssertTrue(CGRect(origin: .zero, size: view).contains(flag.frame))
        }
        let right = try XCTUnwrap(TreemapFlags.tooltip(at: CGPoint(x: 120, y: 120), in: view, sprite: sprite))
        let left = try XCTUnwrap(TreemapFlags.tooltip(at: CGPoint(x: 380, y: 120), in: view, sprite: sprite))
        XCTAssertLessThan(right.sprite.base.x, right.sprite.size.width / 2, "longe da borda: mastro à esquerda")
        XCTAssertGreaterThan(left.sprite.base.x, left.sprite.size.width / 2, "perto da borda: mastro à direita")
    }
}
