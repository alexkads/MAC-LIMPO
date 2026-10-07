---
name: release
description: Publish a MAC-LIMPO change to users — bump VERSION, CHANGELOG, tag, build the .pkg, GitHub release, push and deploy the site (install.sh). Use whenever a fix or feature must reach users ("publica", "lança a versão", "faz a release", "sobe o site"), and ALWAYS after fixing something the user hit through the published installer (`curl … install.sh | sh`) — a commit alone fixes nothing for them.
---

# Releasing MAC-LIMPO

Users get MAC-LIMPO through two published channels, and **neither sees a local commit**:

- `https://alexkads.github.io/MAC-LIMPO/install.sh` — served from the `gh-pages` branch, updated only by `make docs-deploy`. It downloads the source of the **latest GitHub release** (not `main`) and builds it.
- The `.pkg` attached to the GitHub release.

So a fix in `docs/install.sh` reaches users after `make docs-deploy`; a fix in the app (or in anything `install.sh` builds — `Package.swift`, `Scripts/bundle-app.sh`, `Info.plist`) reaches them only after a **new release**. When the user reports a failure of the published installer, finishing the fix means publishing it — don't stop at the commit and ask.

## Order matters

1. Release first, site last. If the site's `install.sh` changes its requirements (macOS/Swift minimums) before a release carries the matching source, users pass the new checks and then the build of the old source fails.
2. A script-only fix (nothing `install.sh` builds changed) can skip the release: push + `make docs-deploy`.

## Steps

1. **Verify** — `swift build`, `swift test`, `shellcheck docs/install.sh` (if touched), `mkdocs build --strict -d <scratch dir>` (if docs touched).
2. **Version** — `VERSION` holds `x.y.z`; bump the patch (`printf '1.3.21\n' > VERSION`). `Makefile`, `Scripts/bundle-app.sh` and `Installer/build-installer.sh` read it.
3. **CHANGELOG.md** — releases since 1.1.0 accumulate under `## [Unreleased]` (Portuguese, `- **Title**: explanation.`), in the sections `### ✨ Adicionado`, `### 🐛 Corrigido`, `### 🔄 Alterado`, `### ⚡️ Desempenho`. Headings like `### 🐛 Corrigido` **repeat in older versions** — when editing by script, insert after the *first* occurrence, never assert a single match. Make the edit and the commit one `&&` chain, so a failed edit doesn't commit a half-done release.
4. **Commit + tag** — `chore: versão x.y.z (<resumo>)`, then `git tag vx.y.z`. Commit messages are Portuguese, no attribution lines.
5. **Package** — `make installer` → `build/MAC-LIMPO-x.y.z.pkg`. Check it: `pkgutil --expand <pkg> <scratch>/pkgx && grep 'os-version min' <scratch>/pkgx/Distribution`.
6. **Push** — `git push origin main vx.y.z`.
7. **GitHub release** — `gh release create vx.y.z build/MAC-LIMPO-x.y.z.pkg --title "MAC-LIMPO x.y.z — <headline>" --notes-file <notes>`. Notes in English with a short Portuguese section, same shape as earlier releases (`gh release view v1.3.20`):
   - `## Install` — the `curl … | sh` line, then the `.pkg` (not notarized: right-click › **Open**) and the macOS requirement.
   - `## New` / `## Changed` / `## Fixed` — bold lead-in + one or two sentences, user-facing.
   - `## Português` — one paragraph.
8. **Site** — `make docs-deploy` (pushes `gh-pages`).
9. **Confirm what users get** — Pages takes ~1 min: `curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh | grep <something from the fix>`, and `gh release list --limit 1` shows the new tag as Latest.

## Testing install.sh without touching /Applications

- Real run into a scratch folder: `sh docs/install.sh --dest <scratch>/apps --no-open` (builds the latest *release* source, not the working tree — to check working-tree packaging run `./Scripts/bundle-app.sh` and inspect `build/app/MAC-LIMPO.app`: `vtool -show-build …/Contents/MacOS/MAC-LIMPO`, `lipo -archs`, `codesign -v`).
- Decisions only: `sh docs/install.sh --dry-run --no-open`.
- Other macOS versions: a fake `sw_vers` first on `PATH` (`printf '#!/bin/sh\necho 26.5\n'`).
- Replacing the root-owned copy in `/Applications` (left by the `.pkg`) needs `sudo` with a terminal — the user runs that one. Tell them to run `sh install.sh`, not `sudo curl … | sh`: there `sudo` applies to `curl` only.
