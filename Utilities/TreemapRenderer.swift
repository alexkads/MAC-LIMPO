// SPDX-License-Identifier: GPL-3.0-or-later
// MAC-LIMPO — Copyright (C) 2025-2026 Alex S S Fonseca and contributors.

import AppKit
import CoreGraphics
import CoreText

/// Treemap do Disk X-Ray: layout squarified (Bruls, Huizing & van Wijk, 2000),
/// pastas com espaçamento e cabeçalho, ladrilhos arredondados com gradiente e
/// rótulos nos blocos grandes. Monta a cena fora da thread principal: as formas
/// viram uma lista de `Shape` que a GPU desenha (`TreemapMetal`) e só os textos
/// são desenhados com CoreText numa imagem transparente por cima. O custo é
/// limitado pela área, não pelo número de arquivos (blocos menores que um pixel
/// não descem na hierarquia).
enum TreemapRenderer {
    struct RGB: Sendable, Equatable {
        var r: Double, g: Double, b: Double

        func mixed(with other: RGB, _ t: Double) -> RGB {
            RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
        }

        var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
        static let white = RGB(r: 1, g: 1, b: 1)
        static let black = RGB(r: 0, g: 0, b: 0)
    }

    /// Uma forma da cena, no layout do shader Metal (5 × float4 = 80 bytes):
    /// retângulo arredondado com gradiente vertical, ou contorno (`stroke` > 0),
    /// opcionalmente iluminado como almofada.
    /// Coordenadas em pixels da cena (origem no canto superior esquerdo), sempre
    /// perto da área desenhada — cabem em Float mesmo na lupa funda.
    struct Shape {
        var rect: SIMD4<Float>
        /// Cor (RGBA, sRGB) na borda de cima e na de baixo.
        var top: SIMD4<Float>
        var bottom: SIMD4<Float>
        /// Raio dos cantos de cima, raio dos de baixo, espessura do contorno (0 =
        /// preenchido), iluminação (1 = almofada).
        var params: SIMD4<Float>
        /// Inclinação da almofada: gx na borda esquerda, dgx/dx, gy no topo, dgy/dy
        /// (por pixel da cena). Calculada em Double, relativa à forma — cabe em Float.
        var cushion: SIMD4<Float> = .zero
    }

    /// Superfície de almofadas (van Wijk & van de Wetering, 1999): cada nível
    /// soma uma parábola em x e em y sobre o retângulo dele, e a luz sobre a soma
    /// mostra a hierarquia — vincos entre pastas, relevo em cada arquivo. A
    /// inclinação nas bordas é ±4h, qualquer que seja o tamanho: o relevo é o
    /// mesmo em qualquer ampliação.
    struct Cushion {
        var s1x = 0.0, s2x = 0.0, s1y = 0.0, s2y = 0.0

        /// Altura do relevo no nível `depth` (cai a cada nível, como no WinDirStat).
        static func height(depth: Int) -> Double { 0.36 * pow(0.86, Double(depth)) }

        func adding(_ rect: CGRect, height h: Double) -> Cushion {
            guard rect.width > 0, rect.height > 0 else { return self }
            var next = self
            next.s1x += 4 * h * Double(rect.maxX + rect.minX) / Double(rect.width)
            next.s2x -= 4 * h / Double(rect.width)
            next.s1y += 4 * h * Double(rect.maxY + rect.minY) / Double(rect.height)
            next.s2y -= 4 * h / Double(rect.height)
            return next
        }

        /// Inclinação na borda de cima/esquerda de `rect` e quanto ela muda por pixel.
        func slopes(at rect: CGRect) -> SIMD4<Float> {
            SIMD4(Float(2 * s2x * Double(rect.minX) + s1x), Float(2 * s2x),
                  Float(2 * s2y * Double(rect.minY) + s1y), Float(2 * s2y))
        }
    }

    struct Rendering: @unchecked Sendable, Identifiable {
        let id = UUID()
        /// 3D: formas em ordem de desenho (a GPU respeita a ordem) e só os textos,
        /// em fundo transparente, do tamanho da cena.
        let shapes: [Shape]
        let labels: CGImage?
        /// 2D: a cena inteira num bitmap (CoreGraphics), como sempre foi.
        let image: CGImage?
        let pixelSize: CGSize
        /// Pixels por ponto com que foi desenhado (a tela pode mudar depois).
        let scale: CGFloat
        let root: Int32
        /// Parte do mapa inteiro que o bitmap mostra (coordenadas unitárias, ver `render`).
        let viewport: CGRect
        /// Retângulo de cada item desenhado, em pixels do bitmap.
        let rects: [Int32: CGRect]
        /// Faixas de cabeçalho (sobrepostas aos filhos): clicar nelas é a pasta.
        let headers: [Int32: CGRect]
    }

