# Vector Toolset

A branded, self-contained WinPE toolkit for IT technicians. Build it once, carry it on a USB stick, and use it two ways from the same stick:

1. Boot a machine from it, into a WinPE diagnostic environment that opens the Vector launcher.
2. Plug it into a running Windows, Mac, or Linux system and use the tools from an accessible folder.

The goal is a diagnostic and repair kit that is intuitive and stress free, built the way an IT specialist would want it, so a tech does not have to assemble one from scratch.

## What this is

A personal IT rescue toolkit and a portfolio build. I built it to own my own stick end to end and to work through the engineering, not to displace the established toolkits. If you just need a loaded rescue USB today, the mature options below are the honest recommendation. Vector is the version I wanted to build and control myself.

## How it compares

The space is well served, and Vector does not try to unseat it:

- Loaded, ready-to-boot rescue kits: Hiren's BootCD PE, Sergei Strelec's WinPE, MediCat. Download and go.
- Multiboot USB loader: Ventoy. Drag ISOs on and boot them, Secure Boot included.
- Build-your-own custom WinPE: PEBakery and its projects (Win10PESE, Win10XPE, PhoenixPE).

What Vector does for its own sake: one opinionated, environment-aware launcher that runs both as the WinPE shell and on a live system; a bring-your-own-tools manifest so the stick holds exactly the tools you choose and nothing else; and a repo that ships no binaries, so the whole thing is license-clean and reproducible from source.

## What it demonstrates

For anyone reading this as a portfolio piece, the engineering underneath:

- A WinPE image built and customized with the Windows ADK and DISM: optional components, driver injection, and a WPF app set as the boot shell.
- A branded GRUB2 multiboot layer built from scratch (grub-mkstandalone via WSL) that chainloads WinPE and loopback-boots Linux tool ISOs, on both BIOS and UEFI.
- A C# WPF launcher (.NET Framework 4.8) that renders as a locked kiosk shell in WinPE and as a normal app on live Windows, driven by a JSON tool manifest.
- A guarded USB deploy: GPT partitioning into an EFI system partition plus an exFAT data partition, with a wipe path that survives the Windows removable-disk auto-init race.

## Status

Boot chain proven on real hardware (themed GRUB menu, WinPE, and the Linux tools all boot). See `docs/` for the design and `docs/BUILD_PLAN.md` for the pipeline.

## How it works, in short

- By default the stick boots straight into WinPE through the Microsoft-signed Windows boot manager, so Secure Boot can stay on on the machine you plug it into. An optional build (`-WithLinuxBoot`) adds a custom GRUB2 menu with Linux repair tools (Clonezilla, ShredOS, Memtest86+, GParted, SystemRescue); that one needs Secure Boot off, because GRUB is not Microsoft-signed.
- WinPE stays small. It loads a tiny core into memory and reaches the rest of the tools from a large data partition on the stick.
- That data partition is exFAT, so the same tool folder is readable when booted into WinPE and when the stick is plugged into a live system.
- The launcher is a C# WPF app that runs as the WinPE shell and also runs on a live Windows box. It is aware of which environment it is in and only offers tools that make sense there.

## Repo layout

    launcher/    C# WPF launcher source
    scripts/     built-in PowerShell tools (diagnostics, SMART, keys, stress, imaging)
    config/      tools-manifest.json (tools and categories), shop.json (branding)
    build/       the build pipeline scripts
    boot/        GRUB2 config, theme, menu
    branding/    splash, logo, icons
    docs/        architecture, build plan, tool decisions, branding, adding tools
    tools/       empty placeholders; binaries are fetched or supplied, never in git

## Building your own stick

Full detail is in `docs/BUILD_PLAN.md`. The short version:

Prerequisites (install once):

- Windows ADK plus the WinPE add-on
- The .NET SDK (provides `dotnet`)
- Scoop for some tool downloads: `irm get.scoop.sh | iex`
- WSL with an Ubuntu or Debian distro - only for the optional Linux-boot stick
  (that is where GRUB is built); the default stick does not need it

Then build and deploy with two commands. Part 1 runs from a normal prompt (the tool
fetch uses Scoop, which will not run as admin); part 2 runs elevated (WinPE imaging
and disk partitioning need Administrator).

1. Normal prompt - builds the launcher and fetches the tools:

       powershell -ExecutionPolicy Bypass -File build\Make-Stick.ps1

2. Elevated prompt - bakes WinPE and writes the stick. Run it once with no disk number
   to list disks, then again with the target number:

       powershell -ExecutionPolicy Bypass -File build\Deploy-Stick.ps1
       powershell -ExecutionPolicy Bypass -File build\Deploy-Stick.ps1 -DiskNumber <N>

This builds the default stick: it boots straight into WinPE, so Secure Boot can stay
on on the machine you plug it into. The deploy wipes the target disk; it refuses a
non-USB or system disk and makes you type the disk number to confirm.

### Optional: add the Linux boot tools

To also get the GRUB multiboot menu (Memtest86+, Clonezilla, GParted, ShredOS,
SystemRescue), pass `-WithLinuxBoot` to both commands. This needs WSL (GRUB is built
there), and the resulting stick needs Secure Boot turned off to boot, because GRUB is
not Microsoft-signed:

       powershell -ExecutionPolicy Bypass -File build\Make-Stick.ps1 -WithLinuxBoot
       powershell -ExecutionPolicy Bypass -File build\Deploy-Stick.ps1 -DiskNumber <N> -WithLinuxBoot

You supply the tool binaries you are licensed to use (see `docs/ADDING_TOOLS.md`); most
are freeware that cannot be redistributed, so they are never in this repo.

## Adding your own tools

Vector ships as a framework with a curated default set. The tool binaries are not in this repo, because most are freeware that cannot be redistributed and would bloat the history. You supply the tools you are licensed to use, including your own proprietary ones, and the launcher picks them up. See `docs/ADDING_TOOLS.md`.

## Documentation

- `docs/ARCHITECTURE.md` - how the stick and the software are structured
- `docs/BUILD_PLAN.md` - what gets built, in what order, and what each part needs
- `docs/TOOL_DECISIONS.md` - the locked tool list and what was dropped or avoided
- `docs/BRANDING.md` - name, palette, typography, and voice
- `docs/ADDING_TOOLS.md` - how tool binaries are supplied and added

## License

MIT, see `LICENSE`. This covers the Vector Toolset code (launcher, scripts, configs,
build pipeline). It does not cover any third-party tools you add to a stick; those keep
their own licenses and are never included in this repo.
