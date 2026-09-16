# `nix/` — the declarative half

Two importable modules and one rule.

| File | Scope | Owns |
| ---- | ----- | ---- |
| [`nixos.nix`](nixos.nix) | system | `programs.zsh.enable`, the `users.users.<you>.shell` declaration, the two packages needed before home-manager runs |
| [`home.nix`](home.nix) | home-manager | every package, `PATH`, tpm |

Everything else — every symlink, and the zsh entry — belongs to
[`../bootstrap.sh`](../bootstrap.sh).

## The rule

> `nix/` owns **packages, PATH, tpm and the login-shell declaration**.
> `bootstrap.sh` owns **every link and the zsh entry**.
> `home.nix` declares no `home.file`, no `programs.zsh`, and exactly one `xdg.configFile`.

It is not a preference. It is the only arrangement that works, and it was measured on a
booted NixOS 25.05 guest — `dotfiles-core`'s `NON-MUTABLE-HOST-PROPOSAL.md` §5 R3
(dotgibson/dotfiles-core#1004).

**The driver wins every collision, silently.** home-manager links a home path at a symlink
*in the store* that points at your checkout — two hops. `blib_link` sees a symlink whose
target is not the checkout, calls it wrong, and replaces it. A differing symlink is a
*relink*, not a foreign file, so there is no backup and no warning. Measured: 25 of 28
home-manager links relinked on the first driver run.

**home-manager tolerates that — until it cannot.** Its collision check compares *content*
(`cmp -s`), and a direct link into the checkout has the same bytes as its own two-hop one.
For 27 of 28 paths it printed *"in the way … will be skipped since they are the same"* and
carried on. The 28th was `$ZDOTDIR/.zshrc`, where the bytes genuinely differ — and `-b`
does not help, because home-manager backs up only a *regular* foreign file, never a
foreign symlink. Exit 1 at `checkLinkTargets`, before a single link is touched.

So the entire fight is over **one file**: the zsh entry. Turn `programs.zsh` on in
`home.nix` and this home becomes one home-manager can no longer activate at all until that
link is removed — and the driver's next run would put it back.

## Install

Order matters, and it is `nix` first.

```bash
# 1. channels (skip if you manage this box with flakes — see below)
sudo nix-channel --add https://nixos.org/channels/nixos-25.05 nixos
nix-channel --add https://github.com/nix-community/home-manager/archive/release-25.05.tar.gz home-manager
nix-channel --update && sudo nix-channel --update

# 2. import nix/nixos.nix from your configuration.nix, then
sudo nixos-rebuild switch

# 3. home-manager — as the NixOS module (recommended) or standalone; see below
home-manager switch

# 4. only now, the links
./bootstrap.sh
```

**Why `nix` first and not the other way round.** On NixOS, home-manager is evaluated and
activated at *system* activation — before any repo checkout necessarily exists. An
activation script that seeds from a checkout therefore **cannot work here**, and must
never be added to `home.nix`: the R3 probe's `mise` seed fired on Fedora and silently did
not on NixOS, for exactly this reason. Seeding is `bootstrap.sh`'s job, which is why it
runs last.

## The two ways to run home-manager

**As the NixOS module** (recommended — it sets `home.username` and `home.homeDirectory`
for you):

```nix
# in your configuration.nix
imports = [ <home-manager/nixos> ];
home-manager.useGlobalPkgs = true;
home-manager.users.you = import /home/you/dotfiles-NixOS/nix/home.nix;
```

**Standalone** — uncomment the two placeholder lines at the top of `home.nix` first. Note
that `home.nix` carries `programs.home-manager.enable = true` because a standalone first
`switch` replaces the user profile and takes the `home-manager` binary with it otherwise
(measured).

## Flakes

This repo is written for a **channel-managed** box, and `os/nixos.capabilities` says so.
Both files here are *plain modules*, so a flake user imports them unchanged — that is the
reason this directory ships no `flake.nix`. The declaration's two verbs change:

| | channel | flake |
| --- | --- | --- |
| refresh | `sudo nix-channel --update` | `nix flake update` |
| upgrade | `sudo nixos-rebuild switch --upgrade` | `nixos-rebuild switch --flake .` |

Core's once-a-day nudge deliberately does not probe flake state: `nix flake metadata`
was measured at 140 s.

## Changing the package set

Edit `home.packages` in [`home.nix`](home.nix) and `home-manager switch`. There is no
`install/packages.txt` in this repo and `make packages-check` is a stub **by design** —
that is the boundary, not an omission.

`nix-env -i` works and is declared in `os/nixos.capabilities`, because the capability
schema needs a true imperative verb and that is one. It is still the documented
anti-pattern: a user-profile generation is exactly the state `nixos-rebuild switch` will
not reproduce. `os/nixos.zsh` declines to alias it for that reason. Reach for
`nxsh` (`nix-shell -p`) when you want a tool for five minutes, and `home.packages` when
you want to keep it.
