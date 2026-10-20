---
name: add-cleaning-service
description: Scaffold a new disk-cleaning category in MAC-LIMPO end-to-end. Use whenever adding a cleaning category/service (e.g. "add a Figma cache cleaner", "criar service para limpar cache do X"). Performs the four coordinated edits SPM requires so the new service actually compiles and appears in the UI, then translates it and updates the site.
---

# Adding a cleaning category to MAC-LIMPO

Adding a category is **four coordinated edits** (service, enum, registry, `Package.swift`). Missing any one fails to compile or leaves the category invisible. The `sources:` array in `Package.swift` is the one people forget — SPM does not glob, so an unlisted `.swift` file is silently excluded from the build.

Before inventing a new category, check whether the paths belong in an existing one (e.g. a new editor's cache → `IDECacheCleaningService`, an AI CLI → `AIToolsCleaningService`, an Electron chat app → `MessagingAppsCleaningService`). Adding a `CleanTarget` to an existing service is a one-line change and skips everything below except translation (if a label is user-visible) and Step 8.

## Inputs to gather first

Ask the user (or infer from the request) if not given:
- **Case name** — lowerCamelCase enum case, e.g. `figmaCache`.
- **Display name** — the enum `rawValue` and English UI name, e.g. `"Figma Cache"`. The rawValue is a stable identity (ids, logs) — never shown directly.
- **Paths to clean** — the `~/…` cache/derived paths that the tool **recreates by itself**. Never user documents, settings, sessions or anything that would sign the user out or lose work. Look at the real folder on this Mac (`du -sh`, `ls`) before deciding.
- **Group** — one of `.development`, `.system`, `.apps`, `.communication`, `.media`.
- **Icon** — an SF Symbol name. **Verify it exists** (an invalid symbol renders blank) — e.g. `swift -e 'import AppKit; print(NSImage(systemSymbolName: "<name>", accessibilityDescription: nil) != nil)'`.
- **Color** — a 6-digit hex (brand color when possible), with a `// Brand` comment like its neighbours.
- **Description** — one short English sentence saying what is removed (and what is kept, if that's reassuring).

Pick a `<Name>` for the file/class (UpperCamelCase, e.g. `FigmaCache`) → file `Services/<Name>CleaningService.swift`, class `<Name>CleaningService`.

Choose the shape:
- **Path-based** (default, almost always) — subclass `PathBasedCleaningService` and list `CleanTarget`s. You get parallel measuring, Trash-first removal, age filters, aggressive mode and Full Disk Access filtering for free, and `scan` always reports exactly what `clean` removes.
- **Custom** — implement `CleaningService` directly on `BaseCleaningService` only when there is real logic: a CLI must run (`docker system prune`, `brew cleanup`, `simctl`), a version policy (keep newest per major — `NvmCleaningService`, `DotnetSdkCleaningService`), or a project search (`ProjectCleaningService`, `RustTargetsCleaningService`). Even then, reuse `PathBasedCleaningService` for the plain-path part (see how `HomebrewCleaningService` wraps one for its cache).

## Step 1 — Create the service file

### Path-based (mirror `Services/ZedCleaningService.swift` / `Services/NotionCleaningService.swift`)

```swift
import Foundation

/// <Portuguese doc comment: what is removed, why it is safe, what is kept.>
final class <Name>CleaningService: PathBasedCleaningService, @unchecked Sendable {
    init() {
        super.init(category: .<caseName>, targets: [
            CleanTarget("~/Library/Caches/<bundle.id>", strategy: .removeContents),
            CleanTarget("~/Library/Application Support/<App>/Cache", label: "<App> cache", strategy: .removeContents),
            CleanTarget("~/Library/Logs/<App>", label: "<App> logs", olderThanDays: 30)
        ])
    }
}
```

`CleanTarget(_ path, label:, strategy:, olderThanDays:, aggressive:)`:
- `strategy: .removeItem` (default) removes the path itself; `.removeContents` keeps the folder and removes its children — use it when the app expects the folder to exist.
- `label` — the name shown in the scan report (default: last path component). Report labels are not localized (like the existing ones).
- `olderThanDays` — only items not modified for N days (applied per child with `.removeContents`).
- `aggressive: true` — only when the user turned on **Aggressive cleaning**: large caches that are regenerable but expensive to rebuild (models, runtimes, full image sets). Say so in the description.
- Paths in TCC-protected areas (`PermissionsHelper.requiresFullDiskAccess`) are skipped automatically without Full Disk Access — don't special-case them.

Deletions go to the **Trash** (`fileHelper.trashItem`), falling back to permanent removal only when the Trash rejects the path.

### Custom

```swift
import Foundation

final class <Name>CleaningService: BaseCleaningService, CleaningService, @unchecked Sendable {
    let category: CleaningCategory = .<caseName>

    func scan(progress: (@Sendable (String) -> Void)?) async -> ScanResult {
        progress?(String(localized: "Checking <Tool>…"))
        guard await runBlocking({ self.shell.checkCommandExists("<tool>") }) else {
            return ScanResult(category: category, estimatedSize: 0, itemCount: 0, items: [])
        }
        let output = await runBlocking { self.shell.execute("<tool> <dry-run>", timeout: 120).output }
        // parse into items/estimatedSize — keep the parser a `static func` so it can be unit-tested
        ...
    }

    func clean() async -> CleaningResult {
        let startTime = Date()
        let result = await runBlocking { self.shell.execute("<tool> <prune>", timeout: 600) }
        var errors: [String] = []
        if result.exitCode != 0 {
            errors.append(String(localized: "<tool> failed: \(String(result.error.prefix(200)))"))
        }
        logger.log("<Name>: limpeza concluída", level: .info)
        return CleaningResult(category: category, bytesRemoved: ..., filesRemoved: ...,
                              errors: errors, executionTime: Date().timeIntervalSince(startTime), success: errors.isEmpty)
    }
}
```

Rules for custom services:
- Wrap anything blocking (shell commands, `sizeOfDirectory`, directory walks) in `runBlocking { }` (`Utilities/Deadline.swift`) — blocking inside an `async` `scan` starves the cooperative pool and the cards spin forever.
- Always pass a `timeout:` to `shell.execute`; a missing tool or a stopped daemon (`docker info`) is a no-op, not an error.
- Never interpolate a path or user-controlled string into `shell.execute` (it goes through `zsh -c`); pass paths as arguments with `shell.run("/usr/bin/<tool>", [args], timeout:)`, which runs the binary without a shell.
- Tool-based removal is permanent — say so in the description if it matters, and keep `scan` estimating exactly what `clean` will remove.
- Anything that needs an admin password follows `DotnetSdkCleaningService` (one prompt for the whole batch) and is mentioned in the description.

Conventions: log messages/comments in Portuguese; UI-facing strings in English via `String(localized:)`; 4-space indent; `fileHelper`/`shell` come from `BaseCleaningService`, `logger` is a global.

## Step 2 — Extend the enum in `Models/CleaningCategory.swift`

The enum is `CaseIterable` and every `switch` over it is exhaustive, so a new case missing from **any** of these fails to compile:
1. `case <caseName> = "<Display Name>"` in the right section (the newest block is `// Dev tooling e IA`).
2. `group` — add `.<caseName>` to the chosen group's case list.
3. `displayName` — `case .<caseName>: String(localized: "<Display Name>")`.
4. `icon` — `case .<caseName>: "<sf.symbol>"` (expression-style switch, no `return`).
5. `color` — `case .<caseName>: Color(hex: "<hex>") // <Brand> <color>`.
6. `description` — `case .<caseName>:` then `String(localized: "<one sentence>")` on the next line.

Any message the service shows (`progress?(…)`, `CleaningResult.errors`) is `String(localized: "…")` too, in English, with interpolation for the variable parts — never a dynamic key.

## Step 3 — Register in `Services/CleaningServiceRegistry.swift`

Add to the `services` dictionary (the single source of truth, shared by the popover, App Intents and Apple Intelligence):
```swift
.<caseName>: <Name>CleaningService(),
```
The last entry has no trailing comma — fix commas when appending at the end.

## Step 4 — Add to `Package.swift` sources — DO NOT SKIP

In the `sources:` array add:
```swift
"Services/<Name>CleaningService.swift",
```
Without this the file compiles nowhere — Step 3 then fails with "cannot find '<Name>CleaningService' in scope", which is the tell.

## Step 5 — Test

- Path-based with only fixed paths: `PathBasedCleaningServiceTests` already covers the mechanics; no new test needed.
- Any rule that decides what is deleted (version policy, parser of a tool's output, age/keep logic) gets a test in `Tests/MACLIMPOTests/<Name>CleaningServiceTests.swift` (see `NvmCleaningServiceTests`, `HomebrewCleaningServiceTests`). Tests that create files use a temp dir and `useTrash: false`. The test target is not enumerated — no `Package.swift` edit for test files.

## Step 6 — Translate

The app is English + Brazilian Portuguese. Run `make strings` (extracts every localizable string into `Localization/Localizable.xcstrings`), then add the `pt-BR` value for each new key — name, description and messages — using macOS terms ("Lixo", "Acesso Total ao Disco"). `swift test` fails (`LocalizationTests`) while any key lacks Portuguese or a translation changes its `%@`/`%lld` placeholders.

## Step 7 — Verify

`swift build && swift test`. Then check it in the app: `swift run`, open the popover and confirm the card appears in its group with the icon and a sensible scan size (`MACLIMPO_SNAPSHOT_POPOVER=<png>` captures it headless).

## Step 8 — Update the website and READMEs

- `docs/cleaning.md` — add the row (`| **<Display Name>** | <description> |`) to its group's table, alphabetical by display name, and bump the count in the intro sentence.
- The same count appears in `docs/index.md`, `docs/index.pt.md`, `README.md` and `README.pt-BR.md` (`grep -rn "46 cleaning\|46 categorias"` with the current number) — bump all of them, and add the tool to the group's list in both READMEs if it's notable.
- `mkdocs build --strict -d <scratch dir>` must pass.
- `CHANGELOG.md` — a `### ✨ Adicionado` entry under `## [Unreleased]` (Portuguese, `- **<Name>**: …`).

## Step 9 — Ship it

The new category reaches users only through a GitHub release (installed apps update themselves from it; the published `install.sh` builds the latest release, not `main`). Use the `release` skill.
