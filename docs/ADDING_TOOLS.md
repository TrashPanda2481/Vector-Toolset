# Adding Tools to Vector Toolset

Vector ships as a framework with a curated default set. The tool binaries are not in this repo. Most of the tools are freeware that cannot be legally redistributed, and even the open source ones would bloat the git history. So you supply the tools you are licensed to use, and the build puts them on the stick.

This is the bring-your-own-tools model. You can use the recommended set, add your own proprietary or licensed tools, or ignore the recommendations entirely and build a stick of only your own tools.

## Where binaries come from

Running `build\Get-Tools.ps1` (which `build\Make-Stick.ps1` calls for you) resolves
each tool in the manifest:

1. Auto-download. If `build\sources.json` lists a strategy for the tool (a GitHub
   release asset, a direct link, or a Scoop package), it is fetched into `tools\` and
   its SHA-256 is recorded. Most of the default set resolves this way.
2. Manual download. Everything else sits behind a click-through or EULA page, or its
   license does not allow redistribution. These are printed as a checklist and also
   written to `tools\MANUAL_DOWNLOADS.md` - the tool, its source URL, and the folder
   to drop it into. Download each by hand, then re-run `Get-Tools.ps1` to confirm.

The Linux boot ISOs work the same way through `build\Get-Payload.ps1` and
`build\payload.json`. As a tool moves from a click-through page to a stable link, it
just moves from list 2 to list 1; nothing else about the pipeline changes.

## Keeping an offline copy (optional)

Upstream links rot, and re-downloading on every build is slow. If you want repeatable,
offline builds, keep your own verified copies of the tool binaries in a folder outside
the repo so they can never be committed by accident - a sibling named
`Vector-Toolset-Binaries` that mirrors the `tools\` structure:

    Vector-Toolset-Binaries\diagnostics\
    Vector-Toolset-Binaries\disk\
    Vector-Toolset-Binaries\drivers\
    Vector-Toolset-Binaries\network\
    Vector-Toolset-Binaries\security\
    Vector-Toolset-Binaries\recovery\
    Vector-Toolset-Binaries\utilities\
    Vector-Toolset-Binaries\fan-control\

This is a personal convenience: copy from it into `tools\` by hand before building. The
build does not read from this folder automatically.

## Adding a tool by hand

1. Place the portable executable under the correct category, matching the path in the manifest.
2. Make sure the manifest entry exists in config/tools-manifest.json with the tool's name, description, category, target path, and its flags (for example whether it is a console tool and whether it is live-Windows only).
3. Build. The launcher will show the tool as ready.

## Adding a tool with the manage-tools screen

The launcher includes a manage-tools screen. Point it at any executable, set the category and the flags, and it writes the manifest entry for you. This is the easiest way to add your own tools, including proprietary ones, without editing files by hand.

## Legal note

This repo never redistributes anyone's software. You are responsible for supplying only tools you are licensed to use and distribute on your own stick. The recommended list in TOOL_DECISIONS.md is a set of pointers, not a bundle.
