import XCTest
@testable import MAC_LIMPO

final class TreemapRendererTests: XCTestCase {
    /// Raiz 0 com um arquivo enorme (1) e um minúsculo (2): no mapa inteiro o
    /// pequeno fica abaixo de meio pixel e não é desenhado.
    private func source(_ weights: [Int32: UInt64] = [0: 10001, 1: 10000, 2: 1]) -> TreemapRenderer.Source {
        return TreemapRenderer.Source(
            weight: { weights[$0] ?? 0 },
            children: { $0 == 0 ? [1, 2] : [] },
            isLeaf: { $0 != 0 },
            color: { _ in TreemapRenderer.RGB(r: 0.5, g: 0.5, b: 0.5) },
            name: { "item \($0)" },
            sizeText: { _ in "" },
            isEmphasized: { _ in true }
        )
    }

    private func render(_ viewport: CGRect, source: TreemapRenderer.Source? = nil) throws -> TreemapRenderer.Rendering {
        let style = TreemapRenderer.Style(scale: 1, dark: true, background: .black)
        return try XCTUnwrap(TreemapRenderer.render(root: 0, width: 400, height: 200, viewport: viewport, style: style,
                                                    source: source ?? self.source(), isCancelled: { false }))
    }

    private let canvas = CGRect(x: 0, y: 0, width: 400, height: 200)

