# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

MAC-LIMPO is a native macOS menu-bar app (SwiftUI + AppKit) for freeing disk space. It has two surfaces: a popover with cleaning-category cards, and a separate "Disk Map" window showing an interactive treemap of disk usage. Built with Swift Package Manager (not an Xcode project by default — the `.xcodeproj` is generated on demand).

## Commands

```bash
make help                   # list every target
swift build                 # debug build
swift build -c release      # release build
swift run                   # build and launch the app (look for the trash icon in the menu bar)
swift test                  # run unit tests (Tests/MACLIMPOTests)
make app                    # assemble + sign build/app/MAC-LIMPO.app  (Scripts/bundle-app.sh)
make installer              # → build/MAC-LIMPO-<version>.pkg          (Installer/build-installer.sh)
make dmg                    # → MAC-LIMPO.dmg                          (./create_installer.sh)
./create_xcode_project.sh   # generate an Xcode project if you need the IDE
swiftformat . && swiftlint  # format + lint (configs: .swiftformat, .swiftlint.yml)
```

### Packaging

`Scripts/bundle-app.sh` is the **single** place the `.app` is assembled — Info.plist
generation, icon compilation and codesigning all live there, and both the `.pkg` and
the `.dmg` consume its output at `build/app/MAC-LIMPO.app`. Never re-implement bundling
in a distribution script; the two used to diverge in plist and signature silently.
It picks a signing identity from the keychain (Developer ID → Apple Development →
ad-hoc), overridable with `IDENTITY=`.

`Installer/` holds the native `.pkg`: `Distribution.xml` (welcome/license/conclusion
pages in `Installer/Resources/*.html`), `Installer/Scripts/{preinstall,postinstall}`
which run as root, and `uninstall-mac-limpo`, which ships to
`/usr/local/bin/mac-limpo-uninstall`. `build-installer.sh` **disables bundle
relocation** and then re-expands the built package to assert no `<relocate>` block
came back — with relocation on, the installer follows Spotlight to any existing copy
of the bundle id and overwrites the dev build as root instead of installing to
`/Applications`.

Anything added under `Installer/` or `Scripts/` must stay in the `exclude:` list in
`Package.swift`, or SPM warns about unhandled files on every build.

The `MACLIMPOTests` target `@testable import MAC_LIMPO`s the executable (note the underscore — hyphens in the target name become underscores in the module name). VS Code launch configs live in `.vscode/launch.json` (Swift extension).

Requires macOS 13+, Swift 5.9.

## Architecture

**MVVM with a service registry.** Flow: menu bar → `MenuBarViewModel` → per-category `CleaningService` implementations.

- `MACLIMPOApp.swift` — `@main` entry. `AppDelegate` sets `NSApp.setActivationPolicy(.accessory)` (no Dock icon), creates the `NSStatusItem`, hosts `MenuBarView` in an `NSPopover`, and lazily opens the treemap in a standalone `NSWindow`. Also enforces single-instance via `NSRunningApplication`.
- `Views/MenuBarView.swift` — contains **both** `MenuBarViewModel` (the `ObservableObject`) and the SwiftUI view. The viewmodel holds `services: [CleaningCategory: CleaningService]` — **this dictionary is the service registry**.

**Most cleaners subclass `PathBasedCleaningService`** (`Services/PathBasedCleaningService.swift`) — a tested base that implements `scan`/`clean` once for services that just measure and remove a list of paths. A subclass is ~10 lines: `super.init(category:targets:)` with `[CleanTarget]` (each has a path, optional label, `.removeItem`/`.removeContents` strategy, and optional age filter). Deletions go to the **Trash** (reversible) via `FileSystemHelper.trashItem`, falling back to permanent removal only if the Trash rejects the path. Only services with genuine custom logic (Docker/tool-based, `SystemDataCleaningService`, `VarFoldersCleaningService` allow/deny traversal, `ProjectCleaningService`, glob/enumerator-based ones) implement `CleaningService` directly.

**Adding a new cleaning category** requires four coordinated edits:
1. Create `Services/<Name>CleaningService.swift` — subclass `PathBasedCleaningService` (preferred) or implement `CleaningService` directly for custom logic. Use the `add-cleaning-service` skill.
2. Add the `case` to the `CleaningCategory` enum in `Models/CleaningCategory.swift`, and fill in its `group`, `icon` (SF Symbol), `color` (hex), and `description` switches — the enum is `CaseIterable`, so a missing switch case fails to compile.
3. Register it in the `services` dictionary in `Views/MenuBarView.swift`.
4. Add the source file path to the `sources:` array in `Package.swift` — **SPM sources are listed explicitly, not globbed.** A new `.swift` file that isn't listed silently won't compile in.

**`Package.swift` quirk:** every source file is enumerated in `sources:`, and many docs/scripts (including the `Services/*.md` design notes and helper `.sh` scripts) are in `exclude:`. When adding or renaming files, update both the sources list and, if needed, excludes.

### The CleaningService contract (`Services/CleaningService.swift`)

```swift
protocol CleaningService {
    var category: CleaningCategory { get }
    func scan(progress: ((String) -> Void)?) async -> ScanResult   // estimate, non-destructive
    func clean() async -> CleaningResult                            // actually deletes
}
```

Services subclass `BaseCleaningService` to get `fileHelper` (`FileSystemHelper.shared`) and `shell` (`ShellExecutor.shared`). Conventional shape: a hardcoded list of `~/…` paths, `scan` sums `fileHelper.sizeOfDirectory` and returns a `ScanResult`; `clean` removes each path via `fileHelper.removeItem` and returns a `CleaningResult` (bytesRemoved, filesRemoved, errors, executionTime, success). Deletions are **permanent** — there is no trash/undo. Prefer targeting cache/derived paths, never user documents.

### Shared utilities (singletons)

- `FileSystemHelper.shared` — `expandPath`, `fileExists`, `sizeOfDirectory`, `removeItem`, `formatBytes`, `availableDiskSpace`/`totalDiskSpace`.
- `ShellExecutor.shared` — runs commands via `/bin/zsh -c` with a hardcoded `PATH` (Homebrew, cargo, etc.) so tools like `docker`/`brew` resolve; supports a `timeout` (polls, then `terminate()`s). Use for tool-based cleaners (Docker, Homebrew).
- `logger` — a **global** (`let logger = Logger.shared` in `Services/Logger.swift`) wrapping `os.log`. Call `logger.log(msg, level:)`. Messages in this codebase are typically Portuguese; UI-facing strings are English.
- `PermissionsHelper` — Full Disk Access checks. Some cleaners need FDA or sudo.

### Disk Map / treemap

- `Services/DiskMapService.swift` — parallel directory scan using `withTaskGroup`; progress is tracked through an `actor ProgressCounter` and pushed to the UI via `MainActor.run`.
- `ViewModels/TreemapViewModel.swift`, `Views/TreemapView.swift` / `TreemapWindowView.swift`, `Utilities/TreemapLayout.swift` (squarified layout), `Models/FileNode.swift` (hierarchical node model).

## Conventions

- 4-space indentation; UI/user-visible strings in English, log/comments often Portuguese.
- `Color(hex:)` extension lives in `Models/CleaningCategory.swift`.
- Design notes for the project live as `Services/*.md` files (excluded from the build) and `docs/`.