    /// O que o renderizador precisa saber de cada item. As closures são
    /// `@Sendable` de propósito: criadas no MainActor, sem isso herdariam o
    /// isolamento dele e o runtime abortaria ao chamá-las na thread do render.
    /// O índice não muda durante o render (a Lixeira espera o render acabar).
    struct Source: Sendable {
        let weight: @Sendable (Int32) -> UInt64
        /// Filhos em ordem decrescente de peso.
        let children: @Sendable (Int32) -> [Int32]
        let isLeaf: @Sendable (Int32) -> Bool
        let color: @Sendable (Int32) -> RGB
        let name: @Sendable (Int32) -> String
        let sizeText: @Sendable (Int32) -> String
        /// `false` esmaece o item (categoria/extensão em destaque).
        let isEmphasized: @Sendable (Int32) -> Bool
    }

    struct Style {
        var scale: CGFloat
        var dark: Bool
        var background: RGB
        /// Relevo de almofadas (3D); desligado, os blocos levam o gradiente plano.
        var cushions = true
        /// Nomes nos blocos e faixas de cabeçalho das pastas (2D e 3D).
        var labels = true
    }

    /// Mapa inteiro em coordenadas unitárias (0…1 nos dois eixos).
    static let fullViewport = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// `viewport`: parte do mapa inteiro a desenhar no bitmap, em coordenadas
    /// unitárias. Menor que o mapa inteiro é a lupa (pinça): o layout é feito
    /// num canvas virtual ampliado e só o que cai no bitmap é desenhado, então
    /// arquivos que ocupavam menos de um pixel ganham bloco e rótulo.
    /// `screen`: parte do `viewport` que está na tela (o resto é margem para
    /// arrastar); rótulos de blocos que aparecem nela ficam na parte visível.
    static func render(
        root: Int32,
        width: Int,
        height: Int,
        viewport: CGRect = fullViewport,
        screen: CGRect? = nil,
        style: Style,
        source: Source,
        isCancelled: @escaping () -> Bool
    ) -> Rendering? {
        // Só os textos vão para o bitmap (transparente); as formas, para a lista.
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        // Origem no canto superior esquerdo, como a tela.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let fullWidth = CGFloat(width) / viewport.width
        let fullHeight = CGFloat(height) / viewport.height
        let canvas = CGRect(x: -viewport.minX * fullWidth, y: -viewport.minY * fullHeight, width: fullWidth, height: fullHeight)
        let labelArea = screen.map { screen in
            CGRect(x: (screen.minX - viewport.minX) / viewport.width * CGFloat(width),
                   y: (screen.minY - viewport.minY) / viewport.height * CGFloat(height),
                   width: screen.width / viewport.width * CGFloat(width),
                   height: screen.height / viewport.height * CGFloat(height)).intersection(bounds)
        } ?? bounds
        var painter = Painter(context: context, style: style, visible: bounds, labelArea: labelArea,
                              magnification: 1 / viewport.width, source: source, isCancelled: isCancelled)
        // Fundo da cena inteira: cada camada cobre as de baixo na área dela.
        painter.fill(bounds, color: style.background, radius: 0)
        painter.draw(root, in: canvas, depth: 0, path: [])
        guard !painter.cancelled else { return nil }
        let labels = painter.hasText ? context.makeImage() : nil
        if !style.cushions {
            // 2D: as mesmas formas desenhadas com CoreGraphics, textos por cima.
            guard let image = rasterize(painter.shapes, labels: labels, width: width, height: height) else { return nil }
            return Rendering(shapes: [], labels: nil, image: image, pixelSize: bounds.size, scale: style.scale,
                             root: root, viewport: viewport, rects: painter.rects, headers: painter.headers)
        }
        return Rendering(shapes: painter.shapes, labels: labels, image: nil,
                         pixelSize: bounds.size, scale: style.scale,
                         root: root, viewport: viewport, rects: painter.rects,
                         headers: painter.headers)
    }

