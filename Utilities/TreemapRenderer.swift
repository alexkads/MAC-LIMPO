// SPDX-License-Identifier: GPL-3.0-or-later
// MAC-LIMPO — Copyright (C) 2025-2026 Alex S S Fonseca and contributors.

import AppKit
import CoreGraphics
import CoreText

/// Treemap do Disk X-Ray: layout squarified (Bruls, Huizing & van Wijk, 2000),
/// pastas com espaçamento e cabeçalho, ladrilhos arredondados com gradiente e
/// rótulos nos blocos grandes. Desenha num bitmap com CoreGraphics, fora da
/// thread principal; o custo é limitado pela área, não pelo número de arquivos
/// (blocos menores que um pixel não descem na hierarquia).
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

    struct Rendering: @unchecked Sendable {
        let image: CGImage
        let pixelSize: CGSize
        /// Pixels por ponto com que foi desenhado (a tela pode mudar depois).
        let scale: CGFloat
        let root: Int32
        /// Retângulo de cada item desenhado, em pixels do bitmap.
        let rects: [Int32: CGRect]
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
    }

    static func render(
        root: Int32,
        width: Int,
        height: Int,
        style: Style,
        source: Source,
        isCancelled: @escaping () -> Bool
    ) -> Rendering? {
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
        context.setFillColor(style.background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        var painter = Painter(context: context, style: style, source: source, isCancelled: isCancelled)
        painter.draw(root, in: CGRect(x: 0, y: 0, width: width, height: height), depth: 0, prefix: "")
        guard !painter.cancelled, let image = context.makeImage() else { return nil }
        return Rendering(image: image, pixelSize: CGSize(width: width, height: height), scale: style.scale,
                         root: root, rects: painter.rects)
    }

    /// Item mais profundo sob o ponto (em pixels do bitmap).
    static func hitTest(_ point: CGPoint, in rendering: Rendering, source: Source) -> Int32? {
        guard rendering.rects[rendering.root]?.contains(point) == true else { return nil }
        var cursor = rendering.root
        outer: while !source.isLeaf(cursor) {
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
        while start < weights.count, remainingWeight > 0 {
            let horizontal = remaining.width >= remaining.height
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
                if ratio > worst, end > start { break }
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
        let source: Source
        let isCancelled: () -> Bool
        var rects: [Int32: CGRect] = [:]
        var cancelled = false
        private var visits = 0

        init(context: CGContext, style: Style, source: Source, isCancelled: @escaping () -> Bool) {
            self.context = context
            self.style = style
            self.source = source
            self.isCancelled = isCancelled
        }

        private var s: CGFloat { style.scale }

        /// `prefix`: nomes das pastas acima que tinham um único filho — a cadeia
        /// vira um cabeçalho só ("Library / Containers / com.docker.docker").
        mutating func draw(_ item: Int32, in rect: CGRect, depth: Int, prefix: String) {
            guard !cancelled, rect.width >= 0.5, rect.height >= 0.5 else { return }
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
                tile(item, rect: rect, colorItem: leaf ? item : dominantLeaf(of: item), labeled: leaf)
                return
            }

            let children = source.children(item)
            let weights = children.map { Double(source.weight($0)) }
            if depth > 0, weights.filter({ $0 > 0 }).count == 1, let only = children.first {
                draw(only, in: rect, depth: depth, prefix: prefix + source.name(item) + " / ")
                return
            }

            var content = rect
            if depth > 0 {
                // Moldura só onde ela ajuda a ler a hierarquia: pastas grandes e
                // rasas. Em pastas pequenas ou profundas o recuo se acumula nível
                // a nível e deixa os blocos ilhados — ali os filhos ocupam tudo.
                let padding = folderPadding(rect, depth: depth)
                let header = rect.width >= 90 * s && rect.height >= 60 * s ? 15 * s : 0
                if padding > 0 || header > 0 {
                    folderBackground(rect)
                    if header > 0 { folderHeader(item, prefix: prefix, rect: rect, height: header) }
                    content = rect.insetBy(dx: padding, dy: padding)
                    content.origin.y += header
                    content.size.height -= header
                    guard content.width > 1, content.height > 1 else { return }
                }
            }

            let layout = TreemapRenderer.squarify(weights: weights, in: content)
            for (child, childRect) in zip(children, layout) {
                draw(child, in: childRect, depth: depth + 1, prefix: "")
                if cancelled { return }
            }
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

        private func dominantLeaf(of item: Int32) -> Int32 {
            var cursor = item
            while !source.isLeaf(cursor), let largest = source.children(cursor).first {
                cursor = largest
            }
            return cursor
        }

        private func folderBackground(_ rect: CGRect) {
            let tint = style.dark ? RGB.white : RGB.black
            context.setFillColor(style.background.mixed(with: tint, style.dark ? 0.07 : 0.05).cgColor)
            let path = CGPath(roundedRect: rect.insetBy(dx: 0.5 * s, dy: 0.5 * s),
                              cornerWidth: min(5 * s, rect.width / 4), cornerHeight: min(5 * s, rect.height / 4), transform: nil)
            context.addPath(path)
            context.fillPath()
        }

        private func folderHeader(_ item: Int32, prefix: String, rect: CGRect, height: CGFloat) {
            let color = style.dark ? CGColor(gray: 1, alpha: 0.75) : CGColor(gray: 0, alpha: 0.7)
            text("\(prefix)\(source.name(item))  \(source.sizeText(item))", in: CGRect(x: rect.minX + 6 * s, y: rect.minY + 2 * s,
                                                                             width: rect.width - 12 * s, height: height - 2 * s),
                 size: 10.5 * s, weight: .semibold, color: color, shadow: false)
        }

        private func tile(_ item: Int32, rect: CGRect, colorItem: Int32, labeled: Bool) {
            var base = source.color(colorItem)
            if !source.isEmphasized(colorItem) {
                base = base.mixed(with: style.background, 0.78)
            }
            // Folga de meio ponto só em blocos que a comportam; abaixo disso ela
            // vira o espaço vazio entre arquivos pequenos.
            let gap = rect.width >= 8 * s && rect.height >= 8 * s ? 0.5 * s : 0
            let box = rect.insetBy(dx: gap, dy: gap)
            guard box.width > 0, box.height > 0 else { return }

            let side = min(box.width, box.height)
            let radius = side >= 12 * s ? min(4 * s, side / 5) : 0
            if box.width * box.height >= 600 * s * s {
                // Gradiente vertical: topo mais claro, base levemente mais escura.
                let top = base.mixed(with: .white, style.dark ? 0.12 : 0.22)
                let bottom = base.mixed(with: .black, style.dark ? 0.18 : 0.08)
                context.saveGState()
                context.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
                context.clip()
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                             colors: [top.cgColor, bottom.cgColor] as CFArray, locations: [0, 1]) {
                    context.drawLinearGradient(gradient, start: CGPoint(x: box.midX, y: box.minY),
                                               end: CGPoint(x: box.midX, y: box.maxY), options: [])
                }
                context.restoreGState()
            } else {
                context.setFillColor(base.cgColor)
                if radius >= 1 {
                    context.addPath(CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil))
                    context.fillPath()
                } else {
                    context.fill(box)
                }
            }

            if labeled, box.width >= 64 * s, box.height >= 30 * s {
                let inset = box.insetBy(dx: 6 * s, dy: 5 * s)
                text(source.name(item), in: CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: 14 * s),
                     size: 11 * s, weight: .semibold, color: CGColor(gray: 1, alpha: 0.95), shadow: true)
                if box.height >= 44 * s {
                    text(source.sizeText(item), in: CGRect(x: inset.minX, y: inset.minY + 14 * s, width: inset.width, height: 13 * s),
                         size: 10 * s, weight: .regular, color: CGColor(gray: 1, alpha: 0.8), shadow: true)
                }
            }
        }

        private func text(_ string: String, in rect: CGRect, size: CGFloat, weight: CTFontWeight, color: CGColor, shadow: Bool) {
            guard rect.width > 8, rect.height > 4 else { return }
            let font = CTFont.system(size: size, weight: weight)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
            let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
            guard let fitted = CTLineCreateTruncatedLine(line, Double(rect.width), .end, token) else { return }

            context.saveGState()
            context.clip(to: rect)
            if shadow {
                context.setShadow(offset: CGSize(width: 0, height: 0.5 * s), blur: 2 * s,
                                  color: CGColor(gray: 0, alpha: 0.55))
            }
            context.textPosition = CGPoint(x: rect.minX, y: rect.minY + CTFontGetAscent(font))
            CTLineDraw(fitted, context)
            context.restoreGState()
        }
    }
}

private enum CTFontWeight {
    case regular, semibold
}

private extension CTFont {
    static func system(size: CGFloat, weight: CTFontWeight) -> CTFont {
        NSFont.systemFont(ofSize: size, weight: weight == .semibold ? .semibold : .regular) as CTFont
    }
}
