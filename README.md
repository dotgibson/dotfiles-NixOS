# dotfiles-NixOS

The NixOS machine repo. Vendors [Core](../dotfiles-core) under `core/`
and adds the NixOS-native layer (`os/nixos.zsh`, package manager, paths).

## The capability declaration

`os/nixos.capabilities` tells Core how THIS archive updates: the package-manager
verbs, the scheduler, and which tools are opt-in here. Core's `up`, its maintenance
runner and `core-doctor` all dispatch through it, so it is the file that stops Core
from carrying NixOS knowledge it has no business having.

**The scaffold shipped Fedora's values.** Replace them —
`core/PORTING-MATRIX.md` §"Package-manager commands" tabulates every archive, and
`core/examples/os.capabilities.example` documents every key. Then:

```bash
core/scripts/check-capabilities.sh os/nixos.capabilities
```

In this schema an **omission is a statement**: no `PKG_ASSUME_YES` means never
auto-confirm, no `PKG_UPGRADE_PARTIAL` means `up -i` refuses, and no
`MAINT_UNATTENDED_UPGRADE` means the scheduled runner will not apply system upgrades
here. Leave a key out to mean those things; do not add one to be helpful.

## Install

```bash
./bootstrap.sh
```

## Gates

`make help` lists every target. The seven that exist in every repo vendoring Core —
`help`, `lint`, `check`, `dry-run`, `packages-check`, `core-verify`, `test` — are
the fleet's Makefile vocabulary (dotfiles-core's `VENDORING.md` — the source repo, it is
not vendored into `core/` — § "The `make` vocabulary, and the
test floor"); keep those names and add your own beside them. `make test` runs `test/`,
which `.github/workflows/test.yml` also runs on **default-branch pushes and pull
requests** (its filter is `branches: [main, master]` — a feature-branch push with no PR
open runs nothing); `make lint` runs the
blocking legs of Core's reusable lint gate with whatever tools are on PATH — a leg whose
tool is not installed says so and skips — while `.github/workflows/lint.yml` calls the
gate itself, with pinned tool versions and its advisory legs, and is the verdict.
`packages-check` is a stub until this repo has an `install/packages.txt`.

## Update Core

Core is fanned out **from Core**, not pulled from here. A raw `git subtree pull` moves
`core/` but not `core.lock`, and `core-integrity` then reports this tree as TAMPERED.

Normally a sync arrives as a PR from Core's fan-out and you just merge it. To run one
by hand, from a `dotfiles-core` checkout:

```bash
./scripts/sync-core.sh dotfiles-NixOS   # materializes core/ AND stamps core.lock
```

Then, in this repo:

```bash
./bootstrap.sh          # re-link any new/changed Core files
```
