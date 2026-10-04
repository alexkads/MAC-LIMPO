import CoreGraphics
import Foundation

/// Port do treemap do WinDirStat (windirstat/Controls/TreeMap.cpp e
/// TreeMapLayout.cpp): layout "Rows" (o padrão), almofadas de van Wijk e o
/// mesmo sombreamento, paleta e normalização de cor. Constantes e fórmulas são
/// as da fonte; os comentários `// TreeMap.cpp` apontam a origem.
enum CushionTreemap {
    /// COLORREF: componentes 0...255.
    struct RGB: Sendable, Equatable, Hashable {
        let r: Int, g: Int, b: Int
    }

    /// Cor de gráfico de um item (CItem::GetGraphColor): RGB + flag opcional.
    struct GraphColor: Sendable, Equatable {
        enum Flag: Sendable { case none, darker, lighter }
        let rgb: RGB
        var flag: Flag = .none

        /// `<Free Space>`: RGB(100,100,100) | COLORFLAG_DARKER
        static let freeSpace = GraphColor(rgb: RGB(r: 100, g: 100, b: 100), flag: .darker)
        /// `<Unknown>`: RGB(255,255,0) | COLORFLAG_LIGHTER
        static let unknown = GraphColor(rgb: RGB(r: 255, g: 255, b: 0), flag: .lighter)
        /// Pastas: RGB(0,0,0) (nunca são folhas com área).
        static let black = GraphColor(rgb: RGB(r: 0, g: 0, b: 0))
    }

    /// PrepareRenderColor (saturação 1.0: sem mistura com cinza).
    static func prepare(_ color: GraphColor) -> (rgb: RGB, brightness: Double) {
        switch color.flag {
        case .none:
            return (color.rgb, brightness)
        case .darker:
            return (makeBrightColor(color.rgb, graphPaletteBrightness), brightness * 0.66)
        case .lighter:
            return (makeBrightColor(color.rgb, graphPaletteBrightness), min(brightness * 1.2, 1.0))
        }
    }

    /// Resultado de um render. `rects` está em pixels do bitmap.
    struct Rendering: @unchecked Sendable {
        let image: CGImage
        let pixelSize: CGSize
        let root: Int32
        /// Retângulo de cada item visível (AddVisibleItem).
        let rects: [Int32: CGRect]
    }

    // MARK: - Opções padrão (TreeMap.h, DefaultOptions)

    static let brightness = 0.88
    static let height = 0.38
    static let scaleFactor = 0.91
    static let ambientLight = 0.13
    static let lightSourceX = -1.0
    static let lightSourceY = -1.0
    /// CColorSpace::GraphPaletteBrightness
    static let graphPaletteBrightness = 0.6

    /// TreeMap.h, DefaultCushionColors.
    static let defaultCushionColors: [RGB] = [
        RGB(r: 0, g: 0, b: 255), // Blue
        RGB(r: 255, g: 0, b: 0), // Red
        RGB(r: 0, g: 255, b: 0), // Green
        RGB(r: 255, g: 255, b: 0), // Yellow
        RGB(r: 0, g: 255, b: 255), // Cyan
        RGB(r: 255, g: 0, b: 255), // Magenta
        RGB(r: 255, g: 170, b: 0), // Orange
        RGB(r: 0, g: 85, b: 255), // Dodger Blue
        RGB(r: 255, g: 0, b: 85), // Hot Pink
        RGB(r: 85, g: 255, b: 0), // Lime Green
        RGB(r: 170, g: 0, b: 255), // Violet
        RGB(r: 0, g: 255, b: 85), // Spring Green
        RGB(r: 255, g: 0, b: 170), // Deep Pink
        RGB(r: 0, g: 170, b: 255), // Sky Blue
        RGB(r: 255, g: 85, b: 0), // Orange Red
        RGB(r: 0, g: 255, b: 170), // Aquamarine
        RGB(r: 85, g: 0, b: 255), // Indigo
        RGB(r: 255, g: 255, b: 255) // White
    ]

    /// CTreeMap::GetDefaultPalette: cada cor com brilho 0.6.
    static let defaultPalette: [RGB] = defaultCushionColors.map { makeBrightColor($0, graphPaletteBrightness) }

    // MARK: - Cor (TreeMap.h, CColorSpace)

