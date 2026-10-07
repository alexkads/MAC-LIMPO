---
description: Install MAC-LIMPO on macOS — one command that builds it on your Mac, the .pkg installer, or from source with Xcode.
---

# Install

## One command (recommended)

```bash
curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh | sh
```

What it does, in order:

1. Checks the Mac: macOS 26.6+, the Command Line Tools (or Xcode) with Swift 6.4, ~2 GB free.
2. Downloads the source of the [latest release](https://github.com/alexkads/MAC-LIMPO/releases/latest) (or `main` if there is none yet).
3. Builds the app with `Scripts/bundle-app.sh` — 2–5 minutes the first time; updates reuse the build cache in `~/Library/Caches/MAC-LIMPO-build`.
4. Installs `MAC-LIMPO.app` into `/Applications` (or `~/Applications` if `/Applications` is not writable) and opens it. A welcome balloon points at the trash icon in the menu bar — MAC-LIMPO has no Dock icon or main window, it lives there.

!!! warning "Don't put `sudo` in the command"
    Run it exactly as above, as your own user. If `/Applications` already has a copy installed by the `.pkg`
    (that copy belongs to root), the script calls `sudo` by itself just to remove it, and asks for **your Mac
    password** once — typing it is expected.

    `sudo curl … | sh` doesn't help: `sudo` only applies to `curl`, the download. And `curl … | sudo sh` would
    build and install everything as root, leaving a root-owned app that the next update can't replace.

!!! info "Why build instead of download?"
    MAC-LIMPO is not signed with a paid Apple Developer ID. macOS checks apps that arrive from the internet
    — they carry a *quarantine* flag — and blocks unsigned ones with "cannot verify that it is free of malware".
    An app that comes out of the compiler on your own Mac never had that flag, so it opens normally on the
    first click.

### Options

With `curl | sh`, pass options after `sh -s --`:

| Option | Effect |
|---|---|
| `--version <ref>` | Build a tag (`v1.3.16`) or a branch (`main`). Default: latest release. |
| `--dest <folder>` | Install somewhere else. Default: `/Applications`. |
| `--no-open` | Don't launch the app at the end. |
| `--dry-run` | Show what would happen without changing anything. |
| `--uninstall` | Remove the app and the build cache. |

```bash
curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh | sh -s -- --version main
curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh | sh -s -- --uninstall
```

Prefer to read it first? It is a plain shell script:

```bash
curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh -o install.sh
less install.sh && sh install.sh
```

### Missing tools

| Message | Fix |
|---|---|
| *the Command Line Tools are not installed* | `xcode-select --install`, wait for it to finish, run the command again. |
| *needs Swift 6.4+* | Update the Command Line Tools in **System Settings › General › Software Update**, or install the latest Xcode and run `sudo xcode-select -s /Applications/Xcode.app`. |
| *the build failed* | The last lines of the log are printed; the full log is in `~/Library/Caches/MAC-LIMPO-build/build.log`. Please [open an issue](https://github.com/alexkads/MAC-LIMPO/issues/new/choose) with it. |

## Installer package (.pkg)

Each [release](https://github.com/alexkads/MAC-LIMPO/releases/latest) includes `MAC-LIMPO-<version>.pkg`. It is not notarized: after downloading, **right-click it › Open**, then follow the installer. It installs the app into `/Applications` and the uninstaller `mac-limpo-uninstall` into `/usr/local/bin`.

## From source and Xcode

```bash
git clone https://github.com/alexkads/MAC-LIMPO.git
cd MAC-LIMPO
swift run          # build and launch
make app           # assemble build/app/MAC-LIMPO.app
make installer     # build/MAC-LIMPO-<version>.pkg
```

To work in **Xcode 27**: `open Package.swift` (or File › Open and choose the folder). Xcode creates the `MAC-LIMPO` scheme; ⌘R runs the app, ⌘U runs the tests.

## After installing

- The app lives in the **menu bar** (no Dock icon). Click it to open the popover.
- Some categories (Mail, Messages, Safari, app containers) need **Full Disk Access**: System Settings › Privacy & Security › Full Disk Access › enable MAC-LIMPO. The app asks when it is needed.
- **Launch at Login** is a toggle in the popover settings.

## Uninstall

```bash
curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh | sh -s -- --uninstall
```

Installed with the `.pkg`? Run `sudo mac-limpo-uninstall`. Your files are never touched.
