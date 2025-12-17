import Foundation
import os.log

class DiskMapService {
    static let shared = DiskMapService()
    private let fileManager = FileManager.default
    private let logger = Logger.shared
    
    // Contador compartilhado para progresso
    private actor ProgressCounter {
        var processed: Int = 0
        var total: Int = 0
        
        func increment() {
            processed += 1
        }
        
        func setTotal(_ value: Int) {
            total = value
        }
        
        func getProgress() -> Double {
            guard total > 0 else { return 0 }
            return Double(processed) / Double(total)
        }
        
        func reset() {
            processed = 0
            total = 0
        }
    }
    
    private let progressCounter = ProgressCounter()
    
    // Escaneia um diretório e constrói a árvore de FileNodes (com paralelização e progresso melhorado)
    func scanDirectory(
        path: String,
        maxDepth: Int = 5,
        currentDepth: Int = 0,
        progress: @escaping (String, Double) -> Void
    ) async -> FileNode {
        // Reset contador no início
        if currentDepth == 0 {
            await progressCounter.reset()
        }
        
        let expandedPath = (path as NSString).expandingTildeInPath
        
        // Verifica se o path existe
        guard fileManager.fileExists(atPath: expandedPath) else {
            logger.log("Path não existe: \(expandedPath)", level: .error)
            return FileNode.empty()
        }
        
        var isDir: ObjCBool = false
        fileManager.fileExists(atPath: expandedPath, isDirectory: &isDir)
        
        // Se for arquivo, retorna nó simples
        if !isDir.boolValue {
            let size = getFileSize(atPath: expandedPath)
            let name = (expandedPath as NSString).lastPathComponent
            return FileNode(name: name, path: expandedPath, size: size, isDirectory: false)
        }
        
        // Se atingiu profundidade máxima, retorna diretório sem filhos
        if currentDepth >= maxDepth {
            let size = FileSystemHelper.shared.sizeOfDirectory(atPath: expandedPath)
            let name = (expandedPath as NSString).lastPathComponent
            return FileNode(name: name, path: expandedPath, size: size, isDirectory: true)
        }
        
        // Lista conteúdo do diretório
        var children: [FileNode] = []
        
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: expandedPath)
            
            // Separa diretórios e arquivos
            var directories: [String] = []
            var files: [String] = []
            
            for item in contents {
                // Ignora arquivos ocultos e do sistema
                if item.hasPrefix(".") {
                    continue
                }
                
                let itemPath = (expandedPath as NSString).appendingPathComponent(item)
                
                var isItemDir: ObjCBool = false
                fileManager.fileExists(atPath: itemPath, isDirectory: &isItemDir)
                
                if isItemDir.boolValue {
                    directories.append(item)
                } else {
                    files.append(item)
                }
            }
            
            // Define total de diretórios a processar (apenas no nível raiz)
            if currentDepth == 0 {
                await progressCounter.setTotal(directories.count)
            }
            
            // Processa arquivos (rápido, não precisa paralelizar)
            for item in files {
                let itemPath = (expandedPath as NSString).appendingPathComponent(item)
                let size = getFileSize(atPath: itemPath)
                let fileNode = FileNode(name: item, path: itemPath, size: size, isDirectory: false)
                children.append(fileNode)
            }
            
            // Processa diretórios em PARALELO usando TaskGroup
            if !directories.isEmpty {
                await withTaskGroup(of: FileNode.self) { group in
                    for item in directories {
                        let itemPath = (expandedPath as NSString).appendingPathComponent(item)
                        
                        group.addTask {
                            // Cada diretório é escaneado em paralelo
                            let node = await self.scanDirectory(
                                path: itemPath,
                                maxDepth: maxDepth,
                                currentDepth: currentDepth + 1,
                                progress: progress
                            )
                            
                            // Atualiza progresso após cada diretório
                            if currentDepth == 0 {
                                await self.progressCounter.increment()
                                let currentProgress = await self.progressCounter.getProgress()
                                
                                await MainActor.run {
                                    let displayName = (itemPath as NSString).lastPathComponent
                                    progress("Scanning: \(displayName)", currentProgress)
                                }
                            }
                            
                            return node
                        }
                    }
                    
                    // Coleta resultados
                    for await childNode in group {
                        children.append(childNode)
                    }
                }
            }
        } catch {
            logger.log("Erro ao ler diretório \(expandedPath): \(error.localizedDescription)", level: .error)
        }
        
        // Calcula tamanho do diretório (soma dos filhos)
        let totalSize = children.reduce(0) { $0 + $1.totalSize }
        let name = (expandedPath as NSString).lastPathComponent
        let node = FileNode(name: name, path: expandedPath, size: 0, isDirectory: true, children: children)
        node.size = totalSize
        
        // Ordena filhos por tamanho
        node.sortChildren()
        
        return node
    }
    
    // Obtém tamanho de um arquivo
    private func getFileSize(atPath path: String) -> Int64 {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            return attributes[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    // Retorna diretórios de nível superior para scan
    func getTopLevelDirectories() -> [(name: String, path: String)] {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        
        return [
            (name: "Home", path: homeDir),
            (name: "Desktop", path: (homeDir as NSString).appendingPathComponent("Desktop")),
            (name: "Documents", path: (homeDir as NSString).appendingPathComponent("Documents")),
            (name: "Downloads", path: (homeDir as NSString).appendingPathComponent("Downloads")),
            (name: "Applications", path: "/Applications"),
            (name: "Library", path: (homeDir as NSString).appendingPathComponent("Library"))
        ]
    }
    
    // Scan rápido para estimar tamanho sem construir árvore completa
    func quickScan(path: String) -> Int64 {
        let expandedPath = (path as NSString).expandingTildeInPath
        return FileSystemHelper.shared.sizeOfDirectory(atPath: expandedPath)
    }
}
