// SPDX-License-Identifier: GPL-3.0-or-later
// MAC-LIMPO — Copyright (C) 2025-2026 Alex S S Fonseca and contributors.

import AppKit
import CoreText

/// Bandeirinha 3D (mastro com bola dourada e pano ondulado) do mapa 3D: o
/// tooltip do item sob o cursor, fincada onde o mouse está.
@MainActor
enum TreemapFlags {
    struct Sprite {
        let image: CGImage
        /// Tamanho em pontos e onde fica a base do mastro dentro dele.
        let size: CGSize
        let base: CGPoint
    }

    /// Onde desenhar o sprite com a base do mastro em `point`; perto das bordas,
    /// ele é empurrado para dentro da view (como um tooltip), sem cortar.
    static func tooltipFrame(for sprite: Sprite, at point: CGPoint, in view: CGSize) -> CGRect {
        var frame = CGRect(x: point.x - sprite.base.x, y: point.y - sprite.base.y,
                           width: sprite.size.width, height: sprite.size.height)
        frame.origin.x = min(max(2, frame.minX), view.width - frame.width - 2)
        frame.origin.y = min(max(2, frame.minY), view.height - frame.height - 2)
        return frame
    }

    /// A bandeira para `point`: o pano abre para a direita; sem espaço até a borda
    /// direita, abre para a esquerda (espelhada) — o mastro fica sempre no ponteiro.
    /// `sprite(mirrored)` desenha cada lado.
    static func tooltip(at point: CGPoint, in view: CGSize,
                        sprite: (_ mirrored: Bool) -> Sprite?) -> (sprite: Sprite, frame: CGRect)? {
        guard let right = sprite(false) else { return nil }
        if point.x - right.base.x + right.size.width > view.width - 2, let left = sprite(true) {
            return (left, tooltipFrame(for: left, at: point, in: view))
        }
        return (right, tooltipFrame(for: right, at: point, in: view))
    }

    // MARK: - Desenho

    private static var cache: [String: Sprite] = [:]

    /// Sprite da bandeira (em cache por conteúdo e escala da tela).
    /// `mirrored`: mastro à direita e pano abrindo para a esquerda (o texto não
    /// espelha).
    static func sprite(title: String, subtitle: String, folder: Bool, color: TreemapRenderer.RGB,
                       scale: CGFloat, mirrored: Bool = false) -> Sprite? {
        let key = "\(folder)|\(mirrored)|\(scale)|\(color.r),\(color.g),\(color.b)|\(title)|\(subtitle)"
        if let cached = cache[key] { return cached }
        if cache.count > 2000 { cache.removeAll() }
        let sprite = draw(title: title, subtitle: subtitle, folder: folder, color: color, scale: scale, mirrored: mirrored)
        cache[key] = sprite
        return sprite
    }