    private func unit(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX / 400, y: rect.minY / 200, width: rect.width / 400, height: rect.height / 200)
    }

    func testFullViewportSkipsSubpixelItems() throws {
        let rendering = try render(TreemapRenderer.fullViewport)
        XCTAssertEqual(rendering.rects[0], CGRect(x: 0, y: 0, width: 400, height: 200))
        XCTAssertNotNil(rendering.rects[1])
        XCTAssertNil(rendering.rects[2])
    }

    func testMagnifiedViewportRevealsSmallItemAndSkipsHiddenOnes() throws {
        // O minúsculo fica na faixa da direita; a lupa a 64× nesse canto o desenha.
        let side = 1.0 / 64
        let rendering = try render(CGRect(x: 1 - side, y: 1 - side, width: side, height: side))
        XCTAssertEqual(rendering.rects[0]?.width ?? 0, 400 * 64, accuracy: 0.001)
        XCTAssertNotNil(rendering.rects[2])
        // Fora da área visível nada é desenhado nem entra no hit-test.
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 200)
        for (item, rect) in rendering.rects where item != 0 {
            XCTAssertTrue(rect.intersects(bounds), "item \(item) fora da tela")
        }
        let hit = TreemapRenderer.hitTest(CGPoint(x: 399, y: 199), in: rendering, source: source())
        XCTAssertEqual(hit, 2)
    }

    /// Árvore de 14 níveis com 4 irmãos iguais por nível (~275 GB): o último nível é
    /// um arquivo de 1 KB (id 53). Ids: o nível `l` (1…14) tem os filhos 4l-3…4l; o
    /// primeiro de cada nível é a pasta que continua.
    private func deepSource() -> (TreemapRenderer.Source, Set<Int32>) {
        var weights: [Int32: UInt64] = [0: 1024 << 28]
        var children: [Int32: [Int32]] = [:]
        var parent: Int32 = 0
        var lineage: Set<Int32> = [0]
        for level in 1 ... 14 {
            let kids = (0 ..< 4).map { Int32(4 * level - 3 + $0) }
            for kid in kids { weights[kid] = 1024 << (2 * (14 - level)) }
            children[parent] = kids
            parent = kids[0]
            lineage.insert(parent)
        }
        let (sizes, tree) = (weights, children)
        let source = TreemapRenderer.Source(
            weight: { sizes[$0] ?? 0 },
            children: { tree[$0] ?? [] },
            isLeaf: { tree[$0] == nil },
            color: { _ in TreemapRenderer.RGB(r: 0.5, g: 0.5, b: 0.5) },
            name: { "item \($0)" },
            sizeText: { _ in "" },
            isEmphasized: { _ in true }
        )
        return (source, lineage)
    }

    /// Invisível no mapa inteiro, o arquivo de 1 KB é localizado pelo caminho sem
    /// desenhar; um único voo até esse retângulo o mostra grande e no lugar certo.
    func testLocateAndMagnifyReachOneKilobyteFile() throws {
        let (source, lineage) = deepSource()
        let file: Int32 = 53
        XCTAssertEqual(source.weight(file), 1024)
        let full = try render(TreemapRenderer.fullViewport, source: source)
        XCTAssertNil(full.rects[file])
        let path = lineage.sorted().filter { $0 == 0 || $0 % 4 == 1 }
        XCTAssertEqual(path.last, file)
        let located = try XCTUnwrap(TreemapRenderer.locate(path, in: canvas, source: source))
        XCTAssertEqual(located.width * located.height, 400 * 200 * 1024 / Double(source.weight(0)), accuracy: 1e-9)

        var viewport = TreemapRenderer.viewport(fitting: unit(located), maxMagnification: 100_000_000)
        viewport.origin.x = min(max(0, viewport.minX), 1 - viewport.width)
        viewport.origin.y = min(max(0, viewport.minY), 1 - viewport.height)
        let magnified = try render(viewport, source: source)
        // Inteiro na tela com ~60% da altura (encostado na borda do mapa, não centraliza).
        let tile = try XCTUnwrap(magnified.rects[file])
        XCTAssertTrue(canvas.insetBy(dx: -0.001, dy: -0.001).contains(tile))
        XCTAssertGreaterThan(tile.height, 100)
        XCTAssertEqual(TreemapRenderer.hitTest(CGPoint(x: tile.midX, y: tile.midY), in: magnified, source: source), file)
    }

    /// Fatia fina (1 KB ao lado de 500 GB): amplia pela espessura, não pelo comprimento.
    func testThinSliverIsMagnifiedByItsThickness() throws {
        let disk: UInt64 = 500_000_000_000
        let source = source([0: disk, 1: disk - 1024, 2: 1024])
        let rect = try XCTUnwrap(TreemapRenderer.locate([0, 2], in: canvas, source: source))
        let viewport = TreemapRenderer.viewport(fitting: unit(rect), maxMagnification: .infinity)
        XCTAssertEqual(min(rect.width, rect.height) / 400 / viewport.width, 0.2, accuracy: 0.01)
    }

    /// A lupa é ampliação pura: um item desenhado no mapa inteiro e ampliado fica
    /// no mesmo lugar do mapa (coordenadas unitárias) — cabeçalhos e molduras que
    /// surgem ao ampliar não podem reorganizar os blocos.
    func testMagnifyingKeepsTheLayout() throws {
        let (source, _) = deepSource()
        let full = try render(TreemapRenderer.fullViewport, source: source)
        func unit(_ rect: CGRect, _ rendering: TreemapRenderer.Rendering) -> CGRect {
            let viewport = rendering.viewport
            return CGRect(x: viewport.minX + rect.minX / 400 * viewport.width,
                          y: viewport.minY + rect.minY / 200 * viewport.height,
                          width: rect.width / 400 * viewport.width, height: rect.height / 200 * viewport.height)
        }
        for magnification in [2.0, 8.0, 64.0] {
            let side = 1 / magnification
            let magnified = try render(CGRect(x: 0, y: 0, width: side, height: side), source: source)
            var compared = 0
            for (item, rect) in magnified.rects where item != 0 {
                guard let before = full.rects[item] else { continue }
                let a = unit(before, full), b = unit(rect, magnified)
                XCTAssertEqual(a.minX, b.minX, accuracy: 1e-9, "item \(item) a \(magnification)×")
                XCTAssertEqual(a.minY, b.minY, accuracy: 1e-9, "item \(item) a \(magnification)×")
                XCTAssertEqual(a.width, b.width, accuracy: 1e-9, "item \(item) a \(magnification)×")
                compared += 1
            }
            XCTAssertGreaterThan(compared, 3)
        }
    }

    /// Área do bloco proporcional ao tamanho, em qualquer ampliação.
    func testTileAreaIsProportionalToSize() throws {
        let (source, _) = deepSource()
        for side in [1.0, 1.0 / 16] {
            let rendering = try render(CGRect(x: 0, y: 0, width: side, height: side), source: source)
            let total = 400.0 * 200 / (side * side)
            for (item, rect) in rendering.rects where item != 0 {
                let expected = total * Double(source.weight(item)) / Double(source.weight(0))
                XCTAssertEqual(rect.width * rect.height, expected, accuracy: expected * 1e-6, "item \(item)")
            }
        }
    }

    /// A posição calculada pelo caminho é exatamente a desenhada.
    func testLocateMatchesRenderedRects() throws {
        let (source, lineage) = deepSource()
        let rendering = try render(TreemapRenderer.fullViewport, source: source)
        let path = lineage.sorted().filter { $0 == 0 || $0 % 4 == 1 }
        var checked = 0
        for end in 1 ... path.count {
            guard let drawn = rendering.rects[path[end - 1]] else { continue }
            let located = try XCTUnwrap(TreemapRenderer.locate(Array(path[..<end]), in: canvas, source: source))
            XCTAssertEqual(located, drawn)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 3)
        XCTAssertNil(TreemapRenderer.locate([0, 999], in: canvas, source: source))
    }

    /// Item de 0 KB não tem área: sem posição (antes caía no canto do mapa).
    func testLocateReturnsNilForZeroSizedItem() throws {
        let source = source([0: 100, 1: 100, 2: 0])
        XCTAssertNotNil(TreemapRenderer.locate([0, 1], in: canvas, source: source))
        XCTAssertNil(TreemapRenderer.locate([0, 2], in: canvas, source: source))
    }
}
