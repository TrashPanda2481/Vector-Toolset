# Vector Toolset boot layer

This is the custom GRUB2 multiboot menu, the "our own Ventoy" piece. GRUB is the
primary bootloader on the stick. WinPE boots natively (GRUB chainloads the
Windows boot manager). The Linux tools boot from their ISO files by GRUB
loopback.

## Files here

- `grub.cfg` - the menu: entries, theme load, partition lookup by label.
- `theme/theme.txt` - the branded theme (charcoal background, orange accent).
- `grub/` - prebuilt GRUB binaries go here (NOT yet added, see below).

## Partition layout the menu expects

Deploy-USB.ps1 (not yet written) creates a GPT stick with these labels:

- `VECTORPE` - small FAT32/NTFS partition with the WinPE media from the
  `build/winpe-work/media` folder (bootmgr, BCD, `sources\boot.wim`,
  `EFI\Microsoft\Boot\bootmgfw.efi`). GRUB chainloads this for the WinPE entry.
- `VECTORDATA` - the big exFAT data partition. Holds `tools\` (the toolkit the
  launcher reads) and `payload\*.iso` (the Linux tool ISOs GRUB loopback-boots).
- ESP (FAT32) - holds GRUB itself: `EFI\BOOT\BOOTX64.EFI` plus `grub.cfg`, the
  theme, and fonts under the GRUB prefix.

Putting the payload ISOs on the exFAT data partition keeps the layout to three
partitions and lets GRUB read them with its exfat module.

## How GRUB gets installed (the hard part on Windows)

Installing GRUB normally uses `grub-install`, a Linux tool. From Windows we avoid
it by shipping prebuilt GRUB images:

- UEFI (the easy, dominant path): a standalone `grubx64.efi` built with
  `grub-mkstandalone` (with the modules baked in), copied to
  `ESP\EFI\BOOT\BOOTX64.EFI`. UEFI firmware auto-runs that path, so no installer
  is needed. `grub.cfg`, `theme/`, and the fonts go next to it under the prefix.
- BIOS/legacy (harder): needs GRUB's `boot.img` in the MBR and `core.img` in a
  BIOS-boot region, which normally wants `grub-bios-setup`. Options: run that
  step from a small Linux helper, or ship a prebuilt BIOS core and write it with
  a Windows tool. Treat BIOS as a follow-up; UEFI first.

The GRUB binaries are built by `build/Build-Grub.ps1` (it uses WSL and
`grub-mkstandalone`). It produces `boot/grub/grubx64.efi` (a self-contained UEFI
GRUB with the modules and `boot/grub/embedded.cfg` baked in) and
`boot/grub/fonts/unicode.pf2`. Both are gitignored. `embedded.cfg` finds the
VECTORPE partition by label and loads the real menu (`grub.cfg`). Deploy-USB.ps1
copies these onto the stick. BIOS/legacy support (an i386-pc core with the
`ntldr` module) is a follow-up.

## Per-distro entries to verify

WinPE, Clonezilla, and GParted use reliable, known patterns. The rest are marked
`VERIFY` in `grub.cfg` and need their kernel/initrd paths and boot parameters
checked against the actual ISO contents once the ISOs are in `payload\`:

- Memtest86+ - ships as an EFI binary (`memtest.efi`) for UEFI; BIOS uses a
  separate image.
- SystemRescue - a single powerful entry that can host ddrescue, chntpw,
  testdisk, and a recovery shell, covering several TOOL_DECISIONS boot items at
  once. Verify its kernel/initrd paths.
- ShredOS - buildroot-based; confirm its kernel and initrd paths from the ISO.

## Design notes

- `timeout=-1` means the menu waits for a choice (no auto-boot), per the locked
  architecture.
- The theme needs a GRUB font (.pf2). The stock `unicode.pf2` from a GRUB build
  works; if the font name or size does not match, generate one with
  `grub-mkfont` and update the names in `theme.txt`.
- Secure Boot: this GRUB is not Microsoft-signed, so on Secure Boot machines the
  tech disables Secure Boot to boot the stick. This is normal for a technician
  USB and matches the plan.