    /// CColorSpace::MakeBrightColor
    static func makeBrightColor(_ color: RGB, _ brightness: Double) -> RGB {
        var dred = Double(color.r & 0xFF) / 255
        var dgreen = Double(color.g & 0xFF) / 255
        var dblue = Double(color.b & 0xFF) / 255
        let f = 3.0 * brightness / (dred + dgreen + dblue)
        dred *= f
        dgreen *= f
        dblue *= f
        var red = Int(dred * 255), green = Int(dgreen * 255), blue = Int(dblue * 255)
        normalizeColor(&red, &green, &blue)
        return RGB(r: red, g: green, b: blue)
    }

    /// CColorSpace::NormalizeColor — leva o que passa de 255 para os outros canais.
    static func normalizeColor(_ red: inout Int, _ green: inout Int, _ blue: inout Int) {
        if red > 255 {
            distributeFirst(&red, &green, &blue)
        } else if green > 255 {
            distributeFirst(&green, &red, &blue)
        } else if blue > 255 {
            distributeFirst(&blue, &red, &green)
        }
    }

    /// CColorSpace::DistributeFirst
    private static func distributeFirst(_ first: inout Int, _ second: inout Int, _ third: inout Int) {
        let h = (first - 255) / 2
        first = 255
        second += h
        third += h
        if second > 255 {
            let j = second - 255
            second = 255
            third += j
        } else if third > 255 {
            let j = third - 255
            third = 255
            second += j
        }
    }

    /// TreeMap.cpp, MakeBitmapColor (usado por DrawSolidRect).
    static func makeBitmapColor(_ color: RGB, _ brightness: Double) -> RGB {
        let factor = brightness / graphPaletteBrightness
        var red = Int(Double(color.r) * factor)
        var green = Int(Double(color.g) * factor)
        var blue = Int(Double(color.b) * factor)
        normalizeColor(&red, &green, &blue)
        return RGB(r: red, g: green, b: blue)
    }

    // MARK: - Layout (TreeMapLayout.cpp)

    /// CRect do Windows: left/top inclusivos, right/bottom exclusivos.
    struct IntRect: Equatable {
        var left: Int, top: Int, right: Int, bottom: Int
        var width: Int { right - left }
        var height: Int { bottom - top }
        var isEmpty: Bool { width <= 0 || height <= 0 }
    }

    /// ArrangeEqualRows
    static func arrangeEqualRows(_ count: Int, bounds: IntRect) -> [IntRect] {
        let width = Double(bounds.width) / Double(count)
        var left = Double(bounds.left)
        var regions: [IntRect] = []
        for i in 0 ..< count {
            let next = left + width
            let right = i + 1 == count ? bounds.right : Int(next)
            regions.append(IntRect(left: Int(left), top: bounds.top, right: right, bottom: bounds.bottom))
            left = next
        }
        return regions
    }

    /// ArrangeRows — o estilo padrão (KDirStat). `weights` em ordem não
    /// crescente, zeros por último, somando `parentWeight`.
    static func arrangeRows(weights: [UInt64], parentWeight: UInt64, bounds: IntRect) -> [IntRect] {
        var regions = [IntRect](repeating: IntRect(left: 0, top: 0, right: 0, bottom: 0), count: weights.count)
        guard !weights.isEmpty, !bounds.isEmpty else { return regions }
        guard parentWeight > 0 else { return arrangeEqualRows(weights.count, bounds: bounds) }

        let minProportion = 0.4
        let horizontalRows = bounds.width >= bounds.height
        let normalizedWidth = horizontalRows
            ? Double(bounds.width) / Double(bounds.height)
            : Double(bounds.height) / Double(bounds.width)
        let rowOrigin = Double(horizontalRows ? bounds.top : bounds.left)
        let rowExtent = horizontalRows ? bounds.height : bounds.width
        let columnExtent = horizontalRows ? bounds.width : bounds.height

        var top = rowOrigin
        var rowBegin = 0
        while rowBegin < weights.count {
            var rowWeight: UInt64 = 0
            var rowFraction = 0.0
            var rowEnd = rowBegin
            while rowEnd < weights.count {
                let childWeight = weights[rowEnd]
                if childWeight == 0 { break }
                rowWeight += childWeight
                let candidateFraction = Double(rowWeight) / Double(parentWeight)
                let childWidth = Double(childWeight) / Double(parentWeight) * normalizedWidth / candidateFraction
                if childWidth / candidateFraction < minProportion {
                    rowWeight -= childWeight
                    break
                }
                rowFraction = candidateFraction
                rowEnd += 1
            }

            if rowEnd == rowBegin { return regions }
            while rowEnd < weights.count, weights[rowEnd] == 0 { rowEnd += 1 }

            let nextTop = top + rowFraction * Double(rowExtent)
            let bottom = rowEnd == weights.count
                ? (horizontalRows ? bounds.bottom : bounds.right)
                : Int(nextTop)
            var left = Double(horizontalRows ? bounds.left : bounds.top)
            for i in rowBegin ..< rowEnd {
                let nextLeft = left + Double(weights[i]) / Double(rowWeight) * Double(columnExtent)
                let lastChild = i + 1 == rowEnd || (i + 1 < weights.count && weights[i + 1] == 0)
                let right = lastChild
                    ? (horizontalRows ? bounds.right : bounds.bottom)
                    : Int(nextLeft)
                regions[i] = horizontalRows
                    ? IntRect(left: Int(left), top: Int(top), right: right, bottom: bottom)
                    : IntRect(left: Int(top), top: Int(left), right: bottom, bottom: right)
                left = nextLeft
            }

            top = nextTop
            rowBegin = rowEnd
        }
        return regions
    }

