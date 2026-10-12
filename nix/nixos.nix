# nix/nixos.nix — the SYSTEM-side fragment of dotfiles-NixOS.
#
# DELIBERATELY NOT NAMED configuration.nix. A file with that name invites being copied
# over yours, and yours carries the things only your machine knows: the
# hardware-configuration.nix import, the bootloader, the filesystems,
# system.stateVersion. This is a plain importable module instead — add it to your imports
# and keep your own configuration:
#
#     # /etc/nixos/configuration.nix
#     { ... }:
#     {
#       imports = [
#         ./hardware-configuration.nix
#         /home/you/dotfiles-NixOS/nix/nixos.nix
#       ];
#     }
#
#     $ sudo nixos-rebuild switch
#
# WHY THERE IS A SYSTEM HALF AT ALL. Almost everything this repo needs is per-user and
# belongs in nix/home.nix. Three things cannot be:
#   · programs.zsh.enable — this is what puts zsh in /etc/shells, and a shell that is not
#     in /etc/shells is not a shell a login can be set to.
#   · users.users.<name>.shell — the login-shell declaration itself. bootstrap.sh PRINTS
#     these two lines rather than running chsh; see its bootstrap_closing().
#   · programs.nix-ld.enable — the dynamic loader prebuilt binaries (mise's runtimes, the
#     Claude Code remote CLI) need. The loader at /lib64 is system state; see below.
#
# The boundary is in nix/README.md. Short version: nix/ owns packages, PATH, tpm, nix-ld
# and the login shell; bootstrap.sh owns every link and the zsh entry.
{ config, pkgs, lib, ... }:

let
  # Set this to your username and uncomment the users.users line below. It is a
  # placeholder rather than a live value because a WRONG username here is a rebuild
  # failure with a confusing message, and this repo cannot know yours.
  username = "you";
in
{
  # ── the login shell, half one: make zsh a valid one ─────────────────────────
  # Installs zsh system-wide and adds it to /etc/shells. Live, because it is safe on any
  # box and is the half that has no per-user alternative.
  programs.zsh.enable = true;

  # ── the login shell, half two: declare it ───────────────────────────────────
  # Uncomment after setting `username` above. This is what bootstrap.sh prints and what
  # makes the choice survive a rebuild — `chsh` takes on NixOS (users.mutableUsers
  # defaults to true) and is exactly the state a rebuild does not reproduce.
  # users.users.${username}.shell = pkgs.zsh;

  # ── the minimum needed BEFORE home-manager runs ─────────────────────────────
  # Everything else belongs in nix/home.nix. These two are here because you need them to
  # clone this repo and run ./bootstrap.sh in the first place, which is the step that
  # wires the config home-manager's package set then fills in.
  environment.systemPackages = with pkgs; [ git zsh ];

  # ── foreign binaries: nix-ld ────────────────────────────────────────────────
  # NixOS ships stub-ld at /lib64/ld-linux-x86-64.so.2, which refuses every prebuilt,
  # dynamically-linked binary. mise's runtimes, the Claude Code remote CLI and anything
  # else downloaded rather than built by Nix are exactly that. nix-ld replaces the stub
  # with a shim that resolves them against a Nix-provided library set. Live, because the
  # bootstrap depends on it and it is a system option with no per-user alternative.
  programs.nix-ld.enable = true;
  # The module's default library set covers the common cases (libstdc++, zlib, openssl,
  # curl, …). If a tool still reports a missing .so, ADD to it here:
  # programs.nix-ld.libraries = with pkgs; [ … ];

  # ── deliberately commented: the auto-upgrade ────────────────────────────────
  # This is why os/nixos.capabilities declares NO MAINT_UNATTENDED_UPGRADE. NixOS has a
  # first-class unattended upgrader and Core's maint runner must not run a second one
  # beside it — two upgraders racing on one box is worse than none. If you want
  # unattended upgrades, turn THIS on and leave the capability key absent.
  # system.autoUpgrade.enable = true;
  # system.autoUpgrade.allowReboot = false;

  # ── deliberately commented: flakes ──────────────────────────────────────────
  # os/nixos.capabilities' PKG_SEARCH carries `--extra-experimental-features nix-command`
  # precisely so this is NOT required — the declaration has to be true on a box that
  # never enabled it. Turn it on if you want it; nothing here depends on it.
  # nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
