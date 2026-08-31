# Adding Tools to Vector Toolset

Vector ships as a framework with a curated default set. The tool binaries are not in this repo. Most of the tools are freeware that cannot be legally redistributed, and even the open source ones would bloat the git history. So you supply the tools you are licensed to use, and the build puts them on the stick.

This is the bring-your-own-tools model. You can use the recommended set, add your own proprietary or licensed tools, or ignore the recommendations entirely and build a stick of only your own tools.

## Where binaries come from

The build resolves each tool in this order:

1. Local stash. If the binary exists in your private stash folder, it is copied in. This is the normal path today.
2. Download. If the manifest lists a stable source URL, the resolver downloads it and verifies it against the recorded hash where one is available.
3. Report missing. If neither works, the tool is listed as add manually, with its source link.

This means a tool with a stable link can be fetched automatically, and a tool behind a click-through or an unstable link is a documented manual step. Nothing about the pipeline changes as tools move from manual to automatic later.

## The local stash

Your private, verified copies of the tool binaries live outside the repo so they can never be committed by accident. Keep them in a folder beside the repo, for example a sibling named `Vector-Toolset-Binaries`.

It mirrors the tools folder structure, for example:

    Vector-Toolset-Binaries\diagnostics\
    Vector-Toolset-Binaries\disk\
    Vector-Toolset-Binaries\drivers\
    Vector-Toolset-Binaries\network\
    Vector-Toolset-Binaries\security\
    Vector-Toolset-Binaries\recovery\
    Vector-Toolset-Binaries\utilities\
    Vector-Toolset-Binaries\fan-control\

Drop each tool's portable files into the matching folder. Point the build at this folder when you run it.

## Adding a tool by hand

1. Place the portable executable under the correct category, matching the path in the manifest.
2. Make sure the manifest entry exists in config/tools-manifest.json with the tool's name, description, category, target path, and its flags (for example whether it is a console tool and whether it is live-Windows only).
3. Build. The launcher will show the tool as ready.

## Adding a tool with the manage-tools screen

The launcher includes a manage-tools screen. Point it at any executable, set the category and the flags, and it writes the manifest entry for you. This is the easiest way to add your own tools, including proprietary ones, without editing files by hand.

## Legal note

This repo never redistributes anyone's software. You are responsible for supplying only tools you are licensed to use and distribute on your own stick. The recommended list in TOOL_DECISIONS.md is a set of pointers, not a bundle.
