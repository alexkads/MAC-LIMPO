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
    static func layout(nodes: [FileNode], in rect: CGRect, depth: Int = 0) -> [TreemapRect] {
        guard !nodes.isEmpty else { return [] }
        
        // Filtra nós com tamanho > 0
        let validNodes = nodes.filter { $0.totalSize > 0 }
        guard !validNodes.isEmpty else { return [] }
        
        let totalSize = validNodes.reduce(0) { $0 + $1.totalSize }
        
        // Se há apenas um nó, retorna ele ocupando todo o espaço
        if validNodes.count == 1 {
            return [TreemapRect(node: validNodes[0], frame: rect, depth: depth)]
        }
        
        // Usa algoritmo squarified para melhor aspect ratio
        return squarify(nodes: validNodes, totalSize: totalSize, in: rect, depth: depth)
    }
    
    // Algoritmo squarified treemap
    private static func squarify(
        nodes: [FileNode],
        totalSize: Int64,
        in rect: CGRect,
        depth: Int
    ) -> [TreemapRect] {
        var result: [TreemapRect] = []
        var remaining = nodes
        var currentRect = rect
        
        while !remaining.isEmpty {
            // Determina orientação (horizontal ou vertical) baseado no aspect ratio
            let isHorizontal = currentRect.width >= currentRect.height
            
            // Pega o próximo nó
            let node = remaining.removeFirst()
            let ratio = Double(node.totalSize) / Double(totalSize)
            
            let nodeRect: CGRect
            if isHorizontal {
                let width = currentRect.width * ratio
                nodeRect = CGRect(
                    x: currentRect.minX,
                    y: currentRect.minY,
                    width: width,
                    height: currentRect.height
                )
                currentRect = CGRect(
                    x: currentRect.minX + width,
                    y: currentRect.minY,
                    width: currentRect.width - width,
                    height: currentRect.height
                )
            } else {
                let height = currentRect.height * ratio
                nodeRect = CGRect(
                    x: currentRect.minX,
                    y: currentRect.minY,
                    width: currentRect.width,
                    height: height
                )
                currentRect = CGRect(
                    x: currentRect.minX,
                    y: currentRect.minY + height,
                    width: currentRect.width,
                    height: currentRect.height - height
                )
            }
            
            result.append(TreemapRect(node: node, frame: nodeRect, depth: depth))
        }
        
        return result
    }
    
    // Calcula aspect ratio de um retângulo
    private static func aspectRatio(of rect: CGRect) -> Double {
        let width = Double(rect.width)
        let height = Double(rect.height)
        return max(width / height, height / width)
    }
}
