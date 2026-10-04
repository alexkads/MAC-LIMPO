# Contributing to MAC-LIMPO

Thanks for helping! Bug reports, new cleaning categories, fixes and documentation are all welcome.
By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

Contribuições em português também são bem-vindas — issues e PRs podem ser escritos em português.

## Ways to contribute

- **Report a bug** — use the [bug report form](https://github.com/alexkads/MAC-LIMPO/issues/new/choose). Include
  the MAC-LIMPO version (bottom of the menu bar popover) and your macOS version.
- **Suggest a cleaning category** — tell us the app/tool, the folders it fills and why they are safe to remove.
- **Send a pull request** — small and focused PRs are the easiest to review.
- **Security problems** — never in public issues; see [SECURITY.md](SECURITY.md).

## Development setup

Requirements: macOS 27+, Xcode 27 (or the Command Line Tools with Swift 6.4).

```bash
git clone https://github.com/alexkads/MAC-LIMPO.git
cd MAC-LIMPO
swift build          # debug build
swift run            # launch — the icon appears in the menu bar
swift test           # unit tests (Tests/MACLIMPOTests)
make help            # every other target (app bundle, installer, dmg)
```

**Xcode:** open `Package.swift` (File › Open, or `open Package.swift`). Xcode creates the `MAC-LIMPO` scheme;
press ⌘R to run and ⌘U to test.

Formatting and lint: `swiftformat . && swiftlint` (configs in `.swiftformat` and `.swiftlint.yml`).

## Project layout

| Path | What lives there |
|---|---|
| `MACLIMPOApp.swift` | App entry, status item, popover, Disk X-Ray window |
| `Views/` | SwiftUI views (`MenuBarView`, `NativeMenuBarView`, `DiskXRay*`, `Components/`) |
| `ViewModels/` | View models (`DiskXRayViewModel`) |
| `Services/` | One `CleaningService` per category, the disk scanner, logging |
| `Models/` | Categories, themes, results, scan index, file categories |
| `Utilities/` | File system, shell, treemap renderer, formatting |
| `Tests/MACLIMPOTests/` | XCTest suite |
| `docs/` | Website (MkDocs) and `install.sh` |
| `Installer/`, `Scripts/` | `.pkg` installer and app bundling |

Detailed architecture notes for contributors and AI coding agents are in [CLAUDE.md](CLAUDE.md) and on the
[development page](https://alexkads.github.io/MAC-LIMPO/development/).

## Adding a cleaning category

1. Create `Services/<Name>CleaningService.swift`. Prefer subclassing `PathBasedCleaningService` — a list of
   `CleanTarget`s is usually all you need. Implement `CleaningService` directly only for custom logic.
2. Add the `case` to `CleaningCategory` (`Models/CleaningCategory.swift`) and fill in `group`, `icon`
   (SF Symbol), `color` and `description`.
3. Register the service in `Services/CleaningServiceRegistry.swift`.
4. Add the file to the `sources:` list in `Package.swift` — **sources are listed explicitly**, a new file that
   is not listed is silently left out of the build.

### Safety rules for cleaners

- Target caches, build output and downloads that tools recreate — **never user documents**.
- Prefer the Trash (`FileSystemHelper.trashItem`) so a cleanup can be undone.
- `scan` must report exactly what `clean` will try to remove; items it skips should say why.
- Never interpolate paths into shell commands; pass them as arguments (`ShellExecutor.run`).
- Add tests for any rule that decides what gets deleted.

## Pull requests

1. Fork, create a branch from `main` (`feat/…`, `fix/…`, `docs/…`).
2. Make sure `swift build` and `swift test` pass and the code is formatted.
3. Update `CHANGELOG.md` under **Unreleased** for user-visible changes.
4. Open the PR using the template; screenshots help for UI changes.

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/) — `feat:`, `fix:`, `perf:`,
`docs:`, `refactor:`, `test:`, `chore:`.

## Documentation website

The site at <https://alexkads.github.io/MAC-LIMPO/> is built with MkDocs Material from `docs/` and deployed by
GitHub Actions on every push to `main`. To preview it locally:

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements-docs.txt
mkdocs serve
```

## License

By contributing you agree that your contributions are licensed under the
[GNU General Public License v3.0 or later](LICENSE).
