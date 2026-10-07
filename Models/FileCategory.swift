// SPDX-License-Identifier: GPL-3.0-or-later
// MAC-LIMPO — Copyright (C) 2025-2026 Alex S S Fonseca and contributors.

import Foundation

/// Grupo de tipos de arquivo usado para colorir o Disk X-Ray. Cada extensão cai
/// em uma categoria; a cor diz "o que é" um bloco no mapa sem precisar ler.
enum FileCategory: Int, CaseIterable, Identifiable, Sendable {
    case video, images, audio, documents, archives, code, build, virtualDisks, data, other

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .video: String(localized: "Video")
        case .images: String(localized: "Images")
        case .audio: String(localized: "Audio")
        case .documents: String(localized: "Documents")
        case .archives: String(localized: "Archives & Installers")
        case .code: String(localized: "Source Code")
        case .build: String(localized: "Builds & Libraries")
        case .virtualDisks: String(localized: "Disk Images & VMs")
        case .data: String(localized: "Data & Databases")
        case .other: String(localized: "Other")
        }
    }

    var symbol: String {
        switch self {
        case .video: "film"
        case .images: "photo"
        case .audio: "music.note"
        case .documents: "doc.text"
        case .archives: "archivebox"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .build: "hammer"
        case .virtualDisks: "externaldrive"
        case .data: "cylinder.split.1x2"
        case .other: "questionmark.square.dashed"
        }
    }

    /// Cor base (sRGB 0...1). Saturadas o bastante para distinguir no mapa,
    /// sem o neon da paleta do WinDirStat.
    var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .video: (0.93, 0.33, 0.42) // rosa avermelhado
        case .images: (0.98, 0.58, 0.24) // laranja
        case .audio: (0.95, 0.78, 0.25) // amarelo
        case .documents: (0.31, 0.56, 0.96) // azul
        case .archives: (0.62, 0.42, 0.94) // roxo
        case .code: (0.30, 0.78, 0.47) // verde
        case .build: (0.20, 0.72, 0.74) // turquesa
        case .virtualDisks: (0.45, 0.42, 0.88) // índigo
        case .data: (0.32, 0.70, 0.93) // ciano
        case .other: (0.56, 0.58, 0.62) // cinza
        }
    }

    /// Categoria de uma chave de extensão do índice (".mp4", "" para sem extensão).
    static func of(extensionKey key: String) -> FileCategory {
        guard key.count > 1 else { return .other }
        return table[String(key.dropFirst())] ?? .other
    }

    private static let table: [String: FileCategory] = {
        var map: [String: FileCategory] = [:]
        func add(_ category: FileCategory, _ extensions: String) {
            for ext in extensions.split(separator: " ") { map[String(ext)] = category }
        }
        add(.video, "mov mp4 m4v mkv avi webm wmv flv mpg mpeg mts m2ts 3gp prores braw r3d")
        add(.images, "jpg jpeg png heic heif gif tif tiff bmp webp svg psd psb ai eps ico icns dng cr2 cr3 nef arw orf rw2 raf sketch fig xcf exr hdr avif jxl")
        add(.audio, "mp3 m4a aac wav aif aiff flac caf ogg opus wma alac mid midi logicx band")
        add(.documents, "pdf doc docx pages key keynote numbers xls xlsx ppt pptx odt ods odp rtf txt md markdown epub csv tex")
        add(.archives, "zip gz tgz tar xz bz2 7z rar zst lz4 dmg pkg mpkg xip iso ipsw cab msi apk aab ipa crate whl gem nupkg")
        add(.code, "swift m mm h hpp c cc cpp cxx rs go py rb php java kt kts scala cs fs js mjs cjs jsx ts tsx vue svelte css scss sass less html htm json yaml yml toml xml plist sql sh zsh bash fish ps1 lua dart ex exs erl hs ml clj r jl pl gradle cmake makefile lock map ipynb graphql proto")
        add(.build, "o a so dylib dll lib rlib rmeta jar war class pyc pyo wasm obj pdb dsym swiftmodule swiftdoc swiftsourceinfo pcm pch d car nib storyboardc metallib framework node bundle exe bin elf")
        add(.virtualDisks, "raw img vmdk vdi vhd vhdx qcow2 qcow sparseimage sparsebundle hdd pvm utm asset")
        add(.data, "db sqlite sqlite3 sqlitedb realm sst ldb data dat parquet arrow feather avro orc safetensors gguf ggml onnx pt pth ckpt h5 hdf5 npy npz pack idx log tsv ndjson jsonl mdb accdb frm ibd myd")
        return map
    }()
}
