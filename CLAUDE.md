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
make dmg                    # → build/MAC-LIMPO-<version>.dmg          (./create_installer.sh)
make strings                # refresh Localization/Localizable.xcstrings from the code (then translate pt-BR)
make docs-deploy            # publish the site + install.sh to gh-pages (release first — see Releasing)
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

Requires macOS 26.6+ (Apple silicon), Swift 6.4, and Xcode 27 (which itself needs macOS 26.6+).

## Architecture

**MVVM with a service registry.** Flow: menu bar → `MenuBarViewModel` → per-category `CleaningService` implementations.

- `MACLIMPOApp.swift` — `@main` entry. `AppDelegate` sets `NSApp.setActivationPolicy(.accessory)` (no Dock icon), creates the `NSStatusItem`, hosts `MenuBarView` in an `NSPopover`, and lazily opens the Disk X-Ray in a standalone `NSWindow`. Also enforces single-instance via `NSRunningApplication`. After an install it shows a welcome balloon anchored to the status item (`Views/WelcomeView.swift`; `WelcomeGate`: launched with `--welcome` — both `install.sh` and the `.pkg` postinstall pass it — or first launch ever), falling back to a floating `NSAlert` when the icon isn't on screen (notch, full menu bar). With several displays it appears on the one whose menu bar is active.
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
- `Utilities/TreemapRenderer.swift` — squarified treemap built off the main thread. The `Painter` emits a list of `Shape`s (rounded rects with gradient or rings, in scene pixels, clipped near the drawn area so they fit in Float) plus a text-only `labels` bitmap (CoreText). **2D** (default, `Style.cushions == false`): `rasterize` draws the shapes with CoreGraphics into `Rendering.image` — the original look, displayed as cropped `Image` layers. **3D** (toolbar cube, `DiskXRayViewModel.map3D`, persisted): the shapes go to `Utilities/TreemapMetal.swift`, which draws every layer on the GPU (instanced quads, SDF rounded rects) with van Wijk cushion shading — `Cushion` accumulates a parabola per nesting level in Double and each tile carries its slopes (`Shape.cushion`), so the relief is identical at any magnification. The shader is compiled at runtime from a string (SPM has no `.metal` processing) — `TreemapMetalTests` catches compile errors, which otherwise silently disable 3D (`half` is a Metal type, don't use it as a name). Layers stretched past Float precision are transformed in Double on the CPU (`stretchedLayer`). `cacheDisplay` can't see Metal layers, so the snapshot hook composes `MetalSnapshotting.snapshotImage()` on top. Both modes draw the same tile labels and folder header bands (toolbar "Labels" toggle, `showLabels` → `Style.labels`, persisted; off = no labels/bands, layout unchanged) (in 3D the bands are Metal shapes and the text a texture; the user prefers them over a text-free relief). On top, in both modes, the name shows as a hover tooltip shaped like a 3D flag (Mario-style pole with a gold ball + waving cloth, `Utilities/TreemapFlags.swift`, cached sprites), that behaves like a system tooltip (`HoverState.pointerMoved`): nothing while the pointer moves, it appears ~0.7 s after the pointer rests, stays planted where it stopped (near the right edge it flips — pole on the right, cloth opening left, text unmirrored — so the pole stays at the pointer: `TreemapFlags.tooltip`; top/bottom edges push it inside) and hides on real movement (> 3 pt), exit, click, zoom or pan. An earlier version planted flags on the map; it was too cluttered — don't bring it back.
- Layout (both modes): the layout is **pure squarify of the sizes** (area ∝ size, identical at any magnification): folder frames (padding as a stroke + 15 pt header band, only on large, shallow folders) are drawn *over* the children, never carved out of them — carving them in screen pixels made the magnifier reshuffle the blocks. Labels start below a covering header band (`labelTop`), at most two bands stack, and `Rendering.headers` makes a click on a band hit the folder. Gaps/rounded corners only on tiles big enough — otherwise small files end up as islands. Children under half a pixel aren't drawn; squarify leaves them together at the end of the folder, and `fillTail` paints that area first with the largest one's colour — without it, folders with thousands of tiny files (node_modules, caches, .git/objects) showed background-coloured holes (very visible in 3D). In the cushion shader the slope is capped (`steep`) so deeply nested corners don't go black. Single-child folder chains collapse into one header. `Rendering.scale` is the scale it was drawn at; display, highlight and hit-testing must use it (the window can move between 1x and 2x screens). `Source` closures are `@Sendable` on purpose (created on the MainActor, called on the render thread).
- Magnifier (pinch): `DiskXRayViewModel.viewport` is the visible part of the map in unit coordinates (side = 1/magnification, ≤ 10⁸× — a 1 KB file on a 500 GB disk needs ~2,000×). `TreemapRenderer.render(viewport:)` lays out on a virtual canvas that large and draws only what lands in the bitmap (off-screen subtrees are skipped, labels clamp to the visible part, one more header level per 2×). Rects become billions of pixels, and CoreGraphics rasterizes in single precision, so tiles/frames are clipped to `nearScreen` before reaching the context. Because the layout is magnification-invariant, `TreemapRenderer.locate(path,in:)` finds any item's rect by walking squarify down its lineage — no render, works off-screen and sub-pixel (`DiskXRayViewModel.unitRect(of:)`). `magnifyToSelection` flies there in one animation (`viewport(fitting:)`; thin slivers are magnified by their thickness), and a selection from the tree/list (`select(_, reveal: false)`) brings it into view Google-Maps style (`bringIntoView`): too small to read → magnify until it spans ~⅓ of the screen, but never past its parent folder filling the screen; bigger than the screen → zoom out to fit; otherwise only pan, and only if mostly off-screen. Map clicks never move the map. When the selection changes, the blue box slides/resizes from the old item to the new one in map coordinates (`selectionMove`, ~0.35 s ease-out, so it tracks a simultaneous auto-zoom) and a pulse ring marks the arrival; the highlight Canvas sits in a `TimelineView` that only ticks during that. A selection too small for an outline (< 10 pt) gets a Google-Maps-style pin with name · size (`pin`, at `selectionMarker()`, cached per selection/root/generation). 0-byte items have no area — `locate` returns nil for them and `mapAnchor(for:)` falls back to the nearest ancestor with size (it used to land in the map's top-left corner at 10⁸×). Far destinations fly over (zoom out mid-way, `bump` in `animateViewport`); durations scale with the number of zoom doublings. `testMagnifyingKeepsTheLayout`, `testLocateMatchesRenderedRects` and `TreemapLayoutConsistencyTests` guard this. Two things keep render and `locate` in lockstep: squarify breaks ties with a relative epsilon (identical file sizes are common; without it the decision rode on the last floating-point bit and flipped with scale), and `DiskXRayViewModel.renderArea` derives the magnified area from the rounded bitmap size so the scale is exactly the 1× scale × magnification on both axes (rounding only the bitmap skewed the aspect ~0.1% — the selection box landed up to ~300 px off on a full-disk scan). Like a map game, nothing goes blank while moving: the view stacks layers — `baseLayer` (whole map), up to two `backdrop` layers and the current `rendering` — each cropped to its visible part (`visiblePiece`, never a huge transform) and stretched by `imageFrame` until the next render. Viewport-only changes don't bump `renderGeneration` (layers stay valid) and are throttled, not debounced (`viewportChanged`: the in-flight render finishes and the next one starts, so the map sharpens mid-gesture). Magnified renders carry a ¼-screen margin on each side; `screen:` keeps labels on the visible part. Drag has inertia (`EventView.startGlide`); buttons, ⌘0, smart magnify and Magnify to Selection animate (`animateViewport`: log-scale side, centre follows zoom progress), gestures apply instantly and cancel any animation/flight. macOS only delivers trackpad gestures to the key window (scroll goes to the window under the pointer), so `EventView` routes `.magnify`/`.smartMagnify` through local + global `NSEvent` monitors when the pointer is over the map but the window isn't key — don't remove them, or pinch needs a click first. The mouse wheel (non-precise deltas) zooms; trackpad scroll keeps select parent/child at 1×. Clicks map through the same transform. Changing the folder zoom resets it.
- `Views/DiskXRayFileTree.swift` — the folder tree is a native `NSOutlineView`; the model only bumps `treeVersion` (reload, keeping expansion) and `revealToken` (expand path, select, scroll). Folder icons load asynchronously. Don't move it back to a SwiftUI list — that made navigation slow.
- `ViewModels/DiskXRayViewModel.swift` — free space and "System & Unaccounted" (= APFS container used − scanned) pseudo items, On Disk/Logical sizes, type filter (dims the rest of the map), zoom/breadcrumbs, largest files, Move to Trash (never the scan root, home or its top-level folders).
- The window is hosted by an `NSHostingController` with `sceneBridgingOptions = [.toolbars, .title]`, so `.toolbar` in `DiskXRayWindowView` becomes the window's native `NSToolbar`.
- `Models/DiskXRay.swift` — `DiskOverview` (APFS container from `diskutil apfs list -plist`) and `Firmlinks`.

