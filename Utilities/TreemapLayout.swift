import Foundation
import SwiftUI

// Representa um retângulo no treemap
struct TreemapRect: Identifiable {
    let id = UUID()
    let node: FileNode
    let frame: CGRect
    let depth: Int
    
    var color: Color {
        node.color
    }
}

// Algoritmo de layout para treemap (squarified)
struct TreemapLayout {
    
    // Layout principal - divide o espaço disponível entre os nós
    static func layout(nodes: [FileNode], in rect: CGRect, depth: Int = 0, inset: CGFloat = 2) -> [TreemapRect] {
        guard !nodes.isEmpty else { return [] }
        
        // Filtra nós com tamanho > 0
        let validNodes = nodes.filter { $0.totalSize > 0 }
        guard !validNodes.isEmpty else { return [] }
        
        let totalSize = validNodes.reduce(0) { $0 + $1.totalSize }
        
        // Se há apenas um nó, retorna ele ocupando todo o espaço
        if validNodes.count == 1 {
            let frame = rect.insetBy(dx: inset, dy: inset)
            return [TreemapRect(node: validNodes[0], frame: frame, depth: depth)]
        }
        
        // Usa algoritmo squarified para melhor aspect ratio
        return squarify(nodes: validNodes, totalSize: totalSize, in: rect, depth: depth, inset: inset)
    }
    
    // Algoritmo squarified treemap (melhorado - preenche todo espaço)
    private static func squarify(
        nodes: [FileNode],
        totalSize: Int64,
        in rect: CGRect,
        depth: Int,
        inset: CGFloat
    ) -> [TreemapRect] {
        guard !nodes.isEmpty, totalSize > 0 else { return [] }
        
        var result: [TreemapRect] = []
        
        // Determina orientação baseada no aspect ratio
        let isHorizontal = rect.width >= rect.height
        
        // Calcula proporções normalizadas
        var currentPos: CGFloat = 0
        let totalDimension = isHorizontal ? rect.width : rect.height
        
        for (index, node) in nodes.enumerated() {
            let ratio = CGFloat(node.totalSize) / CGFloat(totalSize)
            
            // Para o último item, usa todo o espaço restante (evita gaps)
            let dimension: CGFloat
            if index == nodes.count - 1 {
                dimension = totalDimension - currentPos
            } else {
                dimension = totalDimension * ratio
            }
            
            // Garante dimensão mínima
            guard dimension > 0 else { continue }
            
            let nodeRect: CGRect
            if isHorizontal {
                nodeRect = CGRect(
                    x: rect.minX + currentPos,
                    y: rect.minY,
                    width: dimension,
                    height: rect.height
                )
            } else {
                nodeRect = CGRect(
                    x: rect.minX,
                    y: rect.minY + currentPos,
                    width: rect.width,
                    height: dimension
                )
            }
            
            currentPos += dimension
            
            // Aplica inset para separação visual
            let finalFrame = nodeRect.insetBy(dx: inset, dy: inset)
            if finalFrame.width > 0 && finalFrame.height > 0 {
                result.append(TreemapRect(node: node, frame: finalFrame, depth: depth))
            }
        }
        
        return result
    }
}
