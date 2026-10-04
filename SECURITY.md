# Security Policy

MAC-LIMPO deletes files, runs a few system tools (`docker`, `brew`, `xcrun simctl`, `tmutil`) and, for some
categories, asks for an administrator password. Bugs here can cost people data, so security reports are taken
seriously.

## Supported versions

Only the [latest release](https://github.com/alexkads/MAC-LIMPO/releases/latest) receives fixes.

## Reporting a vulnerability

**Please do not open a public issue.** Report it privately through GitHub:

1. Go to <https://github.com/alexkads/MAC-LIMPO/security/advisories/new>.
2. Describe the problem, the macOS version, the MAC-LIMPO version (shown at the bottom of the menu bar
   popover) and the steps to reproduce.

You should get an answer within a week. Once a fix is released, the advisory is published with credit to you
(unless you prefer otherwise).

## What counts

- A cleaning category that can remove files outside caches, build output or the user's explicit choice.
- Path handling that can be tricked into deleting something else (symlinks, crafted names, races).
- Privilege escalation through the administrator prompts or the installer scripts (`Installer/`,
  `docs/install.sh`).
- Anything that leaks file names or contents off the machine.

Bugs in cleaning estimates or UI glitches are regular issues — please use the issue tracker for those.
