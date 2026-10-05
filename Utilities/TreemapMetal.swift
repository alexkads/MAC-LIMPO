// SPDX-License-Identifier: GPL-3.0-or-later
// MAC-LIMPO — Copyright (C) 2025-2026 Alex S S Fonseca and contributors.

import AppKit
import Metal
import MetalKit

/// Desenha as camadas do treemap na GPU. Cada `Rendering` vira um buffer de
/// formas (instâncias de um quad) e uma textura com os textos; pinça e arrasto
/// só mudam a transformação de cada camada (um uniform), então o mapa acompanha
/// o gesto quadro a quadro, nítido, sem redesenhar nada na CPU.
///
/// Precisão: a GPU trabalha em Float. Cada camada leva as formas em pixels da
/// própria cena (sempre perto da área desenhada) e a transformação até a tela;
/// esticada demais (camada de base sob uma lupa de 10⁵×), o produto passaria do
/// que o Float representa — aí as poucas formas que caem na tela são
/// transformadas em Double na CPU (`stretchedLayer`).
/// View Metal que sabe se desenhar fora da tela (capturas de desenvolvimento).
@MainActor
protocol MetalSnapshotting: NSView {
    func snapshotImage() -> CGImage?
    /// Cor que a captura mostra onde a camada Metal deveria estar.
    var snapshotBackground: TreemapRenderer.RGB { get }
}

@MainActor
final class TreemapMetal {
    static let shared = TreemapMetal()