### Themes and the native popover

`AppTheme` (`Models/Theme.swift`): **Liquid Glass** (default, first in the picker), Classic, Cyberpunk, Matrix. `ThemePalette.surfaceStyle` (`solid`/`neon`/`glass`) says how surfaces are built. With Liquid Glass, `MenuBarView` renders `NativeMenuBarView` — **system components only** (List/Section, Gauge, LabeledContent, Picker, Toggle, ProgressView, NSSearchField) plus native glass (`glassEffect`, `GlassEffectContainer`, `.glass`/`.glassProminent`) on controls and floating panels; never simulate glass with blur. Content stays on semantic fills (no glass-on-glass). Shared modifiers live in `Views/Components/ThemeStyles.swift`. Respect Reduce Transparency/Motion and Increase Contrast.

### Distribution without a Developer ID

`docs/install.sh` (published at `https://alexkads.github.io/MAC-LIMPO/install.sh`) checks the Mac, downloads the latest release source, builds with `Scripts/bundle-app.sh` and installs into `/Applications` — locally built apps carry no quarantine flag, so Gatekeeper doesn't block them. Keep it POSIX `sh` and `shellcheck`-clean. Its minimums (macOS 26.6 on Apple silicon — Xcode 27's own floor — and Swift 6.4) must match `Package.swift`, `LSMinimumSystemVersion` and `Installer/Distribution.xml`. An existing copy from the `.pkg` is root-owned, so it is removed with `sudo` (`remove_app` checks the bundle's owner, not whether `/Applications` is writable).

### Update notifications

`Services/UpdateChecker.swift` works like VintageLightbox's (no GitHub Actions, no Developer ID): it fetches `docs/updates.json` from `raw.githubusercontent.com/…/main/docs/updates.json`, then GitHub Pages (`/updates.json`) as fallback — 15 s timeout, numeric version compare (`1.3.10 > 1.3.9`; unparseable never newer). Checks 5 s after launch and hourly, silent on errors; only **Check for Updates…** (Settings, both popovers) reports "up to date"/"couldn't check". A new version shows a dot on the status icon (`AppDelegate.statusImage(badged:)`) and the `UpdateBanner` at the top of the popover. **With a Swift toolchain it installs by itself, like VintageLightbox** (`canBuildFromSource` only checks files — `DEVELOPER_DIR`, `/var/db/xcode_select_link`, Xcode, CLT; never `Process`/`waitUntilExit` there: waiting spins the main run loop, SwiftUI re-renders the banner mid-initialisation and the app traps on a recursive `dispatch_once`; never `xcrun`, which pops an install dialog): it downloads `install.sh` to `~/Library/Caches/MAC-LIMPO-build/update/`, checks it's complete and runs it detached under `nice -n 10` with `--in-background --dest <current folder>` — the script builds and swaps the bundle on disk **without quitting the app**. The banner follows the log's `▸` steps; at the end the version is re-read from the bundle's Info.plist on disk (not `Bundle`, which caches) and the banner says "Version X installed — takes effect next launch, or **Reopen Now**" (`reopenNow`: quit first, then a detached `open … --args --updated`, or the new instance's single-instance check would close it), plus one notification. A lock (`install.lock`, holds the manifest, expires in 3 h) prevents two installers and lets a relaunched app resume watching; a failed version isn't retried automatically for 24 h (`updateFailure`; Try Again and Check for Updates ignore it). `--from-app` (install.sh quits and reopens) stays for 1.3.24 clients. Without a toolchain (`.pkg` installs) it opens the release page. The manifest URL list is append-only — installed apps only know the URLs they were built with. Dev hook: `MACLIMPO_UPDATE_URL=<url|file://>`.

### Releasing

Users only see published work: the site's `install.sh` (updated by `make docs-deploy`) builds the **latest GitHub release**, not `main`, and the `.pkg` ships with the release. A fix to something the user hit through the installer isn't done until it's published. Follow the `release` skill (`.claude/skills/release/SKILL.md`): VERSION + CHANGELOG (`[Unreleased]`) → tag → `make installer` → push → `gh release create` with the `.pkg` → `make docs-deploy` → check the published script. Release before deploying the site whenever the script's requirements change.

### Website

MkDocs Material in `docs/` (+ `overrides/` for Open Graph/JSON-LD), English and Portuguese via suffix files (`page.pt.md`) — a first visit from a Portuguese browser is sent to `/pt/` and a pick in the language selector is remembered (script in `overrides/main.html`), published to the `gh-pages` branch with `make docs-deploy` (`mkdocs gh-deploy`; `.github/workflows/pages.yml` is a manual alternative). `docs/cleaning.md` lists the categories — regenerate it when categories change. `mkdocs build --strict` must pass.

### Development hooks (env vars)

`MACLIMPO_THEME`, `MACLIMPO_APPEARANCE=light|dark`, `MACLIMPO_OPEN_XRAY=1`, `MACLIMPO_XRAY_ROOT=<folder>`, `MACLIMPO_XRAY_LOGICAL=1`, `MACLIMPO_XRAY_3D=1|0`, `MACLIMPO_XRAY_HOVER=<x>,<y>` (pointer at a map fraction, for the 3D tooltip), `MACLIMPO_XRAY_DEMO=1`, `MACLIMPO_XRAY_MAGNIFY=<factor>`, `MACLIMPO_XRAY_FOCUS=<file name>` (select + Magnify to Selection), `MACLIMPO_XRAY_SELECT=<name>` (select as the tree does), `MACLIMPO_SNAPSHOT=<png>` / `MACLIMPO_SNAPSHOT_POPOVER=<png>` with `MACLIMPO_SNAPSHOT_DELAY`, `MACLIMPO_WELCOME=1|0` (force/suppress the welcome balloon), `MACLIMPO_UPDATE_URL=<url|file://>` (update manifest), `MACLIMPO_UPDATE_INSTALLER=<url|file://>` (install script used to update). Snapshots use `cacheDisplay`, which does **not** render Liquid Glass materials — verify glass on screen.

## Conventions

- 4-space indentation; log/comments often Portuguese.
- **The UI is English + Brazilian Portuguese** (follows the macOS language, English fallback). Source text is English; translations live in `Localization/Localizable.xcstrings` (String Catalog) and `Localization/InfoPlist.xcstrings`. SwiftUI literals (`Text("…")`, `Button`, `Label`, `.help`) are localized automatically; any user-visible `String` must be written as `String(localized: "… \(value) …")` where the literal is — never a dynamic key. Enums show `displayName`/`title` (localized), never `rawValue` (identity: ids, persisted keys, logs). After adding or changing UI text: `make strings` (`Scripts/sync-strings.sh` — the compiler's `-emit-localized-strings` + `xcstringstool sync`, built in `.build/strings`), then fill in `pt-BR`. `LocalizationTests` fails on a missing translation or mismatched placeholders. `bundle-app.sh` compiles the catalogs into `en.lproj`/`pt-BR.lproj` and declares `CFBundleLocalizations`; `swift run` (no bundle) is always English. Check a language with `…/MAC-LIMPO -AppleLanguages '(pt-BR)'`. Number/size formatting follows the region, not the language. In pt-BR use macOS terms ("Lixo", "Ajustes do Sistema", "Acesso Total ao Disco"); "Disk X-Ray" stays as the product name.
- `Color(hex:)` extension lives in `Models/CleaningCategory.swift`.
- Design notes for the project live as `Services/*.md` files (excluded from the build) and `docs/`.
