import XCTest
@testable import MAC_LIMPO

final class TreemapLayoutConsistencyTests: XCTestCase {
    /// Árvore pseudoaleatória (semente fixa): 3 níveis, pesos variados.
    private func source() -> TreemapRenderer.Source {
        var weights: [Int32: UInt64] = [:]
        var children: [Int32: [Int32]] = [:]
        var next: Int32 = 1
        var seed: UInt64 = 42
        func random(_ n: UInt64) -> UInt64 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return (seed >> 33) % n
        }
        func build(_ node: Int32, depth: Int) -> UInt64 {
            guard depth < 3 else {
                let w = 1 + random(1_000_000)
                weights[node] = w
                return w
            }
            var kids: [Int32] = []
            var total: UInt64 = 0
            for index in 0 ..< (3 + Int(random(25))) {
                let kid = next
                next += 1
                kids.append(kid)
                // Metade das folhas com tamanho idêntico (cópias, frameworks
                // repetidos): os empates que quebravam a caixa da seleção.
                if depth == 2, index % 2 == 0 {
                    weights[kid] = 4096
                    total += 4096
                } else {
                    total += build(kid, depth: depth + 1)
                }
            }
            kids.sort { weights[$0]! > weights[$1]! }
            children[node] = kids
            weights[node] = total
            return total
        }
        _ = build(0, depth: 0)
        let (w, c) = (weights, children)
        return TreemapRenderer.Source(
            weight: { w[$0] ?? 0 }, children: { c[$0] ?? [] }, isLeaf: { c[$0] == nil },
            color: { _ in TreemapRenderer.RGB(r: 0.5, g: 0.5, b: 0.5) }, name: { "\($0)" },
            sizeText: { _ in "" }, isEmphasized: { _ in true }
        )
    }

    private func lineage(_ item: Int32, _ source: TreemapRenderer.Source) -> [Int32]? {
        func walk(_ node: Int32, _ path: [Int32]) -> [Int32]? {
            if node == item { return path + [node] }
            for child in source.children(node) { if let found = walk(child, path + [node]) { return found } }
            return nil
        }
        return walk(0, [])
    }

    /// Com a lupa e a margem de arrasto (área arredondada para pixels inteiros,
    /// como em `startRender`), cada item desenhado fica onde `locate` diz.
    func testRenderedRectsMatchLocateWhenMagnifiedWithMargin() async throws {
        let source = source()
        let (width, height) = (1020, 285)
        var mismatches = 0
        _ = source
        var checked = 0
        // 0,5 em (0,25; 0,25): o caso do disco real (bitmap de 427,5 → 427 px).
        for (side, x, y) in [(0.5, 0.25, 0.25), (0.31, 0.12, 0.27), (0.137, 0.55, 0.41), (0.5, 0.0, 0.5),
                             (0.0731, 0.9269, 0.3)] {
            let visible = CGRect(x: x, y: y, width: side, height: side)
            let (area, areaWidth, areaHeight) = await DiskXRayViewModel.renderArea(visible: visible, width: width,
                                                                                   height: height, margin: 0.25)
            let style = TreemapRenderer.Style(scale: 2, dark: true, background: .black, cushions: false)
            let rendering = try XCTUnwrap(TreemapRenderer.render(root: 0, width: areaWidth, height: areaHeight, viewport: area,
                                                                 screen: visible, style: style, source: source,
                                                                 isCancelled: { false }))
            for (item, rect) in rendering.rects where item != 0 && rect.width > 20 && rect.height > 20 {
                let unit = CGRect(x: area.minX + rect.minX / CGFloat(areaWidth) * area.width,
                                  y: area.minY + rect.minY / CGFloat(areaHeight) * area.height,
                                  width: rect.width / CGFloat(areaWidth) * area.width,
                                  height: rect.height / CGFloat(areaHeight) * area.height)
                let path = try XCTUnwrap(lineage(item, source))
                let located = try XCTUnwrap(TreemapRenderer.locate(path, in: CGRect(x: 0, y: 0, width: width, height: height),
                                                                   source: source))
                let expected = CGRect(x: located.minX / CGFloat(width), y: located.minY / CGFloat(height),
                                      width: located.width / CGFloat(width), height: located.height / CGFloat(height))
                checked += 1
                // Tolerância: 1 pixel da tela nesse zoom.
                let tolerance = side / Double(width)
                if abs(unit.minX - expected.minX) > tolerance || abs(unit.minY - expected.minY) > tolerance * 4
                    || abs(unit.width - expected.width) > tolerance || abs(unit.height - expected.height) > tolerance * 4 {
                    mismatches += 1
                }
            }
        }
        XCTAssertGreaterThan(checked, 50)
        XCTAssertEqual(mismatches, 0, "\(mismatches) de \(checked) blocos fora do lugar calculado")
    }
}
