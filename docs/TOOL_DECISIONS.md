# Vector Toolset - Tool and Architecture Decisions

The chosen tool list and the architecture decisions behind it, with what was
dropped or avoided and why. This is the record of what was decided; see
ARCHITECTURE.md for how the pieces fit and BUILD_PLAN.md for the build order.

---

## Concept

A branded, self-contained WinPE-based IT technician toolkit, rebuilt from an
older Linux live-build diagnostic USB. Two modes from one stick:

1. Boot FROM it - a WinPE diagnostic environment (native boot) that launches the
   Vector WPF launcher as its shell.
2. Plug INTO a running system - portable tools accessible from Explorer on live
   Windows (and readable on Mac/Linux, since the data partition is exFAT).

Manifest-driven (`config/tools-manifest.json`), so tools can be added without
rebuilding the image.

## Boot architecture - custom GRUB2 multiboot

A branded GRUB2 multiboot layer (UEFI; BIOS is a follow-up). The payload is
curated, so Vector does not reimplement Ventoy's arbitrary-ISO driver injection:

- WinPE - laid down natively as the flagship entry; GRUB chainloads the Windows
  boot manager.
- Linux tools - booted from their ISO files by GRUB loopback.

Tradeoff: adding a brand-new arbitrary ISO later is a menu-entry edit, not a
drag-and-drop. That is fine for a curated kit. Secure Boot: this GRUB is not
Microsoft-signed, so the tech disables Secure Boot to boot the stick (normal for
a technician USB).

## Cloning strategy

No free Windows-native block-level cloner exists after Macrium Reflect Free was
discontinued. Covered three ways:

- Clonezilla (boot entry) - full block-level cloning.
- DISM Imager (`scripts/Invoke-DismImager.ps1`, runs in WinPE) - file-level
  reimage for the common "redeploy Windows" case.
- GNU ddrescue (via the SystemRescue boot entry) - image failing drives.

## Fan control

A live-Windows-only capability (needs a kernel driver and admin; does not work in
WinPE). The tools live in the plugged-in tools folder: FanControl (Rem0o) for
desktops, nbfc-revive for laptops.

---

## Locked tool list

### Built-in (our own scripts + native Windows)
Full Diagnostic Report, SMART Health Check, Product Key Finder, Stress Test,
DISM Imager, diskpart, DISM/SFC

### Hardware ID and sensors
HWiNFO, GPU-Z, Sysinternals Suite, Libre Hardware Monitor

### Fan control (live-Windows only)
FanControl (Rem0o), nbfc-revive

### Storage, benchmark, stress
CrystalDiskInfo, smartmontools, CrystalDiskMark, ATTO, FurMark, Prime95, OCCT

### Disk space
WinDirStat, WizTree (note: WizTree is not free for commercial use - a shop
deployment needs a license)

### Drivers
3DP Net, 3DP Chip, DISM /Add-Driver, DDU, Driver Store Explorer (Rapr),
Double Driver, SDI Origin (last-resort, isolated - AV-flag optics risk)

### Partitioning, cloning, imaging
diskpart, MiniTool Partition Wizard Free, Rufus, Active@ KillDisk Free

### Data recovery
Recuva, PhotoRec, TestDisk, DMDE Free

### Malware and security
Emsisoft Emergency Kit, KVRT, ClamWin/ClamAV, AdwCleaner, rkill, FRST, Autoruns

### Network and firewall
Advanced IP Scanner, Wireshark, PuTTY, WinSCP, Windows Firewall Control
(BiniSoft), vt-cli, Nmap, Angry IP Scanner, WifiInfoView, TCPView, iperf3,
NetSetMan

### Windows repair
NTPWEdit, Tweaking.com Windows Repair (aggressive - prompts for a restore point)

### Password and key
ProduKey, NirLauncher (full NirSoft suite)

### File and system utilities
7-Zip, Notepad++, Everything, FastCopy, Process Explorer, RegCool,
System Informer, BleachBit, TeraCopy

### Remote support
RustDesk (primary, self-host relay), AnyDesk (alternative)

### Web
Firefox Portable

### Boot-level entries (custom bootloader)
Clonezilla, ShredOS (nwipe), Memtest86+, GParted Live, SystemRescue (hosts GNU
ddrescue, chntpw, testdisk, and a recovery shell)

---

## Dropped (redundant or declined)
CPU-Z, HWMonitor, Speccy, Core Temp, TreeSize, HeavyLoad, y-cruncher,
AOMEI Partition Assistant, R-Linux, Malwarebytes Free, MS Safety Scanner,
TDSSKiller, LazeSoft, UltraVNC, Argus Monitor

## Avoided (abandoned, adware, trial-locked, or trust)
AIDA64, Open Hardware Monitor, SpeedFan, Hard Disk Sentinel, AS SSD,
IntelBurnTest, SpaceSniffer, Disk Drill, HitmanPro, ESET Online Scanner,
Sophos Scan & Clean, GMER, RootkitRevealer, Hiren's/Strelec (reference only),
Ophcrack, CCleaner, ImgBurn, TeamViewer QuickSupport, Chrome Remote Desktop

---

## Notes

- Tool binaries are tech-supplied, not tracked in git (see `.gitignore` and
  ADDING_TOOLS.md). Most are freeware that cannot be redistributed.
- BIOS/legacy GRUB (an i386-pc core with the `ntldr` module) is a follow-up;
  UEFI is the supported path today.
