#!/usr/bin/env bash
# bootstrap.sh — wire the vendored Core + the NixOS os/ layer into place. Idempotent.
#
# SHAPE: this file DECLARES what it is and DEFINES the hooks that are NixOS's, then hands
# over to Core's bootstrap driver, blib_main (core/lib/bootstrap-lib.sh, dotfiles-core#976):
# the flag loop, the escalator, the sudo keepalive, the Core symlink surface + the os/
# overlays, the managed ~/.zshrc loader and the closing report run from that ONE definition.
#
# THE BOUNDARY, and it is why this bootstrap is shorter than every sibling's.
# On NixOS the packages, PATH, tpm and the login-shell declaration belong to nix/ —
# nix/nixos.nix (system) and nix/home.nix (home-manager). THIS SCRIPT OWNS EVERY LINK AND
# THE ZSH ENTRY, and installs nothing. That split is measured, not chosen: the driver
# relinks whatever home-manager links (a differing symlink is a relink, not a foreign
# file — no backup), and home-manager TOLERATES that, because its collision check compares
# content — except at $ZDOTDIR/.zshrc, where the bytes differ and `-b` cannot back up a
# foreign SYMLINK. One file, and home-manager refuses to activate at all. So a home has one
# link owner, and it is this script. See nix/README.md and
# core/NON-MUTABLE-HOST-PROPOSAL.md §5 R3 (dotgibson/dotfiles-core#1004).
#
# There is therefore NO bootstrap_provision() hook here, and there should not be one:
# `nix-env -i` into the user profile is the state a `nixos-rebuild switch` will not
# reproduce. Declare the package in nix/home.nix instead.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"

# ── what this bootstrap IS (read by blib_main) ────────────────────────────────
# shellcheck disable=SC2034  # read by the vendored driver, which shellcheck cannot see
BOOTSTRAP_NAME="NixOS"
# shellcheck disable=SC2034
BOOTSTRAP_OS=nixos
# OFF, permanently, and NOT because this repo is a starter.
#
# `chsh -s zsh` TAKES on NixOS (users.mutableUsers defaults to true — measured, R1). It is
# still the wrong tool: a hand-set login shell is precisely the state `nixos-rebuild switch`
# does not reproduce, so the box would drift back on the next rebuild with nothing to say
# why. bootstrap_closing() below PRINTS the declaration instead.
#
# Second consequence, and it is the good one: with this off AND no bootstrap_provision()
# hook, blib_main never resolves an escalator at all (core/lib/bootstrap-lib.sh — the
# best-effort branch needs one of the two). A declarative host therefore never sees a sudo
# prompt or a "no privilege escalator found" line. That is the shape
# core/NON-MUTABLE-HOST-PROPOSAL.md §4.7(1) asks for, reached by declaration rather than by
# BOOTSTRAP_SU=lazy.
# shellcheck disable=SC2034
BOOTSTRAP_LOGIN_SHELL=0

