---
description: What MAC-LIMPO deletes, what it never touches, and how cleanups can be undone.
---

# Safety

MAC-LIMPO removes **caches, build output, logs and temporary files** that tools recreate by themselves. It never targets your documents, photos, projects' source code or app settings.

## How a cleanup works

1. **Scan first.** Every category measures what it would remove; nothing is deleted during a scan.
2. **Confirm.** Cleaning a category or *Clean All* asks for confirmation (you can skip it for the session).
3. **Trash, when possible.** Path-based cleaners move items to the **Trash**, so you can restore them until the Trash is emptied.
4. **Report.** You see how much was freed and any item that could not be removed.

!!! warning "Some removals are permanent"
    Categories that delegate to the tool that owns the data — `docker … prune`, `brew cleanup`, `xcrun simctl`
    — and some system areas remove items directly, because there is no Trash on that path. Their descriptions
    say so, and the larger or riskier ones (local AI models, all unused Docker images, old simulator runtimes)
    only run in **Aggressive cleaning** mode.

## What it never does

- Delete Docker **data volumes** (databases, uploads). It removes unused images, build cache, stopped
  containers and only those unused volumes whose names mark them as rebuildable caches (e.g. `cargo-target`,
  `node-modules`, `next-cache`).
- Remove the toolchains you rely on: the rustup default, `rustup override` and channel toolchains
  (stable/beta/nightly), the nvm `default` alias and the newest Node of each major version stay.
- Remove a Cargo `target/` while a build is running.
- Send anything off your Mac. There is no telemetry; Apple Intelligence recommendations run on-device.

## Permissions

- **Full Disk Access** — needed to measure and clean protected caches (Mail, Messages, Safari, app containers). Without it those areas are skipped, never forced.
- **Administrator password** — asked only for root-owned caches (e.g. superseded .NET SDKs) and only in the categories that need it.

## Disk X-Ray

The Disk X-Ray only reads. *Move to Trash* works on one item at a time, after confirmation, and refuses your home folder and its top-level folders (Documents, Desktop, Library…).

Found something that removed too much? Please [report it privately](https://github.com/alexkads/MAC-LIMPO/security/advisories/new).