    private static func draw(title: String, subtitle: String, folder: Bool, color: TreemapRenderer.RGB,
                             scale s: CGFloat, mirrored: Bool) -> Sprite? {
        let titleFont = NSFont.systemFont(ofSize: 11 * s, weight: .semibold) as CTFont
        let subtitleFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5 * s, weight: .regular) as CTFont
        let primary = folder ? CGColor(gray: 1, alpha: 0.95) : CGColor(gray: 0.08, alpha: 0.9)
        let secondary = folder ? CGColor(gray: 1, alpha: 0.6) : CGColor(gray: 0.08, alpha: 0.55)
        func line(_ text: String, _ font: CTFont, _ color: CGColor) -> CTLine {
            CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
            ]))
        }
        func width(_ line: CTLine) -> CGFloat { CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) }
        let titleLine = line(title, titleFont, primary)
        let subtitleLine = line(subtitle, subtitleFont, secondary)
        let clothWidth = min(max(max(width(titleLine), width(subtitleLine)) + 20 * s, 46 * s), 190 * s)
        guard let fitted = CTLineCreateTruncatedLine(titleLine, Double(clothWidth - 20 * s), .end,
                                                     line("…", titleFont, primary))
        else { return nil }
        let clothHeight = 31 * s
        let poleHeight = (folder ? 44 : 38) * s

        // Sprite: margem para a bola do mastro, a onda e as sombras.
        let pixelWidth = Int((clothWidth + 22 * s).rounded(.up)), pixelHeight = Int((poleHeight + 14 * s).rounded(.up))
        guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

        let base = CGPoint(x: mirrored ? CGFloat(pixelWidth) - 7 * s : 7 * s, y: 8 * s + poleHeight)
        let top = CGPoint(x: base.x, y: base.y - poleHeight)
        let cloth = CGRect(x: mirrored ? top.x - 2 * s - clothWidth : top.x + 2 * s, y: top.y + 3 * s,
                           width: clothWidth, height: clothHeight)
        // `t`: 0 no mastro, 1 na ponta solta — de um lado ou do outro.
        func x(_ t: CGFloat) -> CGFloat { mirrored ? cloth.maxX - cloth.width * t : cloth.minX + cloth.width * t }

        // Onda presa no mastro, cada vez mais solta para a ponta.
        func wave(_ t: CGFloat) -> CGFloat { 2.6 * s * t * sin(t * .pi * 2.5) }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x(0), y: cloth.minY))
        for step in 1 ... 24 {
            let t = CGFloat(step) / 24
            path.addLine(to: CGPoint(x: x(t), y: cloth.minY + wave(t)))
        }
        for step in stride(from: 24, through: 0, by: -1) {
            let t = CGFloat(step) / 24
            path.addLine(to: CGPoint(x: x(t), y: cloth.maxY + wave(t) * 0.8))
        }
        path.closeSubpath()
        let tone = folder ? TreemapRenderer.RGB(r: 0.15, g: 0.16, b: 0.19) : TreemapRenderer.RGB(r: 0.97, g: 0.97, b: 0.95)

        // Sombras no "chão": da base do mastro e do pano.
        context.saveGState()
        context.setShadow(offset: .zero, blur: 2.5 * s, color: CGColor(gray: 0, alpha: 0.5))
        context.setFillColor(CGColor(gray: 0, alpha: 0.38))
        context.fillEllipse(in: CGRect(x: base.x - (mirrored ? 8 : 5) * s, y: base.y - 2 * s, width: 13 * s, height: 4 * s))
        context.restoreGState()
        context.saveGState()
        context.setShadow(offset: CGSize(width: 3 * s, height: 4 * s), blur: 5 * s, color: CGColor(gray: 0, alpha: 0.5))
        context.addPath(path)
        context.setFillColor(tone.cgColor)
        context.fillPath()
        context.restoreGState()

        // Mastro metálico e bola dourada.
        let pole = CGRect(x: top.x - 1.6 * s, y: top.y, width: 3.2 * s, height: poleHeight)
        let rgb = CGColorSpaceCreateDeviceRGB()
        context.saveGState()
        context.clip(to: pole)
        if let metal = CGGradient(colorsSpace: rgb, colors: [CGColor(gray: 0.45, alpha: 1), CGColor(gray: 0.95, alpha: 1),
                                                             CGColor(gray: 0.6, alpha: 1)] as CFArray, locations: [0, 0.4, 1]) {
            context.drawLinearGradient(metal, start: CGPoint(x: pole.minX, y: 0), end: CGPoint(x: pole.maxX, y: 0), options: [])
        }
        context.restoreGState()
        let ball = CGRect(x: top.x - 3.6 * s, y: top.y - 6 * s, width: 7.2 * s, height: 7.2 * s)
        context.saveGState()
        context.addEllipse(in: ball)
        context.clip()
        if let gold = CGGradient(colorsSpace: rgb, colors: [CGColor(srgbRed: 1, green: 0.93, blue: 0.6, alpha: 1),
                                                            CGColor(srgbRed: 0.85, green: 0.6, blue: 0.12, alpha: 1)] as CFArray,
                                 locations: [0, 1]) {
            context.drawRadialGradient(gold, startCenter: CGPoint(x: ball.minX + ball.width * 0.35, y: ball.minY + ball.height * 0.3),
                                       startRadius: 0, endCenter: CGPoint(x: ball.midX, y: ball.midY),
                                       endRadius: ball.width * 0.6, options: [.drawsAfterEndLocation])
        }
        context.restoreGState()

        // Pano: dobras de luz e sombra seguindo a onda, faixa do tipo (arquivo), brilho de cima.
        context.saveGState()
        context.addPath(path)
        context.clip()
        var colors: [CGColor] = []
        var locations: [CGFloat] = []
        for step in 0 ... 12 {
            let t = CGFloat(step) / 12
            let slope = cos(t * .pi * 2.5) * min(1, t * 3)
            colors.append(tone.mixed(with: slope > 0 ? .white : .black, Double(abs(slope)) * (folder ? 0.18 : 0.12)).cgColor)
            locations.append(t)
        }
        if let folds = CGGradient(colorsSpace: rgb, colors: colors as CFArray, locations: locations) {
            context.drawLinearGradient(folds, start: CGPoint(x: x(0), y: 0), end: CGPoint(x: x(1), y: 0),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        if !folder {
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: mirrored ? cloth.maxX - 4 * s : cloth.minX, y: cloth.minY - 4 * s,
                                width: 4 * s, height: cloth.height + 8 * s))
        }
        if let shine = CGGradient(colorsSpace: rgb, colors: [CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0)] as CFArray,
                                  locations: [0, 1]) {
            context.drawLinearGradient(shine, start: CGPoint(x: 0, y: cloth.minY), end: CGPoint(x: 0, y: cloth.midY), options: [])
        }
        context.restoreGState()
        context.addPath(path)
        context.setStrokeColor(CGColor(gray: 0, alpha: folder ? 0.5 : 0.22))
        context.setLineWidth(0.7 * s)
        context.strokePath()

        // Texto acompanhando a onda.
        // Texto sempre da esquerda para a direita; a onda daquele trecho o desloca.
        let textX = cloth.minX + (mirrored ? 9 : 10) * s
        let lift = wave(mirrored ? (cloth.maxX - textX - 20 * s) / cloth.width : (textX - cloth.minX + 20 * s) / cloth.width)
        func text(_ line: CTLine, _ font: CTFont, y: CGFloat, height: CGFloat) {
            let box = CGRect(x: textX, y: y, width: cloth.width - 14 * s, height: height)
            context.saveGState()
            context.clip(to: box)
            context.textPosition = CGPoint(x: box.minX, y: box.minY + CTFontGetAscent(font))
            CTLineDraw(line, context)
            context.restoreGState()
        }
        text(fitted, titleFont, y: cloth.minY + 3.5 * s + lift, height: 14 * s)
        text(subtitleLine, subtitleFont, y: cloth.minY + 18 * s + lift, height: 12 * s)

        guard let image = context.makeImage() else { return nil }
        return Sprite(image: image, size: CGSize(width: CGFloat(pixelWidth) / s, height: CGFloat(pixelHeight) / s),
                      base: CGPoint(x: base.x / s, y: base.y / s))
    }
}
