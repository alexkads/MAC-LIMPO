---
description: Frequently asked questions about MAC-LIMPO.
---

# FAQ

??? question "Is it free? Is there a catch?"
    It is free software under the GPL-3.0-or-later. No account, no subscription, no ads, no telemetry.

??? question "Why does the install script compile the app?"
    The project does not pay for an Apple Developer ID. macOS blocks unsigned apps downloaded from the internet;
    an app compiled on your own Mac is not quarantined and opens normally. See [Install](install.md).

??? question "Which macOS versions are supported?"
    macOS 26.6 or later on Apple silicon. Building needs the Command Line Tools or Xcode with Swift 6.4.

??? question "Which languages does it speak?"
    English and Brazilian Portuguese. The app follows the language of your Mac (System Settings › General ›
    Language & Region) and uses English for any other language. This site opens in Portuguese for Portuguese
    browsers; the language selector at the top switches it, and your pick is remembered.

??? question "How do I update?"
    You don't have to. MAC-LIMPO checks for new versions by itself and, if your Mac has the Command Line Tools or
    Xcode, builds the new one in the background while you keep working — nothing closes. When it's ready, a dot on
    the menu bar icon and a notification tell you; it takes effect the next time the app opens, or click
    **Reopen Now**. Installed from the `.pkg` without build tools? The banner links to the download instead.
    **Check for Updates…** in Settings checks right away.

??? question "Will it delete my files?"
    It targets caches, build output and temporary files that tools recreate. Path-based cleaners move items to
    the Trash. See [Safety](safety.md) for the details and the exceptions.

??? question "Why doesn't the freed space show up immediately?"
    Items moved to the Trash still take space until you empty it. Docker's disk image (`Docker.raw`) only
    shrinks after Docker Desktop compacts it. APFS may also take a moment to update free space.

??? question "Why is part of my disk 'System & Unaccounted' in the Disk X-Ray?"
    That is space in use that the scan cannot read file by file: macOS itself (sealed system volume), Preboot,
    swap, Recovery and folders protected by privacy permissions. Granting Full Disk Access makes it smaller.

??? question "Can I use it from Shortcuts or Siri?"
    Yes — MAC-LIMPO exposes two App Intents, *Scan Mac Storage* and *Clean Mac Storage*.

??? question "How do I uninstall it?"
    `curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh | sh -s -- --uninstall`, or
    `sudo mac-limpo-uninstall` if you used the `.pkg`.

??? question "How can I help?"
    Report bugs, suggest cleaning categories or send a pull request — see the
    [development guide](development.md).
