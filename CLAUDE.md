# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

MAC-LIMPO is a native macOS menu-bar app (SwiftUI + AppKit) for freeing disk space. It has two surfaces: a popover with cleaning-category cards, and a separate "Disk Map" window showing an interactive treemap of disk usage. Built with Swift Package Manager (not an Xcode project by default — the `.xcodeproj` is generated on demand).

## Commands

```bash
swift build                 # debug build
swift build -c release      # release build
swift run                   # build and launch the app (look for the trash icon in the menu bar)
./create_installer.sh       # release build → .app bundle (ad-hoc codesigned) → MAC-LIMPO.dmg
./create_xcode_project.sh   # generate an Xcode project if you need the IDE
```

There is **no test target** — `Package.swift` defines only the executable. VS Code launch configs live in `.vscode/launch.json` (Swift extension).

Requires macOS 13+, Swift 5.9.

## Architecture

**MVVM with a service registry.** Flow: menu bar → `MenuBarViewModel` → per-category `CleaningService` implementations.

- `MACLIMPOApp.swift` — `@main` entry. `AppDelegate` sets `NSApp.setActivationPolicy(.accessory)` (no Dock icon), creates the `NSStatusItem`, hosts `MenuBarView` in an `NSPopover`, and lazily opens the treemap in a standalone `NSWindow`. Also enforces single-instance via `NSRunningApplication`.
- `Views/MenuBarView.swift` — contains **both** `MenuBarViewModel` (the `ObservableObject`) and the SwiftUI view. The viewmodel holds `services: [CleaningCategory: CleaningService]` — **this dictionary is the service registry**.

**Adding a new cleaning category** requires four coordinated edits:
1. Create `Services/<Name>CleaningService.swift` implementing the `CleaningService` protocol.
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
