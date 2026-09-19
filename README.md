<!-- Back to top link -->
<a id="readme-top"></a>

<!-- Project Shields -->
<div align="center"><nobr>

[![dotgibson][dotgibson-shield]][dotgibson-url]<!--
-->[![CI][ci-shield]][ci-url]<!--
-->![Last Commit][lastcommit-shield]<!--
-->[![Contributors][contributors-shield]][contributors-url]<!--
-->[![Forks][forks-shield]][forks-url]<!--
-->[![Stargazers][stars-shield]][stars-url]<!--
-->[![Issues][issues-shield]][issues-url]<!--
-->[![MIT License][license-shield]][license-url]

</nobr></div>

# dotfiles-NixOS

The NixOS machine repo. Vendors [Core](https://github.com/dotgibson/dotfiles-core) under
`core/` and adds the NixOS-native layer — with one thing no other repo in this fleet has:
a **second owner**.

[![dotfiles-NixOS — terminal demo](assets/demo.gif)](https://dotgibson.github.io/dotfiles-web)

## Built with

- [![NixOS][nixos-shield]][nixos-url]
- [![Nix][nix-shield]][nix-url]
- [![home-manager][home-manager-shield]][home-manager-url]

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

<!-- Markdown Links & Images -->
[dotgibson-shield]: https://img.shields.io/github/v/release/dotgibson/dotfiles-core?style=plastic&label=dotgibson&labelColor=181717&logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAF1klEQVR4nLSWbUxT7RnHr9PT09MXSltaoC9QXkqR16Iwhb0Iw8VYYE7jPri5aBaZzpmFZbpolpn4QeMyM%2BM%2B7MVt0Q9LNJIlxCzqxGWS6aKAig51vBQKIi3QltpCS0%2Fbc879pD1N3%2Bnz4fG5Pl2977v%2F331d131f5%2BZrddWQZAgAgy9uCRlefICzT6GeIsP%2FXF15kahmu9JglGmLRQoRQdIQWgu77BuWGe%2Fo%2BOqym8odApaWomTT1%2Bl2HqirahaTuJ9kQMggkgYhDRGfRiQDZBi9fuf52%2BD7l1b3ZhRcmq%2FMnBHmibuO7fvWoTalVoDjQRwL8RGgEOtzB0MbtBDnkRjGR0AgTK%2BQfNukr1LKXlhXKZpJSxTKGoFSq9vf16tQ8%2FiEh094Vu0L449mLGMup20DRWuFYVCiFm%2BvU36nTbOlMB%2BnCDxIOBzhvv6nFpc3TS0dUKDRHzh1Jk9O8wlPYN326Oa%2FJobnN8shAOxqKjrdXa8WSnGKWPewR%2FuHLG5P8oKUFJHi%2FH19F6UKEQ%2BnbJap27%2B%2BtWR15VAHgLkV%2F%2F0xW6OuQCfNE4PgmyX6f0xZKYbJDuj43lmtoYqHU%2FaZdwNXr4eoUG51zqgw%2B%2FCtrbm0UCeRynBhqVj2YC4RNC%2FuqStbKkydAODzeO7%2B6QYTpnOIYgB729R729RY9DAGafb0wDOHLwAA5vKK1mJNFoCpsxeLLn%2Fy91uU359719%2FfVXL%2BSM35IzU9rcXciCcQujz0imOfbGhOB0jkGo2hFQBW7Quzr0Zzq6vyBT%2FuKY%2BHErfBmQWLK1Lhr6l1OkleCqC0poPb%2FuTwv3OrA8DPDhgkokgLmLX77o86kqcGJmaj5xjr1JWlAAr1Js75MDEGAAI%2B1mvWX%2F1JY29XmYDPS5ZoNsrM24si1xSh3%2FRbGBYlz%2F73g41ztqliqYv1onyVHgDocMjjXASAKycavlqnZBHa2ajcasjv%2B8MbAPhRV9nI5MezB41crIPPHWOW9Gtl9XhDDCMCokIqSwGQ4shvyucFhEQCnqlSdm9k%2BdKt6XM%2FqO7aof7t8YbIIW5SHdpVIhUTAOAP0L8bmM3MHgJwByidQCgnhSmAqOEYnQ8AgRBr%2FuUzKsgggIs3pyVCfkeTCgAmFtaNOgm39C%2F3511r2W8JYvIAJbIaAwQ3vKAEoVgRaTQIBYKxqxgMs6euvdUXiQDgeHd5rV7K1fb2kC2rOgaYghQBMJ5grI3HUGuuhQiNIOWq8sy%2FLTgCKplgT0ZtCyprWw7%2FvKCyNr6yQqYg8cim59a9KQDnwv84R1%2F99UwAzsMya4vxeOYLN7YePGG%2BcAPjxXS%2BoavknFfOlRTAh8nHKNqLa1v2ZwK6dxQZtHk5ahu3%2FcYmLsoh%2B%2FsUgN%2BztDQzEvkYFBurGnan%2FS1%2B1P98L1FbxLIPzh193X%2FtwbmjiGUBYHd5nVFRCABPlxdtfh%2B3LHGKxof%2Bqo90C6yj58yi9Tm1kWjr94ZXsGhTuDuynAx2z0245yY4X06Kf9HWFd0N%2BuPbsUR64%2B3a57Erig2qIoOIlJSUNE69GWTZRFufXvRNL%2Fo2ywyJE1fMP6xWqHBEP5yfvP7%2FbAAAsFufG01mkVCqkGvLyrbNTD2mw9kfDckmE0oudx9rUZfhiF5Zd%2F%2F00QDF0NkBTJhanB3e0riHJIRKhXarqWfdu%2Bx0WnOot1ftuNR90lhQzEO0L7B2YvCm3b%2BWNI%2ByffSLq757%2BPcquYaIvBtgdcXycuzO9MzTFdccd9IwDNMVlDaXbzPXtxsVhQRDEQzl8i6d%2Buf12Y%2BONDVMo6vOfHWJxHLz3l811u8WAEZABCNAAHSI8n8k2HABKRJjLJ8JECxFMAE%2BHXhiGb7yn35vcCNDKVsEcSuv%2BEpn%2B7Etla0CwAQIOBLBhrkt85kAnwm8mX95e%2FTOa9vUZiIxQI43r0Kura9uN5SYNMoyuVDGZ2nK73C65iy28Rezo44152bSKYAvz3ifVA1lDn0WAAD%2F%2F%2FWvXexgMwqgAAAAAElFTkSuQmCC
[dotgibson-url]: https://github.com/dotgibson/dotfiles-core/releases/latest
[ci-shield]: https://img.shields.io/github/check-runs/dotgibson/dotfiles-NixOS/main?style=plastic&logo=githubactions&logoColor=white&label=CI
[ci-url]: https://github.com/dotgibson/dotfiles-NixOS/actions/workflows/lint.yml
[lastcommit-shield]: https://img.shields.io/github/last-commit/dotgibson/dotfiles-NixOS?branch=main&style=plastic&logo=git&logoColor=white
[contributors-shield]: https://img.shields.io/github/contributors/dotgibson/dotfiles-NixOS.svg?style=plastic&logo=github
[contributors-url]: https://github.com/dotgibson/dotfiles-NixOS/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/dotgibson/dotfiles-NixOS.svg?style=plastic&logo=github
[forks-url]: https://github.com/dotgibson/dotfiles-NixOS/network/members
[stars-shield]: https://img.shields.io/github/stars/dotgibson/dotfiles-NixOS.svg?style=plastic&logo=github
[stars-url]: https://github.com/dotgibson/dotfiles-NixOS/stargazers
[issues-shield]: https://img.shields.io/github/issues/dotgibson/dotfiles-NixOS?style=plastic&logo=github
[issues-url]: https://github.com/dotgibson/dotfiles-NixOS/issues
[license-shield]: https://img.shields.io/github/license/dotgibson/dotfiles-NixOS.svg?style=plastic
[license-url]: https://github.com/dotgibson/dotfiles-NixOS/blob/main/LICENSE
[nixos-shield]: https://img.shields.io/badge/NixOS-5277C3?style=plastic&logo=nixos&logoColor=white
[nixos-url]: https://nixos.org
[nix-shield]: https://img.shields.io/github/v/tag/NixOS/nix?sort=semver&style=plastic&logo=nixos&logoColor=white&label=Nix&labelColor=5277C3&color=3D59A1
[nix-url]: https://github.com/NixOS/nix
[home-manager-shield]: https://img.shields.io/badge/home--manager-BB9AF7?style=plastic&logo=gnometerminal&logoColor=24283B
[home-manager-url]: https://github.com/nix-community/home-manager
