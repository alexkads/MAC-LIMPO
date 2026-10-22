---
description: What MAC-LIMPO deletes, what it never touches, and how cleanups can be undone.
---

# Safety

MAC-LIMPO removes **caches, build output, logs and temporary files** that tools recreate by themselves. Your own files are never deleted for good: the categories that touch them — *Old Downloads* and *App Leftovers* — only move to the Trash what has sat untouched for a long time.

## How a cleanup works

1. **Scan first.** Every category measures what it would remove; nothing is deleted during a scan.
2. **Confirm.** Cleaning a category or *Clean All* asks for confirmation (you can skip it for the session).
3. **Trash, when possible.** Path-based cleaners move items to the **Trash**, so you can restore them until the Trash is emptied. *Clean All* never empties it — only the *Trash Bin* category does, and its confirmation says that's permanent.
4. **Report.** You see how much was freed and any item that could not be removed.

!!! warning "Some removals are permanent"
    Categories that delegate to the tool that owns the data — `docker … prune`, `brew cleanup`, `xcrun simctl`
    — and some system areas remove items directly, because there is no Trash on that path. Their descriptions
    say so, and the larger or riskier ones (local AI models, all unused Docker images, old simulator runtimes,
    Time Machine local snapshots) only run in **Aggressive cleaning** mode.

## What it never does

- Delete Docker **data volumes** (databases, uploads). It removes unused images, build cache, stopped
  containers and only those unused volumes whose names mark them as rebuildable caches (e.g. `cargo-target`,
  `node-modules`, `next-cache`).
- Remove the toolchains you rely on: the rustup default, `rustup override` and channel toolchains
  (stable/beta/nightly), the nvm `default` alias and the newest Node of each major version stay.
- Remove a Cargo `target/` while a build is running.
- Delete Xcode **Archives** (the dSYMs of your shipped builds) or the SwiftPM configuration.
- Take a `build/` or `dist/` folder without proof that a build tool made it: a Gradle or Flutter project
  for `build/`, a Python package for `dist/`. JavaScript `build/` and `dist/` folders stay.
- Take anything from `/tmp` that a running program may still use — sockets, pipes, anything touched in the
  last 7 days — or that belongs to another user.
- Call an app uninstalled just because it isn't in /Applications: it is looked up by bundle id anywhere on the
  Mac, and its data must have been idle for 90 days. VS Code and Cursor workspace state only goes when its
  project no longer exists.
- Send anything off your Mac. There is no telemetry; Apple Intelligence recommendations run on-device.

## Permissions

- **Full Disk Access** — needed to measure and clean protected caches (Mail, Messages, Safari, app containers). Without it those areas are skipped, never forced.
- **Administrator password** — asked only for root-owned caches (e.g. superseded .NET SDKs) and Time Machine local snapshots in Aggressive mode, and only in the categories that need it.

## Disk X-Ray

The Disk X-Ray only reads. *Move to Trash* works on one item at a time, after confirmation, and refuses your home folder and its top-level folders (Documents, Desktop, Library…).

Found something that removed too much? Please [report it privately](https://github.com/alexkads/MAC-LIMPO/security/advisories/new).
