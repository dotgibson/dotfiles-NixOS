# dotfiles-NixOS

The NixOS machine repo. Vendors [Core](https://github.com/dotgibson/dotfiles-core) under
`core/` and adds the NixOS-native layer — with one thing no other repo in this fleet has:
a **second owner**.

[![dotfiles-NixOS — terminal demo](assets/demo.gif)](https://dotgibson.github.io/dotfiles-web)

## The boundary

On every other machine repo, `bootstrap.sh` is the only thing that owns your `$HOME`.
Here, `nix/` owns part of it — and the split is exact:

| | owns |
| --- | --- |
| [`nix/`](nix/) (`nixos.nix`, `home.nix`) | packages · `PATH` · tpm · the login-shell **declaration** |
| [`bootstrap.sh`](bootstrap.sh) | **every link** · the zsh entry (`~/.zshrc`, `$ZDOTDIR/.zshrc`) |

`home.nix` therefore declares **no `home.file`, no `programs.zsh`**, and exactly one
`xdg.configFile` (tpm — see below). That is not a style preference. It is the only
arrangement that works, and it was measured on a booted NixOS 25.05 guest:
[`nix/README.md`](nix/README.md) has the mechanism, and dotfiles-core's
`NON-MUTABLE-HOST-PROPOSAL.md` §5 R3 has the run.

**What happens if you ignore it.** Add `home.file`, `xdg.configFile` or `programs.zsh`
for anything the driver links, and:

1. the driver **silently relinks** your declaration on its next run — a differing symlink
   is a relink, not a foreign file, so there is no backup and no warning; then
2. home-manager **refuses to activate at all** — not that path, the *whole* activation,
   exit 1 at `checkLinkTargets` — because the one file whose bytes genuinely differ is
   `$ZDOTDIR/.zshrc`, and `-b` cannot back up a foreign symlink.

One file deadlocks everything. So a home gets one link owner, and it is `bootstrap.sh`.

tpm is the documented exception, and it is safe for a reason you can check:
`blib_link_core` does not *link* tpm, it **presence-guards** it (`[[ ! -d … ]]` then
clone), and `[[ -d ]]` follows symlinks — so a home-manager-owned tpm makes the driver
skip its clone entirely. It is also better: a rev-locked fetch instead of an unpinned
clone of `master`.

## Install

Order matters, and it is **`nix` first**.

```bash
# 1. import nix/nixos.nix from your configuration.nix, then
sudo nixos-rebuild switch

# 2. the package set, PATH and tpm
home-manager switch          # or via the NixOS module — see nix/README.md

# 3. only now, the links
./bootstrap.sh
```

Not the other way round: on NixOS, home-manager is evaluated and activated at *system*
activation, **before any checkout necessarily exists**. An activation script that seeds
from a clone cannot work here — measured — which is why seeding is `bootstrap.sh`'s job
and it runs last.

`./bootstrap.sh` installs nothing and never escalates: with no provision hook and
`BOOTSTRAP_LOGIN_SHELL=0`, Core's driver never resolves a privilege escalator at all.
Where the rest of the fleet runs `chsh`, this repo **prints the declaration** for you to
put in `nix/nixos.nix`, because a hand-set login shell is exactly the state
`nixos-rebuild switch` does not reproduce.

## The capability declaration

`os/nixos.capabilities` tells Core how THIS host updates: the package-manager verbs, the
scheduler, and which tools are opt-in here. Core's `up`, its maintenance runner and
`core-doctor` all dispatch through it, so it is the file that stops Core from carrying
NixOS knowledge it has no business having.

```bash
core/scripts/check-capabilities.sh os/nixos.capabilities
```

This is the fleet's only `PROVISIONER=declarative` host, and two of its entries are worth
knowing:

- **`PKG_COUNT_PENDING` is absent**, and that is legal here. "Packages pending" is not
  something a declarative box knows — the nearest question needs root's channel and lists
  derivations, not packages. Core's validator permits the absence under this provisioner,
  and `up` reads it as the sentinel that keeps the once-a-day nudge quiet.
- **`PKG_INSTALL=nix-env -i` is declared but not aliased.** The schema needs a true
  imperative verb and that is one — it is also the documented anti-pattern, since a
  user-profile generation is what a rebuild will not reproduce. Declaring it is honesty;
  putting it two keystrokes away would be promotion. Use `home.packages`, or `nxsh`
  (`nix-shell -p`) for five minutes.

In this schema an **omission is a statement**: no `PKG_ASSUME_YES` means never
auto-confirm, no `PKG_UPGRADE_PARTIAL` means `up -i` refuses, and no
`MAINT_UNATTENDED_UPGRADE` means the scheduled runner will not apply system upgrades here
— because NixOS has `system.autoUpgrade` and two upgraders racing on one box is worse
than none. Leave a key out to mean those things; do not add one to be helpful.

## Gates

`make help` lists every target. The seven that exist in every repo vendoring Core —
`help`, `lint`, `check`, `dry-run`, `packages-check`, `core-verify`, `test` — are the
fleet's Makefile vocabulary (dotfiles-core's `VENDORING.md` § "The `make` vocabulary, and
the test floor"); keep those names and add your own beside them.

`make test` runs `test/`, which `.github/workflows/test.yml` also runs on **default-branch
pushes and pull requests** (its filter is `branches: [main, master]` — a feature-branch
push with no PR open runs nothing); `make lint` runs the blocking legs of Core's reusable
lint gate with whatever tools are on PATH — a leg whose tool is not installed says so and
skips — while `.github/workflows/lint.yml` calls the gate itself, with pinned tool
versions and its advisory legs, and is the verdict.

**`packages-check` is a stub by design**, not "until this repo has an
`install/packages.txt`". There is no such file and there should not be: `nix/home.nix`
owns the package set as nixpkgs attributes. That is the boundary, not an omission — and
it is also why `.github/workflows/bootstrap.yml` declares no `packages_check` and no
`schedule`.

## Update Core

Core is fanned out **from Core**, not pulled from here. A raw `git subtree pull` moves
`core/` but not `core.lock`, and `core-integrity` then reports this tree as TAMPERED.

Normally a sync arrives as a PR from Core's fan-out and you just merge it. To run one by
hand, from a `dotfiles-core` checkout:

```bash
./scripts/sync-core.sh dotfiles-NixOS   # materializes core/ AND stamps core.lock
```

Then, in this repo:

```bash
./bootstrap.sh          # re-link any new/changed Core files
```
