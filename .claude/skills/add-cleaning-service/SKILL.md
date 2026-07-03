---
name: add-cleaning-service
description: Scaffold a new disk-cleaning category in MAC-LIMPO end-to-end. Use whenever adding a cleaning category/service (e.g. "add a Figma cache cleaner", "criar service para limpar cache do X"). Performs the four coordinated edits SPM requires so the new service actually compiles and appears in the UI.
---

# Adding a cleaning category to MAC-LIMPO

Adding a category is **four coordinated edits**. Missing any one fails to compile or leaves the category invisible. The `sources:` array in `Package.swift` is the one people forget — SPM does not glob, so an unlisted `.swift` file is silently excluded from the build.

## Inputs to gather first

Ask the user (or infer from the request) if not given:
- **Case name** — lowerCamelCase enum case, e.g. `figmaCache`.
- **Display name** — the enum `rawValue`, e.g. `"Figma Cache"`.
- **Paths to clean** — the `~/…` cache/derived paths. NEVER target user documents; deletions are permanent (no trash/undo).
- **Group** — one of `.development`, `.system`, `.apps`, `.communication`, `.media`.
- **Icon** — an SF Symbol name. **Verify it exists** (open SF Symbols / check Apple docs); an invalid symbol renders blank.
- **Color** — a 6-digit hex (brand color when possible).
- **Description** — one short English sentence.

Pick a `<Name>` for the file/class (UpperCamelCase, e.g. `FigmaCache`) → file `Services/<Name>CleaningService.swift`, class `<Name>CleaningService`.

Choose the template:
- **Path-based** (default) — deletes a fixed list of directories. Use for almost all cache cleaners.
- **Tool-based** — shells out to a CLI (like Docker/Homebrew). Use only when a tool must run (`docker system prune`, `brew cleanup`). Guard with `shell.checkCommandExists("<tool>")`.

## Step 1 — Create the service file

`Services/<Name>CleaningService.swift`, path-based template (mirror the style of `Services/HomebrewCleaningService.swift`):

```swift
import Foundation

class <Name>CleaningService: BaseCleaningService, CleaningService {
    let category: CleaningCategory = .<caseName>

    private let paths = [
        "~/Library/Caches/<...>",
    ]

    func scan(progress: ((String) -> Void)?) async -> ScanResult {
        var totalSize: Int64 = 0
        var items: [String] = []

        logger.log("Iniciando escaneamento de <Name>", level: .info)
        progress?("Scanning <Name>...")

        for path in paths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                if size > 0 {
                    totalSize += size
                    items.append("\(path): \(fileHelper.formatBytes(size))")
                }
            }
        }

        logger.log("Escaneamento <Name> concluído: \(fileHelper.formatBytes(totalSize))", level: .info)
        return ScanResult(category: category, estimatedSize: totalSize, itemCount: items.count, items: items)
    }

    func clean() async -> CleaningResult {
        let startTime = Date()
        var bytesRemoved: Int64 = 0
        var filesRemoved = 0
        var errors: [String] = []

        logger.log("Iniciando limpeza de <Name>", level: .info)

        for path in paths {
            let expandedPath = fileHelper.expandPath(path)
            if fileHelper.fileExists(atPath: expandedPath) {
                let size = fileHelper.sizeOfDirectory(atPath: expandedPath)
                do {
                    try fileHelper.removeItem(atPath: expandedPath)
                    bytesRemoved += size
                    filesRemoved += 1
                } catch {
                    errors.append("Falha ao limpar: \(path)")
                    logger.log("Falha ao remover: \(expandedPath)", level: .error)
                }
            }
        }

        return CleaningResult(
            category: category,
            bytesRemoved: bytesRemoved,
            filesRemoved: filesRemoved,
            errors: errors,
            executionTime: Date().timeIntervalSince(startTime),
            success: errors.isEmpty
        )
    }
}
```

Tool-based variant: in `scan`, `guard shell.checkCommandExists("<tool>") else { return ScanResult(category: category, estimatedSize: 0, itemCount: 0, items: ["<tool> not installed"]) }` and use `shell.execute(...)`; in `clean`, run the prune command via `shell.execute(...)`. See `Services/DockerCleaningService.swift`.

Conventions: log messages/comments are Portuguese, UI-facing strings (items, descriptions) are English, 4-space indent. Available helpers: `fileHelper` (`expandPath`, `fileExists`, `sizeOfDirectory`, `removeItem`, `formatBytes`) and `shell`; `logger` is a global.

## Step 2 — Extend the enum in `Models/CleaningCategory.swift`

The enum is `CaseIterable` and every `switch` over it is exhaustive, so a new case that isn't handled in **all** of these fails to compile:
1. Add `case <caseName> = "<Display Name>"` in the right section.
2. `group` switch — add `<caseName>` to the chosen group's case list.
3. `icon` switch — `case .<caseName>: return "<sf.symbol>"`.
4. `color` switch — `case .<caseName>: return Color(hex: "<hex>")`.
5. `description` switch — `case .<caseName>: return "<one sentence>"`.

## Step 3 — Register in `Views/MenuBarView.swift`

Add to the `services` dictionary in `MenuBarViewModel`:
```swift
.<caseName>: <Name>CleaningService(),
```
(The trailing entry has no comma — if inserting at the end, fix commas.)

## Step 4 — Add to `Package.swift` sources — DO NOT SKIP

In the `sources:` array add:
```swift
"Services/<Name>CleaningService.swift",
```
Without this the file compiles nowhere and the app builds using the *old* code with no error pointing at the new file.

## Step 5 — Verify

Run `swift build`. A clean build means all four edits are consistent. If the build "succeeds" but the category doesn't appear, you almost certainly skipped Step 4 (source not listed) — re-check `Package.swift`.
