---
name: release
description: Publish a MAC-LIMPO change to users — bump VERSION, CHANGELOG, docs/updates.json, tag, build the .pkg, GitHub release, push and deploy the site (install.sh). Use whenever a fix or feature must reach users ("publica", "lança a versão", "faz a release", "sobe o site"), and ALWAYS after fixing something the user hit through the published installer (`curl … install.sh | sh`) or the in-app update — a commit alone fixes nothing for them.
---

# Releasing MAC-LIMPO

Users get MAC-LIMPO through three published channels, and **none of them sees a local commit**:

- **In-app update** — installed apps poll `docs/updates.json` (raw.githubusercontent on `main` first, the Pages copy as fallback) at launch and hourly. With a Swift toolchain they **install by themselves**: they download the Pages `install.sh` and run it with `--in-background`, which builds the **latest GitHub release** and swaps the bundle on disk. Without a toolchain (`.pkg` installs) the banner opens the release page.
- `https://alexkads.github.io/MAC-LIMPO/install.sh` — served from the `gh-pages` branch, updated only by `make docs-deploy`. It downloads the source of the latest GitHub release (not `main`) and builds it.
- The `.pkg` attached to the GitHub release.

So a fix in `docs/install.sh` reaches users after `make docs-deploy`; a fix in the app (or in anything `install.sh` builds — `Package.swift`, `Scripts/bundle-app.sh`, `Info.plist`) reaches them only after a **new release** announced in `docs/updates.json`. When the user reports a failure of something published, finishing the fix means publishing it — don't stop at the commit and ask.

## Order matters

1. **The release must exist before `docs/updates.json` reaches `main`.** Pushing `main` publishes the manifest at once, and every app with a toolchain starts building right away. If the release isn't there yet, `install.sh` builds the previous release, the app finds the old version on disk, marks the new one as failed and **doesn't retry it for 24 h**. So push the tag, create the release, and only then push `main` (steps 6–8).
2. **Release first, site last.** If the site's `install.sh` changes its requirements (macOS/Swift minimums) before a release carries the matching source, users pass the new checks and then the build of the old source fails. And since the in-app update runs the *published* `install.sh`, a broken script breaks every app's update — test it before deploying (see below).
3. A script-only fix (nothing `install.sh` builds changed) can skip the release: push + `make docs-deploy`. Don't touch `docs/updates.json` then.
4. `UpdateChecker.manifestURLs` is append-only — installed apps only know the URLs they were built with. Never move or rename `docs/updates.json` or `install.sh`.

## Steps