# ── the host probe: report-only, never a guard ───────────────────────────────
# Runs on a full run; blib_main skips it under --links-only. It REPORTS and never exits.
#
# There is deliberately NO bootstrap_guard(). A guard keyed on NixOS would red this
# repo's own CI: the bootstrap-test leg runs in the `nixos/nix` container, which is a nix
# INSTALL on another distro, not NixOS — no /etc/NIXOS, no nixos-rebuild. R6 measured the
# starter running clean there precisely because it has no guard, and the wiring this
# script does is correct on any box with nix on it. So this says what it sees and lets
# the run continue. Do not "harden" it into a guard.
# shellcheck disable=SC2329  # called by the vendored driver
bootstrap_check() {
  # The HOST MARKER, never an os-release ID — the fleet's rule for every variant probe
  # (core/NON-MUTABLE-HOST-PROPOSAL.md §4.3). /etc/NIXOS is what NixOS itself writes.
  if [[ -e /etc/NIXOS ]]; then
    blib_ok "NixOS host (/etc/NIXOS)"
  else
    blib_say "not a NixOS host — wiring anyway; nix/nixos.nix is the half that needs one"
  fi
  if command -v nix >/dev/null 2>&1; then
    blib_ok "nix $(nix --version 2>/dev/null | awk '{print $NF}')"
  else
    blib_warn "nix is not on PATH — nix/home.nix cannot be applied until it is"
  fi
  if command -v home-manager >/dev/null 2>&1; then
    blib_ok "home-manager is available"
  else
    blib_say "home-manager not on PATH — see nix/README.md (the NixOS module needs no CLI)"
  fi
  # WHERE THE PACKAGE SET LANDS depends on how nix/home.nix was applied, and NixOS puts
  # every one of these on PATH, so the probe has to know all three (#9):
  #   ~/.nix-profile                  standalone home-manager, or the NixOS module without
  #                                   home-manager.useUserPackages
  #   $XDG_STATE_HOME/nix/profile     the same, on a box with nix.settings.use-xdg-base-directories
  #   /etc/profiles/per-user/$USER    the NixOS module with useUserPackages = true — the
  #                                   layout where ~/.nix-profile never exists at all, which
  #                                   is what this probe used to look for. Measured on a
  #                                   NixOS-WSL 26.05 host installed per nix/README.md.
  # Independently of the layout, home-manager leaves a gcroot at
  # $XDG_STATE_HOME/home-manager/gcroots/current-home on every activation, module or
  # standalone — the one marker that says "nix/home.nix has been applied" regardless of
  # where its packages went.
  local _state="${XDG_STATE_HOME:-$HOME/.local/state}" _p _profile=""
  for _p in "$HOME/.nix-profile" "$_state/nix/profile" "/etc/profiles/per-user/${USER:-$(id -un)}"; do
    if [[ -d "$_p/bin" ]]; then
      _profile="$_p"
      break
    fi
  done
  if [[ -n "$_profile" ]]; then
    blib_ok "nix user profile: ${_profile/#"$HOME"/\~}"
  else
    blib_say "no nix user profile yet (~/.nix-profile, ~/.local/state/nix/profile or /etc/profiles/per-user/${USER:-$(id -un)}) — apply nix/home.nix to get the package set"
  fi
  if [[ -e "$_state/home-manager/gcroots/current-home" ]]; then
    blib_ok "home-manager generation active (nix/home.nix has been applied)"
  fi
}

# ── the login shell: DECLARED, never chsh'd ──────────────────────────────────
# This is the arm core/NON-MUTABLE-HOST-PROPOSAL.md §4.3 assigns to this repo rather than
# to the lib, and it lives in bootstrap_closing() on purpose.
#
# It is ADVICE, not a substitution. dotfiles-Gentoo announces its handoff from
# wire_pre_loader because it actually PERFORMS one (an append to ~/.bash_profile); this
# script performs nothing — it hands the operator two lines for a file this repo does not
# own. "Say what only this repo knows, at the end" is bootstrap_closing's contract, and it
# is where dotfiles-Offense and dotfiles-Defense put the same class of message.
#
# It is also correct in all three modes for free: the driver calls bootstrap_closing
# unconditionally, so --dry-run and --links-only print the SAME sentence as a full run,
# with nothing faked and no "would print" weasel.
_nixos_login_user() {
  local u
  u="$(id -un 2>/dev/null || true)"
  [[ -n "$u" ]] && { printf '%s\n' "$u"; return 0; }
  printf '%s\n' "${USER:-<you>}"
}

# The same descending-trust lookup the lib uses: getent, then /etc/passwd with the user
# as awk DATA (never interpolated into a pattern), then $SHELL.
_nixos_login_shell() {
  local u="$1" f=""
  command -v getent >/dev/null 2>&1 && f="$(getent passwd "$u" 2>/dev/null | cut -d: -f7 || true)"
  [[ -z "$f" && -r /etc/passwd ]] && f="$(awk -F: -v u="$u" '$1 == u { print $7; exit }' /etc/passwd 2>/dev/null || true)"
  printf '%s\n' "${f:-${SHELL:-}}"
}

