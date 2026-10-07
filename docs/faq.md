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
