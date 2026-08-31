# Vector Toolset Build Plan

What has to be built, in what order, and what each part needs. See ARCHITECTURE.md for how the pieces fit.

## Components

| # | Component | What it is | Needs | Risk |
|---|---|---|---|---|
| 0 | Repo scaffold | The layout, gitignore, archived legacy files, README. Done. | - | low |
| 1 | Manifest schema v2 | Extend tools-manifest.json: source URL, sha256, target path, plane (winpe, live, both), baked flag | - | low |
| 2 | C# WPF launcher | Dark UI, manifest loader, environment detection, process launching, kiosk shell mode | .NET SDK | medium to high |
| 3 | Built-in scripts | Port the four existing PowerShell tools; add the DISM imager and a DISM/SFC repair wrapper; a shared environment module | - | low to medium |
| 4 | Manage-tools GUI | In-launcher add, edit, and remove screen that writes the manifest | part of #2 | medium |
| 5 | Get-Tools resolver | Populate tools from the local stash, or download from the manifest URL, or report missing with instructions | - | medium |
| 6 | Build-WinPE | ADK: copype, mount, add optional components, inject drivers, bake the core, set the launcher as the shell | Windows ADK | medium |
| 7 | Bootloader (GRUB2) | Theme and menu, WinPE entry plus ISO loopback entries, BIOS and UEFI | research | highest |
| 8 | Deploy-USB | Partition the stick, install GRUB, copy the images, populate the data partition | admin | high (writes a physical disk, needs hard safety guards) |
| 9 | Branding | GRUB splash, launcher theme, logo, icons | design | low |
| 10 | Make-Toolset and README | An orchestrator that chains steps 5 through 8, plus the tech facing instructions | - | low |

## Phases

- A. Repo scaffold and manifest schema.
- B. C# launcher plus the ported built-in scripts, tested on live Windows first.
- C. Get-Tools resolver.
- D. WinPE build. Needs the Windows ADK.
- E. GRUB2 bootloader.
- F. Deploy-USB.
- G. Manage-tools GUI, branding, DISM imager, orchestrator, README.

## Sequencing note

Build the launcher first and test it entirely on live Windows before touching the ADK or WinPE. It is the most complex and most failure prone piece, it needs no ADK, and it is directly usable in the plugged-in mode. Get it solid there, then drop it into WinPE as the shell.

## The two unknowns to spike early

- The GRUB2 multiboot layer (item 7). Chainloading WinPE and the Linux ISOs across BIOS and UEFI is the least certain part.
- Deploy-USB (item 8). Partitioning a physical disk safely, with strong guards so the wrong drive can never be targeted.

## Prerequisite gap

The Windows ADK and the WinPE add-on are not installed on the build machine yet. They are needed from phase D on. Phases A and B do not need them, so the launcher work is not blocked.