    /// Desenha as formas num bitmap com CoreGraphics (o modo 2D): retângulos
    /// arredondados com gradiente vertical e contornos, na ordem da lista.
    static func rasterize(_ shapes: [Shape], labels: CGImage?, width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        func color(_ value: SIMD4<Float>) -> CGColor {
            CGColor(srgbRed: CGFloat(value.x), green: CGFloat(value.y), blue: CGFloat(value.z), alpha: CGFloat(value.w))
        }
        for shape in shapes {
            let rect = CGRect(x: CGFloat(shape.rect.x), y: CGFloat(shape.rect.y),
                              width: CGFloat(shape.rect.z), height: CGFloat(shape.rect.w))
            let stroke = CGFloat(shape.params.z)
            if stroke > 0 {
                // Anel por dentro da borda: traço no meio dele.
                let ring = rect.insetBy(dx: stroke / 2, dy: stroke / 2)
                guard ring.width > 0, ring.height > 0 else { continue }
                let radius = max(0, min(CGFloat(shape.params.x) - stroke / 2, ring.width / 2, ring.height / 2))
                context.setStrokeColor(color(shape.top))
                context.setLineWidth(stroke)
                context.addPath(CGPath(roundedRect: ring, cornerWidth: radius, cornerHeight: radius, transform: nil))
                context.strokePath()
                continue
            }
            let path = roundedPath(rect, top: CGFloat(shape.params.x), bottom: CGFloat(shape.params.y))
            if shape.top == shape.bottom {
                context.setFillColor(color(shape.top))
                context.addPath(path)
                context.fillPath()
            } else if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                                colors: [color(shape.top), color(shape.bottom)] as CFArray,
                                                locations: [0, 1]) {
                context.saveGState()
                context.addPath(path)
                context.clip()
                context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY),
                                           end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
                context.restoreGState()
            }
        }
        if let labels {
            // O bitmap dos textos já está de cima para baixo; desenha sem a inversão.
            context.saveGState()
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: 0, y: -CGFloat(height))
            context.draw(labels, in: CGRect(x: 0, y: 0, width: width, height: height))
            context.restoreGState()
        }
        return context.makeImage()
    }

    /// Retângulo com raio próprio nos cantos de cima e nos de baixo.
    private static func roundedPath(_ rect: CGRect, top: CGFloat, bottom: CGFloat) -> CGPath {
        let limit = min(rect.width, rect.height) / 2
        let (top, bottom) = (max(0, min(top, limit)), max(0, min(bottom, limit)))
        if top == bottom {
            return top < 0.01 ? CGPath(rect: rect, transform: nil)
                : CGPath(roundedRect: rect, cornerWidth: top, cornerHeight: top, transform: nil)
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + top))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: top)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: top)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY),
                    radius: bottom)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY),
                    radius: bottom)
        path.closeSubpath()
        return path
    }

    /// Retângulo do último item de `path` (da raiz do mapa até ele) num mapa
    /// desenhado em `canvas`. O layout é só o squarified dos tamanhos, igual em
    /// qualquer ampliação, então dá para descer pelo caminho sem desenhar nada —
    /// vale para itens fora da tela ou menores que um pixel. `nil` para um item de
    /// tamanho zero: ele não tem área no mapa (o squarified nem o posiciona).
    static func locate(_ path: [Int32], in canvas: CGRect, source: Source) -> CGRect? {
        guard !path.isEmpty else { return nil }
        var rect = canvas
        for (parent, child) in zip(path, path.dropFirst()) {
            let children = source.children(parent)
            guard source.weight(child) > 0, let position = children.firstIndex(of: child) else { return nil }
            rect = squarify(weights: children.map { Double(source.weight($0)) }, in: rect)[position]
        }
        return rect
    }

    /// Viewport em que `unit` (coordenadas unitárias) aparece centrado com o lado
    /// maior ocupando `fill` da tela. Fatias finas (um arquivo pequeno ao lado de
    /// um enorme) ficariam invisíveis inteiras: a espessura nunca fica abaixo de
    /// `minThickness` da tela, e o comprimento passa das bordas. Pode sair do
    /// mapa — o chamador limita.
    static func viewport(fitting unit: CGRect, fill: CGFloat = 0.6, minThickness: CGFloat = 0.2,
                         maxMagnification: CGFloat) -> CGRect {
        let fit = max(unit.width, unit.height) / fill
        let thick = min(unit.width, unit.height) / minThickness
        let side = min(1, max(1 / maxMagnification, min(fit, thick)))
        return CGRect(x: unit.midX - side / 2, y: unit.midY - side / 2, width: side, height: side)
    }

    /// Item mais profundo sob o ponto (em pixels do bitmap).
    static func hitTest(_ point: CGPoint, in rendering: Rendering, source: Source) -> Int32? {
        guard rendering.rects[rendering.root]?.contains(point) == true else { return nil }
        var cursor = rendering.root
        outer: while !source.isLeaf(cursor) {
            if rendering.headers[cursor]?.contains(point) == true { break }
            for child in source.children(cursor) {
                if let rect = rendering.rects[child], rect.contains(point) {
                    cursor = child
                    continue outer
                }
            }
            break
        }
        return cursor
    }

    // MARK: - Layout squarified

    /// Distribui `weights` (decrescentes) em `rect` com proporções próximas de 1.
    static func squarify(weights: [Double], in rect: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: weights.count)
        let total = weights.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }

        var remaining = rect
        var remainingWeight = total
        var start = 0
        // Tolerância nos empates (arquivos de tamanho idêntico são comuns): sem ela
        // a decisão ficava no último bit do ponto flutuante e mudava com a escala —
        // a lupa e a caixa da seleção (`locate`) viam arrumações diferentes.
        let tie = 1e-9
        while start < weights.count, remainingWeight > 0 {
            let horizontal = remaining.width >= remaining.height * (1 - tie)
            let side = Double(horizontal ? remaining.height : remaining.width)
            let scale = Double(remaining.width * remaining.height) / remainingWeight

            var end = start
            var rowWeight = 0.0
            var worst = Double.infinity
            while end < weights.count {
                let candidate = rowWeight + weights[end]
                let rowArea = candidate * scale
                let largest = weights[start] * scale
                let smallest = max(weights[end] * scale, .leastNonzeroMagnitude)
                let ratio = max(side * side * largest / (rowArea * rowArea), rowArea * rowArea / (side * side * smallest))
                if ratio > worst * (1 + tie), end > start { break }
                worst = ratio
                rowWeight = candidate
                end += 1
            }

            let thickness = CGFloat(rowWeight * scale / side)
            var offset: CGFloat = 0
            for i in start ..< end {
                let length = CGFloat(weights[i] / rowWeight) * CGFloat(side)
                result[i] = horizontal
                    ? CGRect(x: remaining.minX, y: remaining.minY + offset, width: thickness, height: length)
                    : CGRect(x: remaining.minX + offset, y: remaining.minY, width: length, height: thickness)
                offset += length
            }
            if horizontal {
                remaining.origin.x += thickness
                remaining.size.width -= thickness
            } else {
                remaining.origin.y += thickness
                remaining.size.height -= thickness
            }
            remainingWeight -= rowWeight
            start = end
        }
        return result
    }

    // MARK: - Desenho

    private struct Painter {
        let context: CGContext
        let style: Style
        /// Área do bitmap: com a lupa o canvas é maior e o que cai fora é pulado.
        let visible: CGRect
        /// Parte do bitmap que está na tela (sem a margem de arrasto).
        let labelArea: CGRect
        let source: Source
        let isCancelled: () -> Bool
        var rects: [Int32: CGRect] = [:]
        /// Faixa do cabeçalho de cada pasta (sobreposta aos filhos).
        var headers: [Int32: CGRect] = [:]
        var shapes: [Shape] = []
        var hasText = false
        var cancelled = false
        private var visits = 0

        private let headerFont: CTFont
        private let pathFont: CTFont
        private let headerSizeFont: CTFont
        private let tileFont: CTFont
        private let tileSizeFont: CTFont

        /// Uma pasta cujo maior filho tem ao menos esta fração do tamanho não ganha
        /// cabeçalho próprio: ela entra no caminho do filho ("Users › alexkads").
        private static let dominance = 0.9
        /// Níveis de pasta (a partir da raiz do zoom) que ganham cabeçalho. Mais
        /// fundo que isso os títulos viram uma escada de texto; o caminho completo
        /// está na barra de status e na árvore. A lupa libera um nível a cada 2×.
        private static let headerDepth = 3
        private let headerDepth: Int

        init(context: CGContext, style: Style, visible: CGRect, labelArea: CGRect, magnification: CGFloat,
             source: Source, isCancelled: @escaping () -> Bool) {
            self.context = context
            self.style = style
            self.visible = visible
            self.labelArea = labelArea
            headerDepth = Self.headerDepth + Int(log2(max(1, magnification)))
            self.source = source
            self.isCancelled = isCancelled
            let s = style.scale
            headerFont = .system(size: 10.5 * s, weight: .semibold)
            pathFont = .system(size: 10.5 * s, weight: .regular)
            headerSizeFont = .system(size: 10 * s, weight: .regular, monospacedDigits: true)
            tileFont = .system(size: 11 * s, weight: .semibold)
            tileSizeFont = .system(size: 10 * s, weight: .regular, monospacedDigits: true)
        }

        private var s: CGFloat { style.scale }

        /// `path`: pastas acima que não ganharam cabeçalho por terem um filho só
        /// ou dominante — a cadeia vira um cabeçalho ("Library › Containers › Data").
        /// `labelTop`: base do cabeçalho de um ancestral que cobre o topo deste
        /// item — rótulos e cabeçalhos começam abaixo dele. `stacked`: quantos
        /// cabeçalhos já estão empilhados ali (pastas aninhadas com o mesmo topo).
        ///
        /// O layout é só o squarified dos tamanhos: moldura e cabeçalho são
        /// desenhados por cima dos filhos, não recortados da área deles. Se fossem
        /// recortados (medidos em pixels da tela), cada ampliação os mudaria e os
        /// blocos se reorganizariam — a lupa mostraria outro mapa, e a área deixaria
        /// de ser proporcional ao tamanho.
        mutating func draw(_ item: Int32, in rect: CGRect, depth: Int, path: [String],
                           labelTop: CGFloat = -.infinity, stacked: Int = 0, cushion: Cushion = Cushion()) {
            guard !cancelled, rect.width >= 0.5, rect.height >= 0.5, rect.intersects(visible) else { return }
            visits += 1
            if visits % 20000 == 0, isCancelled() {
                cancelled = true
                return
            }
            rects[item] = rect

            let leaf = source.isLeaf(item)
            // Pasta pequena demais para mostrar o conteúdo: pinta com a cor do
            // maior descendente (o que mais pesa ali dentro).
            if leaf || rect.width < 4 * s || rect.height < 4 * s {
                tile(item, rect: rect, colorItem: leaf ? item : dominantLeaf(of: item), labeled: leaf, labelTop: labelTop,
                     cushion: cushion.adding(rect, height: Cushion.height(depth: depth + 1)))
                return
            }
            // A pasta soma o relevo dela ao dos filhos.
            let inner = depth > 0 ? cushion.adding(rect, height: Cushion.height(depth: depth)) : cushion

            let children = source.children(item)
            let weights = children.map { Double(source.weight($0)) }
            let layout = TreemapRenderer.squarify(weights: weights, in: rect)
            let total = weights.reduce(0, +)
            if depth > 0, let largest = weights.first, total > 0, largest / total >= Self.dominance {
                // Filho único ou dominante: sem moldura nem título aqui; o maior
                // filho herda a posição e o caminho. Os irmãos pequenos ficam ao
                // lado dele, como em qualquer outra pasta.
                let chain = path + [source.name(item)]
                fillTail(children, layout: layout, weights: weights, in: rect, labelTop: labelTop, cushion: inner)
                for (offset, (child, childRect)) in zip(children, layout).enumerated() {
                    if offset == 0 {
                        draw(child, in: childRect, depth: depth, path: chain,
                             labelTop: labelTop, stacked: stacked, cushion: cushion)
                    } else {
                        draw(child, in: childRect, depth: depth + 1, path: [],
                             labelTop: labelTop, stacked: stacked, cushion: inner)
                    }
                    if cancelled { return }
                }
                return
            }

            // Moldura só onde ela ajuda a ler a hierarquia: pastas grandes e rasas.
            // Medida na tela, mas por cima dos filhos — não muda o layout.
            var padding: CGFloat = 0
            var band: CGRect?
            let covered = labelTop > rect.minY
            if depth > 0 {
                padding = folderPadding(rect, depth: depth)
                // A pasta maior vem primeiro no canto superior esquerdo, então pastas
                // aninhadas dividem o topo: no máximo dois cabeçalhos empilhados, ou
                // na lupa funda a escada cobriria a tela.
                if style.labels, depth <= headerDepth, rect.width >= 90 * s, rect.height >= 60 * s,
                   !covered || stacked < 2 {
                    // Logo abaixo do cabeçalho de um ancestral que cubra o topo.
                    let top = max(rect.minY, labelTop)
                    let height = 15 * s + padding
                    if top + height + 30 * s <= rect.maxY {
                        band = CGRect(x: rect.minX, y: top, width: rect.width, height: height)
                    }
                }
                if padding > 0 || band != nil { folderBackground(rect) }
            }

            let childTop = band.map { max(labelTop, $0.maxY) } ?? labelTop
            let childStacked = band == nil ? stacked : (covered ? stacked + 1 : 1)
            fillTail(children, layout: layout, weights: weights, in: rect, labelTop: childTop, cushion: inner)
            for (child, childRect) in zip(children, layout) {
                draw(child, in: childRect, depth: depth + 1, path: [],
                     labelTop: childTop, stacked: childStacked, cushion: inner)
                if cancelled { return }
            }

            if padding > 0 { folderFrame(rect, width: padding) }
            if let band {
                headers[item] = band
                folderHeader(item, path: path, folder: rect, band: band)
            }
        }

        /// Filhos menores que meio pixel não são desenhados; numa pasta com
        /// milhares deles (node_modules, caches, .git/objects) a área que ocupam
        /// ficava vazia — uma caixa da cor do fundo no meio do mapa. O squarified
        /// os deixa juntos no fim (pesos decrescentes): essa área é pintada antes
        /// dos filhos visíveis, com a cor do maior deles.
        private mutating func fillTail(_ children: [Int32], layout: [CGRect], weights: [Double], in rect: CGRect,
                                       labelTop: CGFloat, cushion: Cushion) {
            var tail = CGRect.null
            var first: Int32?
            for (index, childRect) in layout.enumerated() where weights[index] > 0 {
                guard childRect.width < 0.5 || childRect.height < 0.5 else { continue }
                tail = tail.union(childRect)
                if first == nil { first = children[index] }
            }
            let area = tail.intersection(rect).intersection(visible)
            guard let first, !area.isNull, area.width * area.height >= 0.5 else { return }
            let colorItem = source.isLeaf(first) ? first : dominantLeaf(of: first)
            tile(first, rect: tail.intersection(rect), colorItem: colorItem, labeled: false, labelTop: labelTop,
                 cushion: cushion.adding(tail, height: Cushion.height(depth: 8)))
        }

        /// Recuo da moldura: some em pastas pequenas e diminui com a profundidade.
        private func folderPadding(_ rect: CGRect, depth: Int) -> CGFloat {
            let side = min(rect.width, rect.height)
            guard side >= 36 * s else { return 0 }
            switch depth {
            case 1: return 2.5 * s
            case 2: return 1.5 * s
            case 3, 4: return side >= 80 * s ? 1 * s : 0
            default: return 0
            }
        }

        /// Parte do retângulo perto da tela. Com a lupa funda um bloco passa de
        /// bilhões de pixels e o CoreGraphics rasteriza em precisão simples: só
        /// isto vai para o contexto. A folga deixa os cantos arredondados recortados
        /// fora da tela.
        private func nearScreen(_ rect: CGRect) -> CGRect {
            rect.intersection(visible.insetBy(dx: -8 * s, dy: -8 * s))
        }

        /// Onde o rótulo pode ir: a parte na tela, se o bloco aparece nela; senão
        /// a margem (para já estar certo quando for arrastado para dentro).
        private func labelRegion(for rect: CGRect) -> CGRect {
            rect.intersects(labelArea) ? labelArea : visible
        }

        private func dominantLeaf(of item: Int32) -> Int32 {
            var cursor = item
            while !source.isLeaf(cursor), let largest = source.children(cursor).first {
                cursor = largest
            }
            return cursor
        }

        // MARK: Formas

        mutating func fill(_ rect: CGRect, color: RGB, radius: CGFloat) {
            shape(rect, top: color, bottom: color, radiusTop: radius, radiusBottom: radius)
        }

        mutating func shape(_ rect: CGRect, top: RGB, bottom: RGB, radiusTop: CGFloat, radiusBottom: CGFloat,
                            stroke: CGFloat = 0) {
            guard rect.width > 0, rect.height > 0 else { return }
            func rgba(_ color: RGB) -> SIMD4<Float> { SIMD4(Float(color.r), Float(color.g), Float(color.b), 1) }
            shapes.append(Shape(
                rect: SIMD4(Float(rect.minX), Float(rect.minY), Float(rect.width), Float(rect.height)),
                top: rgba(top), bottom: rgba(bottom),
                params: SIMD4(Float(radiusTop), Float(radiusBottom), Float(stroke), 0)
            ))
        }

        private mutating func folderBackground(_ rect: CGRect) {
            let box = nearScreen(rect.insetBy(dx: 0.5 * s, dy: 0.5 * s))
            guard !box.isNull else { return }
            fill(box, color: folderTone, radius: min(5 * s, box.width / 4, box.height / 4))
        }

        private var folderTone: RGB {
            style.background.mixed(with: style.dark ? .white : .black, style.dark ? 0.07 : 0.05)
        }

        /// Contorno da pasta no tom do fundo dela, por cima das bordas dos filhos:
        /// faz o papel do antigo recuo sem mexer no layout.
        private mutating func folderFrame(_ rect: CGRect, width: CGFloat) {
            // Anel de `width` por dentro da borda (a meio ponto dela).
            let outer = nearScreen(rect.insetBy(dx: 0.5 * s, dy: 0.5 * s))
            guard !outer.isNull, outer.width > 0, outer.height > 0 else { return }
            let radius = min(5 * s + width / 2, outer.width / 4, outer.height / 4)
            shape(outer, top: folderTone, bottom: folderTone, radiusTop: radius, radiusBottom: radius, stroke: width)
        }

        /// Faixa do cabeçalho por cima do topo da pasta: nome à esquerda (as pastas
        /// do caminho em cinza, a pasta em destaque) e tamanho alinhado à direita.
        /// Sem espaço, o tamanho sai antes de o nome ser cortado; num caminho o
        /// corte é no começo, para manter a pasta final.
        private mutating func folderHeader(_ item: Int32, path: [String], folder rect: CGRect, band: CGRect) {
            // Com a lupa a pasta pode passar das bordas: o título acompanha a parte visível.
            let span = band.intersection(labelRegion(for: band))
            guard !span.isNull, span.height > 0 else { return }
            let outline = rect.insetBy(dx: 0.5 * s, dy: 0.5 * s)
            // Faixa dentro do contorno arredondado da pasta: cantos de cima
            // arredondados só quando ela começa no topo da pasta.
            let strip = nearScreen(CGRect(x: outline.minX, y: max(band.minY, outline.minY), width: outline.width,
                                          height: band.maxY - max(band.minY, outline.minY)))
            guard !strip.isNull else { return }
            let atTop = band.minY <= outline.minY && strip.minY == max(band.minY, outline.minY)
            fill(strip, color: folderTone, radius: 0)
            if atTop {
                shapes[shapes.count - 1].params.x = Float(min(5 * s, outline.width / 4, outline.height / 4))
            }

            let area = CGRect(x: span.minX + 6 * s, y: band.minY + 1.5 * s, width: span.width - 12 * s, height: 13.5 * s)
            guard area.width > 8 * s else { return }
            hasText = true

            let primary = style.dark ? CGColor(gray: 1, alpha: 0.88) : CGColor(gray: 0, alpha: 0.82)
            let secondary = style.dark ? CGColor(gray: 1, alpha: 0.5) : CGColor(gray: 0, alpha: 0.45)

            let title = NSMutableAttributedString()
            for folder in path {
                title.append(attributed(folder + " › ", font: pathFont, color: secondary))
            }
            title.append(attributed(source.name(item), font: headerFont, color: primary))
            let titleLine = CTLineCreateWithAttributedString(title)
            let sizeLine = CTLineCreateWithAttributedString(attributed(source.sizeText(item), font: headerSizeFont, color: secondary))
            let titleWidth = width(of: titleLine)
            let sizeWidth = width(of: sizeLine)

            var titleSpace = area.width
            let spacing = 8 * s
            if area.width - sizeWidth - spacing >= min(titleWidth, 56 * s) {
                titleSpace -= sizeWidth + spacing
                draw(sizeLine, at: area.maxX - sizeWidth, in: area, font: headerFont, shadow: false)
            }
            let token = CTLineCreateWithAttributedString(attributed("…", font: headerFont, color: path.isEmpty ? primary : secondary))
            guard let fitted = CTLineCreateTruncatedLine(titleLine, Double(titleSpace), path.isEmpty ? .end : .start, token)
            else { return }
            draw(fitted, at: area.minX, in: area, font: headerFont, shadow: false)
        }

        private mutating func tile(_ item: Int32, rect: CGRect, colorItem: Int32, labeled: Bool, labelTop: CGFloat,
                                   cushion: Cushion) {
            var base = source.color(colorItem)
            if !source.isEmphasized(colorItem) {
                base = base.mixed(with: style.background, 0.78)
            }
            // Folga de meio ponto só em blocos que a comportam; abaixo disso ela
            // vira o espaço vazio entre arquivos pequenos.
            let gap = rect.width >= 8 * s && rect.height >= 8 * s ? 0.5 * s : 0
            let box = rect.insetBy(dx: gap, dy: gap)
            guard box.width > 0, box.height > 0 else { return }
            let near = nearScreen(box)
            guard !near.isNull else { return }

            let side = min(box.width, box.height)
            // Raio ≤ metade do lado — vale também para o recorte.
            let radius = side >= 12 * s ? min(4 * s, side / 5, min(near.width, near.height) / 2) : 0
            if style.cushions {
                // A luz da almofada faz o relevo (no shader); a cor é a do tipo.
                fill(near, color: base, radius: radius >= 1 ? radius : 0)
                shapes[shapes.count - 1].params.w = 1
                shapes[shapes.count - 1].cushion = cushion.slopes(at: near)
            } else if box.width * box.height >= 600 * s * s {
                // Gradiente vertical: topo mais claro, base levemente mais escura.
                // Recortado perto da tela, as pontas pegam a cor daquela altura.
                let top = base.mixed(with: .white, style.dark ? 0.12 : 0.22)
                let bottom = base.mixed(with: .black, style.dark ? 0.18 : 0.08)
                shape(near, top: top.mixed(with: bottom, (near.minY - box.minY) / box.height),
                      bottom: top.mixed(with: bottom, (near.maxY - box.minY) / box.height),
                      radiusTop: radius, radiusBottom: radius)
            } else {
                fill(near, color: base, radius: radius >= 1 ? radius : 0)
            }

            // Rótulo no canto visível do bloco (com a lupa o bloco pode passar da tela).
            // Abaixo do cabeçalho de uma pasta que cubra o topo do bloco.
            var shown = box.intersection(labelRegion(for: box))
            if !shown.isNull, labelTop > shown.minY {
                shown.size.height = max(0, shown.maxY - labelTop)
                shown.origin.y = labelTop
            }
            if style.labels, labeled, !shown.isNull, shown.width >= 64 * s, shown.height >= 30 * s {
                hasText = true
                let inset = shown.insetBy(dx: 6 * s, dy: 5 * s)
                text(source.name(item), in: CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: 14 * s),
                     font: tileFont, color: CGColor(gray: 1, alpha: 0.96))
                if shown.height >= 44 * s {
                    text(source.sizeText(item), in: CGRect(x: inset.minX, y: inset.minY + 14.5 * s, width: inset.width, height: 13 * s),
                         font: tileSizeFont, color: CGColor(gray: 1, alpha: 0.82))
                }
            }
        }

        /// Rótulo sobre um bloco colorido: uma linha, cortada no fim, com uma
        /// sombra curta só para destacar do fundo (sombra larga borra a letra).
        private func text(_ string: String, in rect: CGRect, font: CTFont, color: CGColor) {
            guard rect.width > 8, rect.height > 4 else { return }
            let line = CTLineCreateWithAttributedString(attributed(string, font: font, color: color))
            let token = CTLineCreateWithAttributedString(attributed("…", font: font, color: color))
            guard let fitted = CTLineCreateTruncatedLine(line, Double(rect.width), .end, token) else { return }
            draw(fitted, at: rect.minX, in: rect, font: font, shadow: true)
        }

        private func draw(_ line: CTLine, at x: CGFloat, in clip: CGRect, font: CTFont, shadow: Bool) {
            context.saveGState()
            context.clip(to: clip)
            if shadow {
                context.setShadow(offset: CGSize(width: 0, height: 0.5 * s), blur: 1 * s,
                                  color: CGColor(gray: 0, alpha: 0.45))
            }
            context.textPosition = CGPoint(x: x, y: clip.minY + CTFontGetAscent(font))
            CTLineDraw(line, context)
            context.restoreGState()
        }

        private func width(of line: CTLine) -> CGFloat {
            CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        }

        private func attributed(_ string: String, font: CTFont, color: CGColor) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
            ])
        }
    }
}

private enum CTFontWeight {
    case regular, semibold
}

private extension CTFont {
    static func system(size: CGFloat, weight: CTFontWeight, monospacedDigits: Bool = false) -> CTFont {
        let weight: NSFont.Weight = weight == .semibold ? .semibold : .regular
        let font = monospacedDigits
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        return font as CTFont
    }
}
