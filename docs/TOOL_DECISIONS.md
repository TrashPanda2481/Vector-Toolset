# Vector Toolset - Tool and Architecture Decisions

Status: planning locked. The chosen tool list, and what was dropped or avoided.

---

## Concept

Rebuild of the old Linux live-build diagnostic USB into a **branded, self-contained WinPE-based
IT technician's toolkit**. Two modes from one stick:

1. **Boot FROM it** — WinPE diagnostic environment (native boot), launches the branded HTA launcher.
2. **Plug INTO a running system** — portable tools accessible from Explorer on live Windows/Mac.

Manifest-driven (`config/tools-manifest.json`) so tools can be added without rebuilding the image.

## Boot architecture — "our own Ventoy" (leading plan)

Custom **branded GRUB2 multiboot** (BIOS + UEFI). We do NOT reimplement Ventoy's hardest trick
(arbitrary-ISO driver injection) because we control the payload:

- **WinPE** — laid down natively (flagship entry) → HTA launcher
- **Linux tools** — booted via GRUB `loopback` (they support it)

Tradeoff: adding a brand-new arbitrary ISO later = a menu-entry edit, not drag-drop. Fine for a
curated product. Secure Boot: our GRUB isn't MS-signed → tech disables Secure Boot to boot (normal).

## Cloning strategy (resolved)

No free Windows-native block-level cloner exists post-Macrium-Free EOL. Covered by:
- **Clonezilla** (boot entry) — full block-level cloning
- **DISM Imager** (our WinPE build) — file-level reimage for the 80% "redeploy Windows" case
- **GNU ddrescue** (boot entry) — image failing drives

## Fan control (resolved)

Live-Windows-only capability (needs kernel driver + admin; does NOT work in WinPE). Tools live in
the plugged-in tools folder: **FanControl (Rem0o)** desktop + **nbfc-revive** laptop.

---

## LOCKED TOOL LIST

### Built-in (our own scripts + native)
Full Diagnostic Report · SMART Health Check · Product Key Finder · Stress Test · **DISM Imager** (to build) · diskpart · DISM/SFC

### Hardware ID & sensors
HWiNFO · GPU-Z · Sysinternals Suite · Libre Hardware Monitor

### Fan control (live-Windows only)
FanControl (Rem0o) · nbfc-revive

### Storage / benchmark / stress
CrystalDiskInfo · smartmontools · CrystalDiskMark · ATTO · FurMark · Prime95 · OCCT

### Disk space
WinDirStat · WizTree ⚠ _(WizTree is not free for commercial use — needs a license for shop use)_

### Drivers
3DP Net · 3DP Chip · DISM /Add-Driver · DDU · Driver Store Explorer (Rapr) · Double Driver · **SDI Origin** _(last-resort, isolated — AV-flag optics risk)_

### Partitioning / cloning / imaging
diskpart · MiniTool Partition Wizard Free · Rufus · Active@ KillDisk Free

### Data recovery
Recuva · PhotoRec · TestDisk · DMDE Free

### Malware / security
Emsisoft Emergency Kit · KVRT · ClamWin/ClamAV · AdwCleaner · rkill · FRST · Autoruns

### Network / firewall
Advanced IP Scanner · Wireshark · PuTTY · WinSCP · Windows Firewall Control (BiniSoft) · vt-cli · Nmap · Angry IP Scanner · WifiInfoView · TCPView · iperf3 · NetSetMan

### Windows repair
NTPWEdit · Tweaking.com Windows Repair _(aggressive — prompts for restore point)_

### Password / key
ProduKey · NirLauncher (full NirSoft suite)

### File / system utilities
7-Zip · Notepad++ · Everything · FastCopy · Process Explorer · RegCool · System Informer · BleachBit · TeraCopy

### Remote support
RustDesk _(primary, self-host relay)_ · AnyDesk _(alternative)_

### Web
Firefox Portable

### Boot-level entries (custom bootloader)
Clonezilla · ShredOS (nwipe) · Memtest86+ · GParted Live · GNU ddrescue · Offline NT Password (chntpw)

---

## DROPPED (redundant / declined)
CPU-Z · HWMonitor · Speccy · Core Temp · TreeSize · HeavyLoad · y-cruncher · AOMEI Partition Assistant · R-Linux · Malwarebytes Free · MS Safety Scanner · TDSSKiller · LazeSoft · UltraVNC · Argus Monitor

## AVOID (abandoned / adware / trial-locked / trust)
AIDA64 · Open Hardware Monitor · SpeedFan · Hard Disk Sentinel · AS SSD · IntelBurnTest · SpaceSniffer · Disk Drill · HitmanPro · ESET Online Scanner · Sophos Scan & Clean · GMER · RootkitRevealer · Hiren's/Strelec (reference only) · Ophcrack · CCleaner · ImgBurn · TeamViewer QuickSupport · Chrome Remote Desktop

---

## Open threads for next session
- **Branding** — name (working: "IT Toolset"), palette, logo, boot splash. NOT started.
- **HTA launcher bug** — `launcher/index.hta` starts but window never appears after the encoding
  fix (OpenTextFile flag −1→0). Silent crash unresolved. `scratchpad/test.hta` was the diagnostic.
- **Windows ADK** — required to build the WinPE image; NOT installed yet.
- **Custom GRUB2 bootloader** — design/build the branded multiboot layer.
- **Legacy Linux files** — old live-build files still in tree, cleanup pending.
- Tool binaries are tech-supplied (not tracked in git per `.gitignore`).
