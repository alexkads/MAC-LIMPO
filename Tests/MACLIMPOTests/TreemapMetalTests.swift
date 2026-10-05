import XCTest
@testable import MAC_LIMPO

@MainActor
final class TreemapMetalTests: XCTestCase {
    private func source() -> TreemapRenderer.Source {
        let weights: [Int32: UInt64] = [0: 300, 1: 200, 2: 100]
        return TreemapRenderer.Source(
            weight: { weights[$0] ?? 0 },
            children: { $0 == 0 ? [1, 2] : [] },
            isLeaf: { $0 != 0 },
            color: { $0 == 1 ? TreemapRenderer.RGB(r: 1, g: 0, b: 0) : TreemapRenderer.RGB(r: 0, g: 0, b: 1) },
            name: { "item \($0)" },
            sizeText: { _ in "" },
            isEmphasized: { _ in true }
        )
    }

    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return (data[0], data[1], data[2])
    }

    /// Os shaders compilam (são compilados em tempo de execução) e a cena 3D sai
    /// na GPU com cada bloco na sua cor, iluminado.
    func testShadersCompileAndCushionSceneRenders() throws {
        let metal = try XCTUnwrap(TreemapMetal.shared, "Metal indisponível ou shader com erro")
        let style = TreemapRenderer.Style(scale: 1, dark: true, background: .black, cushions: true)
        let rendering = try XCTUnwrap(TreemapRenderer.render(root: 0, width: 300, height: 100, style: style,
                                                             source: source(), isCancelled: { false }))
        XCTAssertNil(rendering.image)
        XCTAssertTrue(rendering.shapes.contains { $0.params.w == 1 })
        let image = try XCTUnwrap(metal.image([.init(rendering: rendering, frame: CGRect(x: 0, y: 0, width: 300, height: 100))],
                                              background: .black, viewSize: CGSize(width: 300, height: 100), scale: 1))
        // Item 1 (vermelho, ⅔ da área) à esquerda; item 2 (azul) à direita.
        let left = pixel(image, 25, 75), right = pixel(image, 215, 22)
        XCTAssertGreaterThan(left.r, 150)
        XCTAssertLessThan(left.b, 60)
        XCTAssertGreaterThan(right.b, 150)
        XCTAssertLessThan(right.r, 60)
        // Relevo: o canto de cima à esquerda do bloco é mais claro que o de baixo à direita.
        let lit = pixel(image, 8, 8), shaded = pixel(image, 190, 92)
        XCTAssertGreaterThan(Int(lit.r), Int(shaded.r) + 20)
    }

    /// O 2D continua no CoreGraphics: um bitmap e nenhuma forma para a GPU.
    func testFlatSceneStaysOnCoreGraphics() throws {
        let style = TreemapRenderer.Style(scale: 1, dark: true, background: .black, cushions: false)
        let rendering = try XCTUnwrap(TreemapRenderer.render(root: 0, width: 300, height: 100, style: style,
                                                             source: source(), isCancelled: { false }))
        let image = try XCTUnwrap(rendering.image)
        XCTAssertTrue(rendering.shapes.isEmpty)
        XCTAssertGreaterThan(pixel(image, 100, 50).r, 150)
        XCTAssertGreaterThan(pixel(image, 250, 50).b, 150)
    }

    /// O botão Labels vale nos dois modos: ligado, o 3D leva os nomes (textura);
    /// desligado, nenhum texto — no 2D e no 3D.
    func testLabelsToggleControlsTextInBothModes() throws {
        func render(cushions: Bool, labels: Bool) throws -> TreemapRenderer.Rendering {
            let style = TreemapRenderer.Style(scale: 1, dark: true, background: .black, cushions: cushions, labels: labels)
            return try XCTUnwrap(TreemapRenderer.render(root: 0, width: 300, height: 100, style: style,
                                                        source: source(), isCancelled: { false }))
        }
        XCTAssertNotNil(try render(cushions: true, labels: true).labels)
        XCTAssertNil(try render(cushions: true, labels: false).labels)
        // 2D: os nomes vão no próprio bitmap — com e sem, as imagens diferem.
        let withText = try XCTUnwrap(render(cushions: false, labels: true).image)
        let without = try XCTUnwrap(render(cushions: false, labels: false).image)
        XCTAssertNotEqual(withText.dataProvider?.data as Data?, without.dataProvider?.data as Data?)
    }
}
