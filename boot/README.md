# Vector Toolset boot layer

This is the custom GRUB2 multiboot menu. GRUB is the primary bootloader on the
stick. WinPE boots natively (GRUB chainloads the Windows boot manager). The Linux
tools boot from their ISO files by GRUB loopback.

## Files here

- `grub.cfg` - the menu: entries, theme load, partition lookup by label.
- `theme/theme.txt` - the branded theme (charcoal background, orange accent).
- `grub/embedded.cfg` - the config baked into the standalone GRUB binary; it
  finds the VECTORPE partition by label and loads the real menu (`grub.cfg`).
- `grub/` - also receives the prebuilt GRUB binaries after a build; those are
  gitignored (see below).

## Partition layout the menu expects

Deploy-USB.ps1 creates a 2-partition GPT stick:

- `VECTORPE` - a FAT32 EFI System Partition that holds both GRUB
  (`EFI\BOOT\BOOTX64.EFI`, `grub.cfg`, the theme, and fonts) and the WinPE media
  from `build/winpe-work/media` (bootmgr, BCD, `sources\boot.wim`,
  `EFI\Microsoft\Boot\bootmgfw.efi`). GRUB chainloads the WinPE boot manager
  from here.
- `VECTORDATA` - the big exFAT data partition. Holds `tools\` (the toolkit the
  launcher reads) and `payload\*.iso` (the Linux tool ISOs GRUB loopback-boots).

Putting the payload ISOs on the exFAT data partition keeps the stick to two
partitions and lets GRUB read them with its exfat module.

## How GRUB gets installed (the hard part on Windows)

Installing GRUB normally uses `grub-install`, a Linux tool. From Windows we avoid
it by shipping a prebuilt GRUB image:

- UEFI (the supported path): a standalone `grubx64.efi` built with
  `grub-mkstandalone` (modules baked in), copied to
  `VECTORPE\EFI\BOOT\BOOTX64.EFI`. UEFI firmware auto-runs that path, so no
  installer is needed. `grub.cfg`, the theme, and the fonts go alongside it.
- BIOS/legacy (a follow-up): needs GRUB's `boot.img` in the MBR and `core.img`
  in a BIOS-boot region, which normally wants `grub-bios-setup`. UEFI first;
  BIOS is not wired up yet.

`build/Build-Grub.ps1` builds the binaries (it uses WSL and `grub-mkstandalone`).
It produces `boot/grub/grubx64.efi` (a self-contained UEFI GRUB with the modules
and `boot/grub/embedded.cfg` baked in) and `boot/grub/fonts/unicode.pf2`. Both
are gitignored. Deploy-USB.ps1 copies these onto the stick.

## Menu entries

The menu (`grub.cfg`) offers WinPE plus the Linux tools, all boot-tested on real
hardware:

- WinPE - chainloads the Windows boot manager on VECTORPE.
- Clonezilla, GParted Live - loopback-booted from their ISOs.
- Memtest86+ - the EFI binary for UEFI.
- SystemRescue - a single entry that hosts ddrescue, chntpw, testdisk, and a
  recovery shell, covering several boot-level tools at once.
- ShredOS - buildroot-based secure wipe; its rootfs is embedded in the kernel.

## Design notes

- `timeout=-1` means the menu waits for a choice (no auto-boot), per the locked
  architecture.
- The theme needs a GRUB font (.pf2). The stock `unicode.pf2` from a GRUB build
  works; if the font name or size does not match, generate one with `grub-mkfont`
  and update the names in `theme.txt`.
- Secure Boot: this GRUB is not Microsoft-signed, so on Secure Boot machines the
  tech disables Secure Boot to boot the stick. Normal for a technician USB.