1. **Verify** — `make strings` (no key may be left without `pt-BR`), `swift build`, `swift test` (includes `LocalizationTests` and `UpdateCheckerTests`), `shellcheck docs/install.sh` (if touched), `mkdocs build --strict -d <scratch dir>` (if docs touched). `git status` must be clean apart from the release edits.
2. **Version** — `VERSION` holds `x.y.z`; bump the patch (`printf '1.3.28\n' > VERSION`), minor for a large feature. `Makefile`, `Scripts/bundle-app.sh` and `Installer/build-installer.sh` read it.
3. **CHANGELOG.md** — releases since 1.1.0 accumulate under `## [Unreleased]` (no per-version sections; Portuguese, `- **Title**: explanation.`), in the sections `### ✨ Adicionado`, `### 🐛 Corrigido`, `### 🔄 Alterado`, `### ⚡️ Desempenho`. Headings like `### 🐛 Corrigido` **repeat in older versions** — when editing by script, insert after the *first* occurrence, never assert a single match. Make the edit and the commit one `&&` chain, so a failed edit doesn't commit a half-done release. (`docs/changelog.md` just includes `CHANGELOG.md` — don't edit it.)
4. **docs/updates.json** — what installed apps read to announce and install the version (dot on the icon, banner, notification). Set `version` (= VERSION), `date` (today, `YYYY-MM-DD`), `url` (`https://github.com/alexkads/MAC-LIMPO/releases/tag/vx.y.z`), `important` (true only for fixes users must get — the banner turns red), and `notes.en` / `notes.pt-BR` with `title` (one line), `changes` (2–4 short user-facing bullets) and `why`. `UpdateCheckerTests` fails if it doesn't match `VERSION` or lacks either language.
5. **Commit + tag** — `git add VERSION CHANGELOG.md docs/updates.json && git commit -m "chore: versão x.y.z (<resumo>)" && git tag vx.y.z`. Commit messages are Portuguese, no attribution lines.
6. **Package** — `make installer` → `build/MAC-LIMPO-x.y.z.pkg`. Check it: `pkgutil --expand build/MAC-LIMPO-x.y.z.pkg <scratch>/pkgx && grep 'os-version min' <scratch>/pkgx/Distribution` (the build script already asserts there's no `<relocate>` block).
7. **Push the tag, then create the release** — `git push origin vx.y.z`, then `gh release create vx.y.z build/MAC-LIMPO-x.y.z.pkg --title "MAC-LIMPO x.y.z — <headline>" --notes-file <notes>`. Notes in English with a short Portuguese section, same shape as earlier releases (`gh release view v1.3.27`):
   - `## Install` — the `curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh | sh` block, then the `.pkg` (not notarized: right-click › **Open**) and "Requires macOS 26.6+ on Apple silicon."
   - `## New` / `## Changed` / `## Fixed` — bold lead-in + one or two sentences, user-facing.
   - `## Português` — one paragraph.
8. **Push main** — `git push origin main` (this is what announces the version to installed apps). `gh release list --limit 1` must show the new tag as Latest first.
9. **Site** — `make docs-deploy` (pushes `gh-pages`; also refreshes the Pages copy of `updates.json`).
10. **Confirm what users get** — Pages takes ~1 min:
    - `curl -fsSL "https://raw.githubusercontent.com/alexkads/MAC-LIMPO/main/docs/updates.json?t=$(date +%s)" | grep '"version"'` and the same for `https://alexkads.github.io/MAC-LIMPO/updates.json`.
    - `curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh | grep <something from the fix>` when the script changed.
    - If the user has the app installed, its banner should show "Version x.y.z installed — … Reopen Now" within the hour (or right away with **Check for Updates…**).

## Testing install.sh and the update without touching /Applications

- Real run into a scratch folder: `sh docs/install.sh --dest <scratch>/apps --no-open` (builds the latest *release* source, not the working tree — `--version vx.y.z` picks another tag). To check working-tree packaging run `./Scripts/bundle-app.sh` and inspect `build/app/MAC-LIMPO.app`: `vtool -show-build …/Contents/MacOS/MAC-LIMPO`, `lipo -archs`, `codesign -v`.
- Decisions only: `sh docs/install.sh --dry-run --no-open`.
- The in-app path: `sh docs/install.sh --in-background --dest <scratch>/apps` (what the app runs — no quitting, no opening; the `▸` lines are what the banner shows).
- The whole update flow: the app reinstalls into the folder its bundle is in (`--dest` = the bundle's parent), so test from a bundled copy in a scratch folder, never `/Applications` or `swift run` (no bundle — it would install into `.build/`). `./Scripts/bundle-app.sh`, copy `build/app/MAC-LIMPO.app` to `<scratch>/apps/`, quit the installed MAC-LIMPO (single instance), then `MACLIMPO_UPDATE_URL=file://<scratch>/updates.json MACLIMPO_UPDATE_INSTALLER=file://$PWD/docs/install.sh <scratch>/apps/MAC-LIMPO.app/Contents/MacOS/MAC-LIMPO` with a manifest whose `version` is higher than `VERSION`.
- Other macOS versions: a fake `sw_vers` first on `PATH` (`printf '#!/bin/sh\necho 26.5\n'`).
- Replacing the root-owned copy in `/Applications` (left by the `.pkg`) needs `sudo` with a terminal — the user runs that one. Tell them to run `sh install.sh`, not `sudo curl … | sh`: there `sudo` applies to `curl` only.
