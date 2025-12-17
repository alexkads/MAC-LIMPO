import Foundation
import SwiftUI

class TreemapViewModel: ObservableObject {
    @Published var rootNode: FileNode?
    @Published var currentNode: FileNode?
    @Published var isScanning: Bool = false
    @Published var scanProgress: Double = 0
    @Published var scanStatus: String = ""
    @Published var selectedNode: FileNode?
    @Published var hoveredNode: FileNode?
    @Published var breadcrumbs: [FileNode] = []
    
    private let diskMapService = DiskMapService.shared
    private let maxDepth: Int
    
    private var scanTask: Task<Void, Never>?
    
    init(maxDepth: Int = 5) {
        self.maxDepth = maxDepth
    }
    
    // Inicia scan de um diretório
    func startScan(path: String) {
        cancelScanTask() // Cancela scan anterior se houver
        
        isScanning = true
        scanProgress = 0
        scanStatus = "Preparing scan..."
        
        scanTask = Task {
            let node = await diskMapService.scanDirectory(
                path: path,
                maxDepth: maxDepth,
                progress: { [weak self] status, progress in
                    Task { @MainActor in
                        self?.scanStatus = status
                        self?.scanProgress = progress
                    }
                }
            )
            
            // Verifica se a task foi cancelada antes de atualizar a UI
            if !Task.isCancelled {
                await MainActor.run {
                    rootNode = node
                    currentNode = node
                    breadcrumbs = [node]
                    isScanning = false
                    scanStatus = "Scan complete!"
                    scanProgress = 1.0
                }
            }
        }
    }
    
    // Cancela o scan atual
    func cancelScanTask() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        scanStatus = "Scan cancelled"
        scanProgress = 0
    }
    
    // Navega para um nó específico (zoom in)
    func navigateToNode(_ node: FileNode) {
        guard node.isDirectory, !node.children.isEmpty else { return }
        
        currentNode = node
        
        // Atualiza breadcrumbs
        if let index = breadcrumbs.firstIndex(where: { $0.id == node.id }) {
            breadcrumbs = Array(breadcrumbs.prefix(through: index))
        } else {
            breadcrumbs.append(node)
        }
    }
    
    // Navega para cima (zoom out)
    func navigateUp() {
        guard breadcrumbs.count > 1 else { return }
        breadcrumbs.removeLast()
        currentNode = breadcrumbs.last
    }
    
    // Navega para um breadcrumb específico
    func navigateToBreadcrumb(_ node: FileNode) {
        guard let index = breadcrumbs.firstIndex(where: { $0.id == node.id }) else { return }
        breadcrumbs = Array(breadcrumbs.prefix(through: index))
        currentNode = node
    }
    
    // Reseta para o root
    func reset() {
        currentNode = rootNode
        breadcrumbs = rootNode.map { [$0] } ?? []
        selectedNode = nil
        hoveredNode = nil
    }
    
    // Limpa o scan atual e volta para a seleção
    func clearScan() {
        rootNode = nil
        currentNode = nil
        breadcrumbs = []
        selectedNode = nil
        hoveredNode = nil
        isScanning = false
        scanStatus = ""
        scanProgress = 0
    }
    
    // Obtém diretórios de nível superior
    func getTopLevelDirectories() -> [(name: String, path: String)] {
        diskMapService.getTopLevelDirectories()
    }
}