    struct Layer {
        let rendering: TreemapRenderer.Rendering
        /// Onde a cena fica na view, em pontos.
        let frame: CGRect
    }

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let shapePipeline: MTLRenderPipelineState
    private let labelPipeline: MTLRenderPipelineState
    private let textureLoader: MTKTextureLoader
    private var resources: [UUID: (shapes: MTLBuffer?, labels: MTLTexture?)] = [:]
    static let pixelFormat = MTLPixelFormat.bgra8Unorm

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.shaderSource, options: nil)
        else { return nil }
        func pipeline(_ vertex: String, _ fragment: String) -> MTLRenderPipelineState? {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: vertex)
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            let attachment = descriptor.colorAttachments[0]!
            attachment.pixelFormat = Self.pixelFormat
            // Cores pré-multiplicadas, "source over".
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }
        guard let shapes = pipeline("shapeVertex", "shapeFragment"),
              let labels = pipeline("labelVertex", "labelFragment")
        else { return nil }
        self.device = device
        self.queue = queue
        shapePipeline = shapes
        labelPipeline = labels
        textureLoader = MTKTextureLoader(device: device)
    }

    // MARK: - Desenho

    /// Desenha `layers` (da mais grossa para a mais nítida) num alvo de
    /// `viewSize` pontos com `scale` pixels por ponto.
    func encode(_ layers: [Layer], viewSize: CGSize, scale: CGFloat, into encoder: MTLRenderCommandEncoder) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        let live = Set(layers.map(\.rendering.id))
        resources = resources.filter { live.contains($0.key) }
        for layer in layers {
            draw(layer, viewSize: viewSize, scale: scale, encoder: encoder)
        }
    }

    /// Para a tela: desenha no drawable da view.
    func draw(_ layers: [Layer], background: TreemapRenderer.RGB, in view: MTKView) {
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer()
        else { return }
        pass.colorAttachments[0].clearColor = MTLClearColor(red: background.r, green: background.g, blue: background.b, alpha: 1)
        pass.colorAttachments[0].loadAction = .clear
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encode(layers, viewSize: view.bounds.size, scale: view.window?.backingScaleFactor ?? 2, into: encoder)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    /// Fora da tela, para capturas (`cacheDisplay` não enxerga a camada Metal) e testes.
    func image(_ layers: [Layer], background: TreemapRenderer.RGB, viewSize: CGSize, scale: CGFloat) -> CGImage? {
        let width = max(1, Int(viewSize.width * scale)), height = max(1, Int(viewSize.height * scale))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.pixelFormat, width: width, height: height,
                                                                  mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let target = device.makeTexture(descriptor: descriptor), let buffer = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: background.r, green: background.g, blue: background.b, alpha: 1)
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encode(layers, viewSize: viewSize, scale: scale, into: encoder)
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                           | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Transformação de pixels da cena para coordenadas de clipe (NDC) e quantos
    /// pixels do alvo cabem num pixel da cena (para o antisserrilhado).
    private struct Uniforms {
        var scale: SIMD2<Float>
        var offset: SIMD2<Float>
        var devicePerScene: Float
        var padding: Float = 0
    }

    private func draw(_ layer: Layer, viewSize: CGSize, scale: CGFloat, encoder: MTLRenderCommandEncoder) {
        let rendering = layer.rendering
        guard !rendering.shapes.isEmpty, rendering.pixelSize.width > 0, rendering.pixelSize.height > 0 else { return }
        let stretchX = layer.frame.width / rendering.pixelSize.width
        let stretchY = layer.frame.height / rendering.pixelSize.height
        // Pontos de tela por pixel da cena vezes o tamanho da cena: acima disso o
        // Float da GPU erra a posição em mais de ~0,1 pt.
        let reach = max(stretchX * rendering.pixelSize.width, stretchY * rendering.pixelSize.height)
        if reach > 2_000_000 {
            stretchedLayer(layer, viewSize: viewSize, scale: scale, encoder: encoder)
            return
        }

        var resource = resources[rendering.id] ?? (nil, nil)
        if resource.shapes == nil {
            resource.shapes = rendering.shapes.withUnsafeBytes {
                device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared)
            }
            if let labels = rendering.labels {
                resource.labels = try? textureLoader.newTexture(cgImage: labels, options: [.SRGB: false])
            }
            resources[rendering.id] = resource
        }
        guard let shapes = resource.shapes else { return }

        var uniforms = Uniforms(
            scale: SIMD2(Float(stretchX * 2 / viewSize.width), Float(-stretchY * 2 / viewSize.height)),
            offset: SIMD2(Float(layer.frame.minX * 2 / viewSize.width - 1), Float(1 - layer.frame.minY * 2 / viewSize.height)),
            devicePerScene: Float(min(stretchX, stretchY) * scale)
        )
        encoder.setRenderPipelineState(shapePipeline)
        encoder.setVertexBuffer(shapes, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: rendering.shapes.count)

        if let labels = resource.labels {
            var size = SIMD2(Float(rendering.pixelSize.width), Float(rendering.pixelSize.height))
            encoder.setRenderPipelineState(labelPipeline)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setVertexBytes(&size, length: MemoryLayout<SIMD2<Float>>.stride, index: 2)
            encoder.setFragmentTexture(labels, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
    }

    /// Camada esticada além da precisão do Float: as formas que caem na tela são
    /// levadas a pontos da view em Double e recortadas perto dela. Os textos
    /// ficam de fora — nesse esticamento seriam um borrão.
    private func stretchedLayer(_ layer: Layer, viewSize: CGSize, scale: CGFloat, encoder: MTLRenderCommandEncoder) {
        let rendering = layer.rendering
        let kx = layer.frame.width / rendering.pixelSize.width
        let ky = layer.frame.height / rendering.pixelSize.height
        let margin: CGFloat = 16
        let view = CGRect(origin: .zero, size: viewSize).insetBy(dx: -margin, dy: -margin)
        var shapes: [TreemapRenderer.Shape] = []
        for shape in rendering.shapes {
            let rect = CGRect(x: layer.frame.minX + CGFloat(shape.rect.x) * kx, y: layer.frame.minY + CGFloat(shape.rect.y) * ky,
                              width: CGFloat(shape.rect.z) * kx, height: CGFloat(shape.rect.w) * ky)
            let clipped = rect.intersection(view)
            guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { continue }
            var moved = shape
            moved.rect = SIMD4(Float(clipped.minX), Float(clipped.minY), Float(clipped.width), Float(clipped.height))
            // Gradiente reamostrado nas bordas novas; cantos no máximo dentro da margem.
            let top = Float((clipped.minY - rect.minY) / rect.height), bottom = Float((clipped.maxY - rect.minY) / rect.height)
            moved.top = shape.top + (shape.bottom - shape.top) * top
            moved.bottom = shape.top + (shape.bottom - shape.top) * bottom
            moved.params.x = min(shape.params.x * Float(ky), 12)
            moved.params.y = min(shape.params.y * Float(ky), 12)
            moved.params.z = shape.params.z * Float(min(kx, ky))
            // Almofada: inclinação por pixel da cena vira por ponto da view.
            let u0 = Float((clipped.minX - rect.minX) / kx), v0 = Float((clipped.minY - rect.minY) / ky)
            moved.cushion = SIMD4(shape.cushion.x + shape.cushion.y * u0, shape.cushion.y / Float(kx),
                                  shape.cushion.z + shape.cushion.w * v0, shape.cushion.w / Float(ky))
            shapes.append(moved)
        }
        guard !shapes.isEmpty else { return }
        var uniforms = Uniforms(scale: SIMD2(Float(2 / viewSize.width), Float(-2 / viewSize.height)),
                                offset: SIMD2(-1, 1), devicePerScene: Float(scale))
        encoder.setRenderPipelineState(shapePipeline)
        shapes.withUnsafeBytes {
            if $0.count <= 4096 {
                encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 0)
            } else if let buffer = device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) {
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            }
        }
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: shapes.count)
    }

    // MARK: - Shaders

    /// Compilado em tempo de execução (o SPM não processa `.metal` sem um bundle
    /// de recursos). O layout de `Shape` tem de bater com `TreemapRenderer.Shape`.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Shape {
        float4 rect;     // x, y, largura, altura (pixels da cena)
        float4 top;      // cor na borda de cima
        float4 bottom;   // cor na borda de baixo
        float4 params;   // raio em cima, raio embaixo, contorno, iluminação (1 = almofada)
        float4 cushion;  // inclinação da almofada: gx na borda esquerda, dgx/dx, gy no topo, dgy/dy
    };

    struct Uniforms {
        float2 scale;
        float2 offset;
        float devicePerScene;
        float padding;
    };

    struct ShapeOut {
        float4 position [[position]];
        float2 local;
        float2 size;
        float4 top;
        float4 bottom;
        float4 params;
        float4 cushion;
        float devicePerScene;
    };

    vertex ShapeOut shapeVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                                const device Shape *shapes [[buffer(0)]],
                                constant Uniforms &u [[buffer(1)]]) {
        Shape s = shapes[iid];
        float2 corner = float2(vid & 1, vid >> 1);
        // Um pixel do alvo de folga para o antisserrilhado da borda.
        float pad = 1.0 / max(u.devicePerScene, 1e-6);
        float2 p = s.rect.xy - pad + corner * (s.rect.zw + 2.0 * pad);
        ShapeOut out;
        out.position = float4(p * u.scale + u.offset, 0, 1);
        out.local = p - s.rect.xy;
        out.size = s.rect.zw;
        out.top = s.top;
        out.bottom = s.bottom;
        out.params = s.params;
        out.cushion = s.cushion;
        out.devicePerScene = u.devicePerScene;
        return out;
    }

    // Distância com sinal até um retângulo arredondado (negativa dentro).
    static float roundedBox(float2 p, float2 extent, float radius) {
        float2 d = abs(p) - extent + radius;
        return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
    }

    fragment float4 shapeFragment(ShapeOut in [[stage_in]]) {
        float2 extent = in.size * 0.5;
        float2 p = in.local - extent;
        float radius = min(p.y < 0 ? in.params.x : in.params.y, min(extent.x, extent.y));
        float distance = roundedBox(p, extent, radius);
        // Cobertura com antisserrilhado de um pixel do alvo.
        float coverage = clamp(0.5 - distance * in.devicePerScene, 0.0, 1.0);
        if (in.params.z > 0) {
            coverage *= clamp(0.5 + (distance + in.params.z) * in.devicePerScene, 0.0, 1.0);
        }
        if (coverage <= 0) discard_fragment();
        float t = clamp(in.local.y / max(in.size.y, 1e-6), 0.0, 1.0);
        float4 color = mix(in.top, in.bottom, t);
        if (in.params.w > 0.5) {
            // Almofada (van Wijk & van de Wetering): normal da superfície somada
            // das pastas acima, luz vinda do alto à esquerda.
            float2 g = float2(in.cushion.x + in.cushion.y * in.local.x, in.cushion.z + in.cushion.w * in.local.y);
            // Muitos níveis aninhados somam inclinação: limitada, para o canto de
            // baixo à direita de pastas fundas não afundar no escuro.
            float steep = length(g);
            if (steep > 2.4) g *= 2.4 / steep;
            float3 normal = normalize(float3(-g.x, -g.y, 1.0));
            float3 light = normalize(float3(-1.0, -1.0, 4.5));
            float diffuse = max(dot(normal, light), 0.0);
            float specular = pow(max(dot(reflect(-light, normal), float3(0, 0, 1)), 0.0), 24.0);
            color.rgb = color.rgb * (0.42 + 0.70 * diffuse) + specular * 0.10;
        }
        return float4(color.rgb * color.a * coverage, color.a * coverage);
    }

    struct LabelOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex LabelOut labelVertex(uint vid [[vertex_id]], constant Uniforms &u [[buffer(1)]],
                                constant float2 &size [[buffer(2)]]) {
        float2 corner = float2(vid & 1, vid >> 1);
        LabelOut out;
        out.position = float4(corner * size * u.scale + u.offset, 0, 1);
        out.uv = corner;
        return out;
    }

    fragment float4 labelFragment(LabelOut in [[stage_in]], texture2d<float> labels [[texture(0)]]) {
        constexpr sampler linear(filter::linear, address::clamp_to_edge);
        return labels.sample(linear, in.uv);
    }
    """
}
