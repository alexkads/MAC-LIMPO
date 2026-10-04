---
description: Disk X-Ray — see where every gigabyte of your Mac goes with a fast full-disk scan, a file-type treemap, a folder tree and the largest files.
---

# Disk X-Ray

Open it from the :material-radiology-box: button at the top of the menu bar popover.

![Disk X-Ray](assets/images/disk-xray-light.png#only-light){ .screenshot }
![Disk X-Ray](assets/images/disk-xray-dark.png#only-dark){ .screenshot }

## What you see

- **Summary** — disk used and free, a bar split by file type, and a card per category (video, images, source code, builds & libraries, disk images & VMs, data & databases, archives & installers, documents, audio…). Click a card to highlight that type in the map.
- **Folders** — a native, sortable tree (size, share of the parent folder, files, modified). It stays fast with millions of items.
- **Largest Files** — the biggest files anywhere on the disk.
- **Types** — every category and its extensions with sizes and file counts; click one to highlight it.
- **Map** — a treemap where every file is a tile sized by how much space it takes and colored by type. Large folders get a header with their name and size.

## Using the map

| Action | Result |
|---|---|
| Click | Select the file or folder (the tree follows) |
| Double-click | Zoom into that folder |
| Breadcrumb / ⟨ | Go back up |
| Scroll | Select parent / child |
| ⌘ + scroll | Zoom in / out |
| Right-click | Quick Look, Open, Show in Finder, Copy Path, Move to Trash |
| Space | Quick Look the selection |

## Options in the toolbar

- **On Disk / Logical** — *On Disk* is the space files actually occupy; *Logical* is the size they report. They differ for sparse files (a Docker disk image may report 500 GB and use 30 GB) and compressed files.
- **Free** and **System** — add the free space and the space the scan cannot read (macOS itself, Preboot, swap, protected folders) to the map, so the whole disk adds up.
- **Scan target** — the whole disk or a folder of your choice.

## How it is fast

The scanner reads each folder in bulk with `getattrlistbulk(2)` — names, sizes and dates for hundreds of entries per system call — using several threads tuned to the Mac (one per core on SSDs, fewer on spinning disks and network volumes). On a 10-core Mac it reads ~3 million items in about 16 seconds. Hard links count once and virtual mounts (like a connected iPhone) are skipped.

!!! note "Full Disk Access"
    Without Full Disk Access some protected folders cannot be read; their space shows up under **System**.
    Grant it in System Settings › Privacy & Security › Full Disk Access.
