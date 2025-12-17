import Foundation
import SwiftUI

class FileNode: Identifiable, ObservableObject {
    let id = UUID()
    let name: String
    let path: String
    @Published var size: Int64
    @Published var children: [FileNode]
    let isDirectory: Bool
    let fileExtension: String?
    
    init(name: String, path: String, size: Int64, isDirectory: Bool, children: [FileNode] = []) {
        self.name = name
        self.path = path
        self.size = size
        self.isDirectory = isDirectory
        self.children = children
        self.fileExtension = isDirectory ? nil : (path as NSString).pathExtension.lowercased()
    }
    
    // Tamanho total incluindo filhos
    var totalSize: Int64 {
        if children.isEmpty {
            return size
        }
        return children.reduce(size) { $0 + $1.totalSize }
    }
    
    // Porcentagem relativa ao pai
    func percentage(relativeTo parentSize: Int64) -> Double {
        guard parentSize > 0 else { return 0 }
        return Double(totalSize) / Double(parentSize) * 100.0
    }
    
    // Cor baseada no tipo de arquivo
    var color: Color {
        if isDirectory {
            return .gray.opacity(0.3)
        }
        
        guard let ext = fileExtension else {
            return .gray
        }
        
        // Código fonte
        if ["swift", "js", "ts", "py", "java", "cpp", "c", "h", "m", "go", "rs", "rb"].contains(ext) {
            return Color(hex: "2196F3") // Azul
        }
        
        // Documentos
        if ["pdf", "doc", "docx", "txt", "md", "pages", "numbers", "key"].contains(ext) {
            return Color(hex: "4CAF50") // Verde
        }
        
        // Mídia (vídeo)
        if ["mp4", "mov", "avi", "mkv", "m4v", "flv", "wmv"].contains(ext) {
            return Color(hex: "F44336") // Vermelho
        }
        
        // Imagens
        if ["jpg", "jpeg", "png", "gif", "bmp", "svg", "webp", "heic"].contains(ext) {
            return Color(hex: "FF9800") // Amarelo/Laranja
        }
        
        // Áudio
        if ["mp3", "wav", "aac", "flac", "m4a", "ogg"].contains(ext) {
            return Color(hex: "E91E63") // Rosa
        }
        
        // Compactados
        if ["zip", "tar", "gz", "rar", "7z", "dmg", "pkg"].contains(ext) {
            return Color(hex: "9C27B0") // Roxo
        }
        
        // Executáveis/Binários
        if ["app", "exe", "bin", "dylib", "so", "dll"].contains(ext) {
            return Color(hex: "607D8B") // Cinza azulado
        }
        
        // Dados/Database
        if ["db", "sqlite", "sql", "json", "xml", "csv", "plist"].contains(ext) {
            return Color(hex: "00BCD4") // Ciano
        }
        
        return .gray
    }
    
    // Formata o tamanho para exibição
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    // Ordena filhos por tamanho (maior primeiro)
    func sortChildren() {
        children.sort { $0.totalSize > $1.totalSize }
        children.forEach { $0.sortChildren() }
    }
}

// Extension para FileNode facilitar criação de nós vazios
extension FileNode {
    static func empty() -> FileNode {
        FileNode(name: "Empty", path: "", size: 0, isDirectory: true)
    }
}
