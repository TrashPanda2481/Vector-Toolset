# Vector Toolset Architecture

This describes how the stick and the software are put together. For the tool list see TOOL_DECISIONS.md. For build order see BUILD_PLAN.md.

## The three planes

The stick has to serve three situations, and the design keeps them distinct.

1. Boot. On a bare machine the stick boots into WinPE. By default it boots WinPE directly through the Microsoft-signed Windows boot manager, so Secure Boot can stay on. An optional build (`-WithLinuxBoot`) instead lays down a branded GRUB2 menu that also offers the Linux repair tools; that menu waits for a choice and does not auto boot.
2. WinPE runtime. Booting WinPE brings up the Vector launcher as the shell. This is the flagship path for diagnosing and repairing a machine.
3. Live system. Plugged into a running Windows, Mac, or Linux box, the same tool folder is available from the file manager, and on Windows the same launcher runs directly.

## USB layout

GPT partitioning, two partitions:

- VECTORPE, FAT32 EFI System Partition, about 4 GB. The bootloader plus the WinPE media (boot.wim and the BCD). On the default stick the bootloader is WinPE's own Microsoft-signed Windows boot manager; on a `-WithLinuxBoot` stick it is GRUB, with the boot theme and fonts. This partition gets no drive letter, so Windows does not show it.
- VECTORDATA, exFAT, the rest. The full toolkit tree, readable by any modern OS. Holds the tools, the launcher, generated reports, captured disk images, customer backups, offline driver packs, and AV definition updates. On a `-WithLinuxBoot` stick it also holds `payload\` with the Linux boot ISOs (Clonezilla, ShredOS, Memtest86+, GParted, SystemRescue) that GRUB loopback-boots.

The data partition being exFAT is the key decision. It is the one partition that WinPE and a live Windows, Mac, or Linux system all mount as a normal drive, so a single copy of the tools serves both the booted and the plugged in planes. exFAT also has no 4 GB file size limit, which matters for full disk images.

## Two tier tool placement

WinPE loads its boot.wim entirely into a RAM disk, so anything baked into WinPE costs memory at boot. Vector keeps WinPE small by splitting tools into two tiers.

- Baked into WinPE: the launcher, the built-in PowerShell scripts, and a few tiny command line tools (for example smartctl and 7-Zip). This is the core that must work even if the data partition were missing.
- On the data partition: everything else. All the portable GUI tools, the live-only tools, the browser, and the driver tools. The launcher reaches them from the data partition at runtime, and a live system opens the same folder directly.

## Boot layer

The stick is built in one of two profiles.

Default (WinPE-direct). The stick boots straight into WinPE through WinPE's own Microsoft-signed Windows boot manager. Nothing unsigned is in the boot path, so Secure Boot can stay on on the machine being serviced, with no firmware changes. This is the common path, since the machines Vector services are almost always Windows.

Optional (`-WithLinuxBoot`). The stick uses a custom branded GRUB2 bootloader (UEFI) with a menu that offers WinPE plus the Linux repair tools. GRUB chainloads WinPE and loopback-boots a fixed, known set of Linux ISOs; Vector does not reimplement the hardest trick that tools like Ventoy solve, booting an arbitrary unknown ISO in place, because the payload is curated. GRUB is not Microsoft-signed, so this stick needs Secure Boot turned off to boot. That is normal for a technician USB and is a one-time, reversible firmware toggle on the machine being serviced.

## Launcher

A C# WPF application targeting .NET Framework 4.8, built from the .NET SDK command line so it does not require full Visual Studio.

- It runs as the WinPE shell, full screen, so a tech cannot get lost or crash to a bare desktop. It also runs on a live Windows system.
- It is environment aware. It detects WinPE versus live Windows and only offers tools that make sense in that environment. For example fan control and the AV scanners are hidden or disabled in WinPE because they need a full running Windows.
- It is manifest driven. It reads config/tools-manifest.json to build the categories and tool cards, and shows each tool's status (ready, not found, built in).
- It includes a manage-tools screen that adds, edits, and removes tools and writes the manifest, so a tech can extend the kit without editing code.

The built-in tools stay as PowerShell scripts. The launcher runs them as separate processes. The launcher's job is the menu, status, launching, and the manage-tools screen.

## Persistence

WinPE itself is disposable by design. Its RAM disk resets on every boot, and there is no supported persistence layer for the OS. That is fine here, because the persistence that matters lives on the exFAT data partition: captured images, backups, reports, driver packs, and AV definitions all persist there. Portable tools also keep their settings next to their own executable on the data partition, so tool state persists without needing a persistent OS.

If a fully installable, persistent OS were ever wanted, that would be a different product (Windows To Go or a persistent Linux install), with its own tradeoffs. For a repair kit, disposable WinPE plus a large persistent data partition is the right shape.

## Distribution

Vector is distributed as source that a tech clones and builds, not as a prebuilt image. The repo holds the launcher, scripts, build pipeline, manifest, and branding, but no tool binaries. A build resolver fetches or copies the binaries once, then the finished stick is self contained. See ADDING_TOOLS.md for the bring-your-own-tools model.