# shellcheck disable=SC2329  # called by the vendored driver
bootstrap_closing() {
  local user shell_now
  user="$(_nixos_login_user)"
  shell_now="$(_nixos_login_shell "$user")"

  # zsh ABSENT → everything above is wired but inert. Core owns that wording and the
  # return-1 contract (the driver then declines to call the run complete), so reuse it —
  # but say WHERE the fix is declared first, because blib_login_shell_hint's own remedy
  # is `chsh`, which is the wrong verb here.
  if ! command -v zsh >/dev/null 2>&1; then
    blib_warn "zsh is not installed — declare it, then re-run:"
    blib_warn "    nix/home.nix     home.packages = [ pkgs.zsh ];"
    blib_warn "    nix/nixos.nix    programs.zsh.enable = true;"
    blib_login_shell_hint
    return
  fi

  # Already zsh → one line, idempotent. A re-run after the declaration landed must not
  # print the block again.
  if [[ "$shell_now" == *zsh ]]; then
    blib_ok "login shell is already zsh — keep it declared in nix/nixos.nix so a rebuild reproduces it"
    return 0
  fi

  # The arm itself. Never chsh, never /etc/shells, never an escalator.
  blib_say "login shell is ${shell_now:-unknown} — DECLARE zsh rather than running chsh:"
  printf '\n'
  printf '    # nix/nixos.nix (the system-side fragment)\n'
  printf '    users.users.%s.shell = pkgs.zsh;\n' "$user"
  printf '    programs.zsh.enable = true;\n'
  printf '\n'
  printf '    $ sudo nixos-rebuild switch\n'
  printf '\n'
  blib_say "chsh would work here (users.mutableUsers defaults to true) and is still wrong:"
  blib_say "  a hand-set shell is exactly what the next rebuild does not reproduce."
  # shellcheck disable=SC2034  # read by the driver for its closing line
  BLIB_NEXT_HINT="for this session: exec zsh"
  return 0
}

# The NixOS half of --help; the driver prints the shared flags after it. bootstrap_usage()
# is the ONE place a repo flag is documented — never a line range of this header, which
# drifts the moment a line is added above it. Add a flag: name it here, take it in
# bootstrap_flag() (see the driver's contract in core/lib/bootstrap-lib.sh).
# shellcheck disable=SC2329  # called by the vendored driver
bootstrap_usage() {
  cat <<'USAGE'
usage: bootstrap.sh [flags]

Wire the vendored Core + the NixOS os/ layer into place. Idempotent; safe to re-run
after every Core sync.

This script INSTALLS NOTHING. On NixOS the packages, PATH, tpm and the login-shell
declaration live in nix/ (nix/nixos.nix and nix/home.nix); this script owns every
symlink and the zsh entry, and prints the login-shell declaration rather than running
chsh. See nix/README.md for the boundary and why it is not negotiable.

The shared flags below are the driver's.
USAGE
}

# ── after the managed ~/.zshrc, before the login shell ────────────────────────
# The ZDOTDIR entry pair. ~/.zshenv points ZDOTDIR at ~/.config/zsh, where the driver
# has just seeded .zshrc as a symlink to the managed ~/.zshrc loader; .zprofile is this
# repo's login-time hook. Both .zsh sources, extensionless destinations (#451).
# shellcheck disable=SC2329
bootstrap_wire_post_loader() {
  blib_link "$DOTFILES/zsh/zshenv.zsh" "$HOME/.zshenv"
  blib_link "$DOTFILES/zsh/zprofile.zsh" "$CONFIG/zsh/.zprofile"
}

# ── vendored core/ present? (inline: can't source a lib out of core/ before this) ─
[[ -d "$DOTFILES/core" ]] || { echo "core/ subtree missing — run the subtree add first (VENDORING.md, one-time setup)" >&2; exit 1; }
for _req in core/zsh/loader.zsh core/lib/ux.sh core/lib/bootstrap-lib.sh; do
  [[ -e "$DOTFILES/$_req" ]] || { echo "vendored core/ missing or incomplete (need $_req) — run make sync in dotfiles-core" >&2; exit 1; }
done
unset _req
# shellcheck source=core/lib/ux.sh
source "$DOTFILES/core/lib/ux.sh"
# shellcheck source=core/lib/bootstrap-lib.sh
source "$DOTFILES/core/lib/bootstrap-lib.sh"

blib_main "$@"
