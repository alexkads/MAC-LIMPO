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
            // Diretórios agora têm cor baseada no nome para variedade visual, mas sutil
            let hash = abs(name.hashValue)
            let hue = Double(hash % 360) / 360.0
            return Color(hue: hue, saturation: 0.05, brightness: 0.9) // Cinza sutil com toque de cor
        }
        
        guard let ext = fileExtension else {
            return Color(hex: "9E9E9E") // Cinza neutro
        }
        
        // Código fonte - Azul Neon
        if ["swift", "js", "ts", "py", "java", "cpp", "c", "h", "m", "go", "rs", "rb", "php", "html", "css"].contains(ext) {
            return Color(hex: "007AFF") // System Blue vibrante
        }
        
        // Documentos - Verde Esmeralda
        if ["pdf", "doc", "docx", "txt", "md", "pages", "numbers", "key", "xls", "xlsx", "ppt", "pptx"].contains(ext) {
            return Color(hex: "34C759") // System Green
        }
        
        // Mídia (vídeo) - Laranja/Vermelho
        if ["mp4", "mov", "avi", "mkv", "m4v", "flv", "wmv", "webm"].contains(ext) {
            return Color(hex: "FF3B30") // System Red
        }
        
        // Imagens - Roxo/Rosa
        if ["jpg", "jpeg", "png", "gif", "bmp", "svg", "webp", "heic", "tiff", "psd", "ai"].contains(ext) {
            return Color(hex: "AF52DE") // System Purple
        }
        
        // Áudio - Ciano
        if ["mp3", "wav", "aac", "flac", "m4a", "ogg"].contains(ext) {
            return Color(hex: "00C7BE") // System Teal
        }
        
        // Compactados - Amarelo/Laranja
        if ["zip", "tar", "gz", "rar", "7z", "dmg", "pkg", "iso"].contains(ext) {
            return Color(hex: "FF9500") // System Orange
        }
        
        // Executáveis/Binários - Indigo
        if ["app", "exe", "bin", "dylib", "so", "dll", "sh"].contains(ext) {
            return Color(hex: "5856D6") // System Indigo
        }
        
        // Dados/Database - Rosa
        if ["db", "sqlite", "sql", "json", "xml", "csv", "plist", "yaml", "yml"].contains(ext) {
            return Color(hex: "FF2D55") // System Pink
        }
        
        // Outros
        return Color(hex: "8E8E93") // System Gray
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
