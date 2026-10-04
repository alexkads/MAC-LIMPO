# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

MAC-LIMPO is a free, open-source (GPL-3.0-or-later) native macOS menu-bar app (SwiftUI + AppKit) for freeing disk space. It has two surfaces: a popover with the cleaning categories, and a separate "Disk X-Ray" window that maps every byte of the disk. Built with Swift Package Manager (not an Xcode project by default — the `.xcodeproj` is generated on demand).

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

Requires macOS 27.0+, Swift 6.4, and Xcode 27.

## Architecture

**MVVM with a service registry.** Flow: menu bar → `MenuBarViewModel` → per-category `CleaningService` implementations.

- `MACLIMPOApp.swift` — `@main` entry. `AppDelegate` sets `NSApp.setActivationPolicy(.accessory)` (no Dock icon), creates the `NSStatusItem`, hosts `MenuBarView` in an `NSPopover`, and lazily opens the Disk X-Ray in a standalone `NSWindow`. Also enforces single-instance via `NSRunningApplication`.
- `Views/MenuBarView.swift` — contains **both** `MenuBarViewModel` (the `ObservableObject`) and the SwiftUI view. The viewmodel reads `services` from `CleaningServiceRegistry.shared` (`Services/CleaningServiceRegistry.swift`) — **the registry is the single source of truth**, shared with App Intents and Apple Intelligence.

**Most cleaners subclass `PathBasedCleaningService`** (`Services/PathBasedCleaningService.swift`) — a tested base that implements `scan`/`clean` once for services that just measure and remove a list of paths. A subclass is ~10 lines: `super.init(category:targets:)` with `[CleanTarget]` (each has a path, optional label, `.removeItem`/`.removeContents` strategy, and optional age filter). Deletions go to the **Trash** (reversible) via `FileSystemHelper.trashItem`, falling back to permanent removal only if the Trash rejects the path. Only services with genuine custom logic (Docker/tool-based, `SystemDataCleaningService`, `VarFoldersCleaningService` allow/deny traversal, `ProjectCleaningService`, glob/enumerator-based ones) implement `CleaningService` directly.

**Adding a new cleaning category** requires four coordinated edits:
1. Create `Services/<Name>CleaningService.swift` — subclass `PathBasedCleaningService` (preferred) or implement `CleaningService` directly for custom logic. Use the `add-cleaning-service` skill.
2. Add the `case` to the `CleaningCategory` enum in `Models/CleaningCategory.swift`, and fill in its `group`, `icon` (SF Symbol), `color` (hex), and `description` switches — the enum is `CaseIterable`, so a missing switch case fails to compile.
3. Register it in `Services/CleaningServiceRegistry.swift`.
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

Services subclass `BaseCleaningService` to get `fileHelper` (`FileSystemHelper.shared`) and `shell` (`ShellExecutor.shared`). Conventional shape: a hardcoded list of `~/…` paths, `scan` sums `fileHelper.sizeOfDirectory` and returns a `ScanResult`; `clean` removes each path and returns a `CleaningResult` (bytesRemoved, filesRemoved, errors, executionTime, success). `PathBasedCleaningService` moves items to the **Trash** (`fileHelper.trashItem`) and only falls back to `removeItem`; tool-based cleaners (docker prune, brew cleanup, simctl) remove permanently. Prefer targeting cache/derived paths, never user documents, and keep `scan` reporting exactly what `clean` will try to remove.

### Shared utilities (singletons)

- `FileSystemHelper.shared` — `expandPath`, `fileExists`, `sizeOfDirectory`, `removeItem`, `formatBytes`, `availableDiskSpace`/`totalDiskSpace`.
- `ShellExecutor.shared` — runs commands via `/bin/zsh -c` with a hardcoded `PATH` (Homebrew, cargo, etc.) so tools like `docker`/`brew` resolve; supports a `timeout` (polls, then `terminate()`s). Use for tool-based cleaners (Docker, Homebrew).
- `logger` — a **global** (`let logger = Logger.shared` in `Services/Logger.swift`) wrapping `os.log`. Call `logger.log(msg, level:)`. Messages in this codebase are typically Portuguese; UI-facing strings are English.
- `PermissionsHelper` — Full Disk Access checks. Some cleaners need FDA or sudo.

### Disk X-Ray

Full-disk map: summary by file category, native folder tree, file-type panel, largest files and a treemap, all in sync. Inspired by WinDirStat (see NOTICE) but with its own look — keep the macOS-native design.

