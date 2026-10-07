---
description: Free, open-source macOS disk cleaner and disk space analyzer for developers — a CleanMyMac and DaisyDisk alternative. Clean Xcode, Docker, simulators, node_modules and 40+ caches from the menu bar, and see where every gigabyte goes.
---

<div class="hero" markdown>

# MAC-LIMPO

<p class="tagline">Free up disk space on your Mac — a native menu bar cleaner for developers,<br>with a disk X-ray that shows where every gigabyte goes.</p>

[Install :material-download:](install.md){ .md-button .md-button--primary }
[View on GitHub :fontawesome-brands-github:](https://github.com/alexkads/MAC-LIMPO){ .md-button }

</div>

![Disk X-Ray](assets/images/disk-xray-light.png#only-light){ .screenshot }
![Disk X-Ray](assets/images/disk-xray-dark.png#only-dark){ .screenshot }

## Install in one command

<div class="install-command" markdown>

```bash
curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh | sh
```

</div>

The script builds MAC-LIMPO **on your Mac** and installs it into `/Applications`. Built locally, the app opens on the first click — no Gatekeeper warning, no paid certificate. Needs macOS 26.6+ and the Command Line Tools. [More options →](install.md)

## What it does

<div class="grid cards" markdown>

-   :material-broom: **46 cleaning categories**

    ---

    Xcode, simulators, Docker, `node_modules`, Rust `target/`, Cargo, Go, pnpm, Bun, Android SDK, .NET, IDE caches, browsers, logs, temp files and more.

    [:octicons-arrow-right-24: Categories](cleaning.md)

-   :material-radiology-box: **Disk X-Ray**

    ---

    Reads every file in seconds and maps the disk by file type: folder tree, type panel, largest files and a treemap you pinch to magnify down to a single file — in 2D or as a 3D map drawn with Metal.

    [:octicons-arrow-right-24: Disk X-Ray](disk-xray.md)

-   :material-shield-check: **Safe by default**

    ---

    Scan before cleaning, confirmation, Trash instead of delete where possible, caches only — never your documents.

    [:octicons-arrow-right-24: Safety](safety.md)

-   :material-apple: **Native**

    ---

    SwiftUI + AppKit, Liquid Glass by default, Apple Intelligence recommendations, App Intents for Shortcuts and Siri. No telemetry, no account.

    [:octicons-arrow-right-24: FAQ](faq.md)

</div>

## Menu bar

<figure markdown>
![Menu bar popover](assets/images/menu-bar-light.png#only-light){ width="320" .screenshot }
![Menu bar popover](assets/images/menu-bar-dark.png#only-dark){ width="320" .screenshot }
</figure>

Click the icon in the menu bar: the popover shows disk usage and every category with how much it would free. Click a category to clean it, or **Clean All**.

## Free software

MAC-LIMPO is released under the [GPL-3.0-or-later](https://github.com/alexkads/MAC-LIMPO/blob/main/LICENSE). Bug reports, ideas and pull requests are welcome — see the [development guide](development.md).
