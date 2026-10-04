---
description: Build MAC-LIMPO from source, open it in Xcode, run the tests, add a cleaning category and understand the architecture.
---

# Development

## Requirements

- macOS 27+ on Apple silicon
- Xcode 27, or the Command Line Tools with Swift 6.4

## Build, run and test

```bash
git clone https://github.com/alexkads/MAC-LIMPO.git
cd MAC-LIMPO
swift build          # debug build
swift run            # launch (menu bar icon)
swift test           # unit tests
swiftformat . && swiftlint
make help            # app bundle, .pkg installer, .dmg
```

### Xcode

The project is a Swift package — there is no `.xcodeproj` to keep in sync. Open it with:

```bash
open Package.swift
```

Xcode resolves the package and creates the **MAC-LIMPO** scheme. ⌘R runs the app, ⌘U runs the test suite.
Running from Xcode launches the bare executable (no app bundle); `make app` builds the signed
`build/app/MAC-LIMPO.app` with icon and `Info.plist`.

## Architecture

```
MACLIMPOApp.swift      NSStatusItem + NSPopover (menu bar) and the Disk X-Ray NSWindow
Views/                 SwiftUI: MenuBarView, NativeMenuBarView (Liquid Glass), DiskXRay*, Components/
ViewModels/            DiskXRayViewModel
Services/              One CleaningService per category, CleaningServiceRegistry, DiskScanner
Models/                CleaningCategory, Theme, CleaningResult, DiskScanIndex, FileCategory
Utilities/             FileSystemHelper, ShellExecutor, TreemapRenderer, ScanTuning, SizeFormat
Tests/MACLIMPOTests/   XCTest
docs/                  This website (MkDocs) and install.sh
Installer/, Scripts/   .pkg installer and app bundling
```

- **Cleaning** — the popover's view model asks every `CleaningService` for a `scan` (estimate, read-only) and
  calls `clean` on demand. Most services subclass `PathBasedCleaningService`, which measures and trashes a list
  of `CleanTarget`s; tool-based ones (Docker, Homebrew, simulators) implement the protocol directly.
- **Disk X-Ray** — `DiskScanner` reads folders in bulk with `getattrlistbulk(2)` across worker threads
  (`ScanTuning` picks the count from the hardware and the volume type), then builds a pre-order
  `DiskScanIndex` of parallel arrays (no object per file). `TreemapRenderer` draws a squarified treemap with
  CoreGraphics off the main thread; the folder tree is a native `NSOutlineView`.
- **Themes** — `AppTheme` × `SurfaceStyle` (`solid`, `neon`, `glass`). The default *Liquid Glass* theme renders
  the popover with system components only (`NativeMenuBarView`); shared styling lives in `ThemeStyles.swift`.

[CLAUDE.md](https://github.com/alexkads/MAC-LIMPO/blob/main/CLAUDE.md) has the detailed notes (also used by AI
coding agents).

## Adding a cleaning category

1. Create `Services/<Name>CleaningService.swift`, preferably subclassing `PathBasedCleaningService`:

    ```swift
    final class FigmaCleaningService: PathBasedCleaningService, @unchecked Sendable {
        init() {
            super.init(category: .figmaCache, targets: [
                CleanTarget("~/Library/Application Support/Figma/DesktopProfile/v34/Cache", strategy: .removeContents)
            ])
        }
    }
    ```

2. Add the case to `CleaningCategory` and fill in `group`, `icon`, `color` and `description`.
3. Register it in `Services/CleaningServiceRegistry.swift`.
4. List the file in `Package.swift` → `sources:` (sources are explicit).
5. Add tests for any rule that decides what is deleted.

Safety rules: only caches/build output that tools recreate, prefer the Trash, `scan` must match `clean`, and
never interpolate paths into shell commands.

## Development hooks

Environment variables for screenshots and debugging (no effect in normal use):

| Variable | Effect |
|---|---|
| `MACLIMPO_THEME=liquidGlass` | Start with a theme without saving the preference |
| `MACLIMPO_APPEARANCE=light\|dark` | Force the appearance |
| `MACLIMPO_OPEN_XRAY=1` | Open the Disk X-Ray at launch |
| `MACLIMPO_XRAY_ROOT=<folder>` | Scan a folder instead of the whole disk |
| `MACLIMPO_SNAPSHOT=<png>` | Save a picture of the Disk X-Ray window after `MACLIMPO_SNAPSHOT_DELAY` seconds |
| `MACLIMPO_SNAPSHOT_POPOVER=<png>` | Same for the popover |

## Releasing

1. Update `CHANGELOG.md`, bump `VERSION` and `BUILD_NUMBER` in `Scripts/bundle-app.sh`.
2. `swift test && make installer` → `build/MAC-LIMPO-<version>.pkg`.
3. Commit, tag `v<version>`, push, and create a GitHub release with the `.pkg`. The `install.sh` script picks up
   the latest release automatically.

## Website

Built with [MkDocs Material](https://squidfunk.github.io/mkdocs-material/) from `docs/` and published to the
`gh-pages` branch, which GitHub Pages serves:

```bash
make docs-serve     # preview at http://127.0.0.1:8000
make docs-deploy    # build and publish (maintainers)
```

Translations use the suffix convention: `page.md` (English) and `page.pt.md` (Portuguese).