- `Services/DiskScanner.swift` — reads folders in bulk with `getattrlistbulk(2)` (the `NtQueryDirectoryFile` equivalent WinDirStat uses: name, type, alloc/logical size, mtime, inode for many entries per call) with worker threads pulling folders from a shared queue, then one pre-order pass builds the index. APFS has no MFT-like fast path, so parallelism is the lever. With `FSOPT_PACK_INVAL_ATTRS`, dir attributes are absent from file entries and vice versa (parse by `returned.dirattr`). Physical = allocated size, hard links once, mount points not crossed.
- `Utilities/ScanTuning.swift` — threads/buffer per machine and volume, never fixed: local SSD → one per active core clamped to 4…16 (on a 10-core M-series 8–16 all give ~16 s for 2.9M items vs 52 s with 1), rotational disk (IOKit "Medium Type") → 2, network volume (`!MNT_LOCAL`) → 4 threads + 64 KiB buffer.
- `Models/DiskScanIndex.swift` — every item as an index into parallel arrays (no object per file). Pre-order indices make a subtree the contiguous range `i+1…subtreeEnd[i]`. Extension key: from the last `.`, lowercased, `""` if none.
- `Models/FileCategory.swift` — extension → category (Video, Images, Source Code, Builds & Libraries, Disk Images & VMs…) with color and SF Symbol; drives the map colors, summary chips and the Types panel.
- `Utilities/TreemapRenderer.swift` — squarified treemap drawn with CoreGraphics off the main thread. Folder frames (padding + header) only on large, shallow folders; gaps/rounded corners only on tiles big enough — otherwise small files end up as islands. Single-child folder chains collapse into one header. `Rendering.scale` is the scale it was drawn at; display, highlight and hit-testing must use it (the window can move between 1x and 2x screens). `Source` closures are `@Sendable` on purpose (created on the MainActor, called on the render thread).
- `Views/DiskXRayFileTree.swift` — the folder tree is a native `NSOutlineView`; the model only bumps `treeVersion` (reload, keeping expansion) and `revealToken` (expand path, select, scroll). Folder icons load asynchronously. Don't move it back to a SwiftUI list — that made navigation slow.
- `ViewModels/DiskXRayViewModel.swift` — free space and "System & Unaccounted" (= APFS container used − scanned) pseudo items, On Disk/Logical sizes, type filter (dims the rest of the map), zoom/breadcrumbs, largest files, Move to Trash (never the scan root, home or its top-level folders).
- The window is hosted by an `NSHostingController` with `sceneBridgingOptions = [.toolbars, .title]`, so `.toolbar` in `DiskXRayWindowView` becomes the window's native `NSToolbar`.
- `Models/DiskXRay.swift` — `DiskOverview` (APFS container from `diskutil apfs list -plist`) and `Firmlinks`.

### Themes and the native popover

`AppTheme` (`Models/Theme.swift`): **Liquid Glass** (default, first in the picker), Classic, Cyberpunk, Matrix. `ThemePalette.surfaceStyle` (`solid`/`neon`/`glass`) says how surfaces are built. With Liquid Glass, `MenuBarView` renders `NativeMenuBarView` — **system components only** (List/Section, Gauge, LabeledContent, Picker, Toggle, ProgressView, NSSearchField) plus native glass (`glassEffect`, `GlassEffectContainer`, `.glass`/`.glassProminent`) on controls and floating panels; never simulate glass with blur. Content stays on semantic fills (no glass-on-glass). Shared modifiers live in `Views/Components/ThemeStyles.swift`. Respect Reduce Transparency/Motion and Increase Contrast.

### Distribution without a Developer ID

`docs/install.sh` (published at `https://alexkads.github.io/MAC-LIMPO/install.sh`) checks the Mac, downloads the latest release source, builds with `Scripts/bundle-app.sh` and installs into `/Applications` — locally built apps carry no quarantine flag, so Gatekeeper doesn't block them. Keep it POSIX `sh` and `shellcheck`-clean.

### Website

MkDocs Material in `docs/` (+ `overrides/` for Open Graph/JSON-LD), English and Portuguese via suffix files (`page.pt.md`), published to the `gh-pages` branch with `make docs-deploy` (`mkdocs gh-deploy`; `.github/workflows/pages.yml` is a manual alternative). `docs/cleaning.md` lists the categories — regenerate it when categories change. `mkdocs build --strict` must pass.

### Development hooks (env vars)

`MACLIMPO_THEME`, `MACLIMPO_APPEARANCE=light|dark`, `MACLIMPO_OPEN_XRAY=1`, `MACLIMPO_XRAY_ROOT=<folder>`, `MACLIMPO_XRAY_LOGICAL=1`, `MACLIMPO_XRAY_DEMO=1`, `MACLIMPO_SNAPSHOT=<png>` / `MACLIMPO_SNAPSHOT_POPOVER=<png>` with `MACLIMPO_SNAPSHOT_DELAY`. Snapshots use `cacheDisplay`, which does **not** render Liquid Glass materials — verify glass on screen.

## Conventions

- 4-space indentation; UI/user-visible strings in English, log/comments often Portuguese.
- `Color(hex:)` extension lives in `Models/CleaningCategory.swift`.
- Design notes for the project live as `Services/*.md` files (excluded from the build) and `docs/`.