    // MARK: - Desenho (TreeMap.cpp, DrawTreeMap)

    /// Coeficientes da superfície (Surface = std::array<double, 4>).
    typealias Surface = (Double, Double, Double, Double)

    /// CTreeMap::AddRidge
    static func addRidge(_ rc: IntRect, _ surface: inout Surface, _ h: Double) {
        let h4 = 4 * h
        let wf = h4 / Double(rc.width)
        surface.2 += wf * Double(rc.right + rc.left)
        surface.0 -= wf
        let hf = h4 / Double(rc.height)
        surface.3 += hf * Double(rc.bottom + rc.top)
        surface.1 -= hf
    }

    /// Desenha o treemap de `root`. `color(item)` é a cor de gráfico do item
    /// (TmiGetGraphColor); `background` a cor de fundo da janela.
    static func render(
        index: DiskScanIndex,
        root: Int32,
        width: Int,
        height pixelHeight: Int,
        background: RGB,
        shadow: RGB,
        color: (Int32) -> GraphColor,
        isLeaf: (Int32) -> Bool,
        weight: (Int32) -> UInt64,
        children: (Int32) -> [Int32],
        isCancelled: () -> Bool
    ) -> Rendering? {
        guard width > 0, pixelHeight > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * pixelHeight * 4)
        var rects: [Int32: CGRect] = [:]

        let light = self.light

        let cancelled: Bool = pixels.withUnsafeMutableBufferPointer { bitmap in
            // DrawSolidRect(bitmap, whole, COLOR_WINDOW, GraphPaletteBrightness)
            let fill = makeBitmapColor(background, graphPaletteBrightness)
            for offset in stride(from: 0, to: bitmap.count, by: 4) {
                bitmap[offset] = UInt8(fill.r)
                bitmap[offset + 1] = UInt8(fill.g)
                bitmap[offset + 2] = UInt8(fill.b)
                bitmap[offset + 3] = 255
            }
            // PrepareRenderArea(drawOuterFrame: !grid): linha COLOR_3DSHADOW à
            // direita e embaixo, e a área útil encolhe 1 px.
            for y in 0 ..< pixelHeight { setPixel(bitmap, width: width, x: width - 1, y: y, shadow) }
            for x in 0 ..< width { setPixel(bitmap, width: width, x: x, y: pixelHeight - 1, shadow) }
            guard width > 1, pixelHeight > 1 else { return false }

            struct State {
                var surface: Surface
                var rc: IntRect
                var item: Int32
                var ridgeHeight: Double
                var asRoot: Bool
            }
            var stack: [State] = [State(
                surface: (0, 0, 0, 0),
                rc: IntRect(left: 0, top: 0, right: width - 1, bottom: pixelHeight - 1),
                item: root, ridgeHeight: height, asRoot: true
            )]
            var visited = 0

            while var state = stack.popLast() {
                visited += 1
                if visited % 50000 == 0, isCancelled() { return true }

                let item = state.item
                rects[item] = CGRect(
                    x: state.rc.left, y: state.rc.top, width: state.rc.width, height: state.rc.height
                )
                if state.rc.width <= 0 || state.rc.height <= 0 { continue }

                if !state.asRoot {
                    addRidge(state.rc, &state.surface, state.ridgeHeight)
                }

                if isLeaf(item) {
                    let prepared = prepare(color(item))
                    drawCushion(bitmap, width: width, rc: state.rc, surface: state.surface,
                                color: prepared.rgb, brightness: prepared.brightness, light: light)
                    continue
                }

                // pushChildren
                let kids = children(item)
                let weights = kids.map(weight)
                let parentWeight = weights.reduce(0, +)
                let regions = arrangeRows(weights: weights, parentWeight: parentWeight, bounds: state.rc)
                for (child, region) in zip(kids, regions) where !region.isEmpty {
                    stack.append(State(
                        surface: state.surface, rc: region, item: child,
                        ridgeHeight: state.ridgeHeight * scaleFactor, asRoot: false
                    ))
                }
            }
            return false
        }
        guard !cancelled else { return nil }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: width, height: pixelHeight, bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              )
        else { return nil }
        return Rendering(
            image: image, pixelSize: CGSize(width: width, height: pixelHeight), root: root, rects: rects
        )
    }

    /// CTreeMap::DrawCushion (cor já preparada; brilho = Options.brightness).
    private static func drawCushion(
        _ bitmap: UnsafeMutableBufferPointer<UInt8>,
        width: Int,
        rc: IntRect,
        surface: Surface,
        color: RGB,
        brightness: Double,
        light: (x: Double, y: Double, z: Double)
    ) {
        let ia = ambientLight
        let isLight = 1 - ia
        let brightnessFactor = brightness / graphPaletteBrightness
        let colR = Double(color.r), colG = Double(color.g), colB = Double(color.b)
        let nxStep = -2 * surface.0

        for iy in rc.top ..< rc.bottom {
            let ny = -(2 * surface.1 * (Double(iy) + 0.5) + surface.3)
            let nyLyLz = ny * light.y + light.z
            let ny2Plus1 = ny * ny + 1.0
            var nx = -(2 * surface.0 * (Double(rc.left) + 0.5) + surface.2)
            var offset = (iy * width + rc.left) * 4
            for _ in rc.left ..< rc.right {
                var cosa = (nx * light.x + nyLyLz) / (nx * nx + ny2Plus1).squareRoot()
                cosa = min(cosa, 1.0)
                var pixel = isLight * cosa
                pixel = max(pixel, 0.0)
                pixel += ia
                pixel *= brightnessFactor

                var red = Int(colR * pixel)
                var green = Int(colG * pixel)
                var blue = Int(colB * pixel)
                normalizeColor(&red, &green, &blue)
                bitmap[offset] = UInt8(clamping: red)
                bitmap[offset + 1] = UInt8(clamping: green)
                bitmap[offset + 2] = UInt8(clamping: blue)
                bitmap[offset + 3] = 255
                offset += 4
                nx += nxStep
            }
        }
    }

    private static func setPixel(_ bitmap: UnsafeMutableBufferPointer<UInt8>, width: Int, x: Int, y: Int, _ c: RGB) {
        let offset = (y * width + x) * 4
        bitmap[offset] = UInt8(clamping: c.r)
        bitmap[offset + 1] = UInt8(clamping: c.g)
        bitmap[offset + 2] = UInt8(clamping: c.b)
        bitmap[offset + 3] = 255
    }

    private static var light: (x: Double, y: Double, z: Double) {
        let length = (lightSourceX * lightSourceX + lightSourceY * lightSourceY + 100).squareRoot()
        return (lightSourceX / length, lightSourceY / length, 10 / length)
    }

    /// CTreeMap::DrawColorPreview: a amostra de cor da lista de extensões é uma
    /// almofada com ridge height·scaleFactor.
    static func colorPreview(_ color: GraphColor, width: Int, height pixelHeight: Int) -> CGImage? {
        guard width > 0, pixelHeight > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * pixelHeight * 4)
        let local = IntRect(left: 0, top: 0, right: width, bottom: pixelHeight)
        var surface: Surface = (0, 0, 0, 0)
        addRidge(local, &surface, height * scaleFactor)
        let prepared = prepare(color)
        pixels.withUnsafeMutableBufferPointer { bitmap in
            drawCushion(bitmap, width: width, rc: local, surface: surface,
                        color: prepared.rgb, brightness: prepared.brightness, light: light)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: pixelHeight, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    /// Item mais profundo visível sob o ponto (em pixels do bitmap).
    static func hitTest(
        _ point: CGPoint,
        in rendering: Rendering,
        isLeaf: (Int32) -> Bool,
        children: (Int32) -> [Int32]
    ) -> Int32? {
        guard rendering.rects[rendering.root]?.contains(point) == true else { return nil }
        var cursor = rendering.root
        outer: while !isLeaf(cursor) {
            for child in children(cursor) {
                if let rect = rendering.rects[child], rect.width > 0, rect.height > 0, rect.contains(point) {
                    cursor = child
                    continue outer
                }
            }
            break
        }
        return cursor
    }
}
