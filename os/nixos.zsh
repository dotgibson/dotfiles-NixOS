# os/nixos.zsh — the NixOS interactive layer (symlinked to $ZDOTDIR/80-os.zsh by bootstrap;
# band 80 = OS-native, the range reserved for this repo's own fragment).
# Put OS-specific aliases, PATH, and package-manager bits HERE — never in Core.
# It may use any Core helper (00-tools.zsh's _cache_eval and _core_is_wsl, 05-ui.zsh's
# _core_* primitives).
#
# Core ALREADY hooks direnv/gh/uv/ty and already answers "is this WSL?" (_core_is_wsl) —
# do not re-add either here. Seven os layers each carried a copy until dotfiles-core#449,
# and the reusable lint workflow now flags a duplicate. See VENDORING.md.

[[ $- == *i* ]] || return 0

# ── PATH ──────────────────────────────────────────────────────────────────────
# The first two are the fleet's, byte-identical to every sibling. The nix profile
# directories matter on a STANDALONE-nix box (Fedora, macOS, a container): on NixOS
# proper they are already in the system profile and these are no-ops. Guarded both
# ways, so this layer is correct in both places — which is the point, because
# nix/home.nix is importable on a non-NixOS host too.
[[ -d "$HOME/.local/bin" && ":$PATH:" != *":$HOME/.local/bin:"* ]] && export PATH="$HOME/.local/bin${PATH:+:$PATH}"
[[ -d "$HOME/.cargo/bin" && ":$PATH:" != *":$HOME/.cargo/bin:"* ]] && export PATH="$HOME/.cargo/bin${PATH:+:$PATH}"
[[ -d "$HOME/.nix-profile/bin" && ":$PATH:" != *":$HOME/.nix-profile/bin:"* ]] && export PATH="$HOME/.nix-profile/bin${PATH:+:$PATH}"
[[ -d /nix/var/nix/profiles/default/bin && ":$PATH:" != *":/nix/var/nix/profiles/default/bin:"* ]] && export PATH="/nix/var/nix/profiles/default/bin${PATH:+:$PATH}"

# ── Clipboard: delegate to Core's cross-OS scripts ────────────────────────────
# Nothing NixOS-specific here — the backend is wl-copy/xclip like every Linux sibling,
# and nix/home.nix installs both. On a headless box there may be no backend at all,
# which is expected.
command -v clip       >/dev/null && alias pbcopy='clip'
command -v clip-paste >/dev/null && alias pbpaste='clip-paste'

# ── conveniences ──────────────────────────────────────────────────────────────
# dotsync resolves THIS FILE's own path rather than hard-coding a clone location:
# %N is the file as it was sourced, :A resolves it through bootstrap's symlink to the
# real file, and two :h strip /os/nixos.zsh back to the repo root. Gentoo's form
# (dotfiles-Gentoo#…), and it matters more here than anywhere: a NixOS user is as
# likely to keep this beside their configuration.nix as in ~.
_nixos_repo="${${(%):-%N}:A:h:h}"
if [[ -d "$_nixos_repo/os" && -f "$_nixos_repo/bootstrap.sh" ]]; then
  alias dotsync="cd ${(q)_nixos_repo}"
else
  alias dotsync='cd "$HOME/dotfiles-NixOS"'   # fallback: the documented clone path
fi
unset _nixos_repo
command -v op >/dev/null 2>&1 && alias opsignin='eval "$(op signin)"'
alias localip='ip -brief -4 addr show scope global'

# ── nixos-rebuild ─────────────────────────────────────────────────────────────
# `switch` activates and makes the generation the boot default; `test` activates
# WITHOUT touching the bootloader (so a bad config is undone by a reboot) and `boot`
# does the reverse. `test` is the verb with no analogue anywhere else in the fleet and
# is the best reason this section exists — it is how you try a change you do not trust.
alias nrs='sudo nixos-rebuild switch'
alias nrt='sudo nixos-rebuild test'
alias nrb='sudo nixos-rebuild boot'
# Kept BYTE-IDENTICAL to os/nixos.capabilities' PKG_UPGRADE, so `up` and the alias can
# never drift into meaning two different things.
alias nru='sudo nixos-rebuild switch --upgrade'
# Generations are this host's `dnf history`; `nixos-rebuild switch --rollback` is the
# undo and is already short enough not to need one.
alias nrgen='nixos-rebuild list-generations'

# ── nix ───────────────────────────────────────────────────────────────────────
# Byte-identical to PKG_SEARCH. The --extra-experimental-features is load-bearing on a
# box that never enabled flakes, and is part of the verb rather than a prerequisite.
alias nxs='nix --extra-experimental-features nix-command search nixpkgs'
# PKG_OWNS. Guarded because it needs the nix-index database built once (`nix-index`);
# nix/home.nix installs the package, but the database is per-user state.
command -v nix-locate >/dev/null 2>&1 && alias nxw='nix-locate --top-level'
# The real NixOS answer to Fedora's `dnfi`: "I need this tool for five minutes." It is
# what you reach for INSTEAD of installing, which is why it earns a short alias and
# nix-env does not.
alias nxsh='nix-shell -p'
# The one maintenance verb with no fleet analogue: /nix/store only ever grows until
# this runs. Both scopes, because they collect different things.
alias nxg='sudo nix-collect-garbage -d'
alias nxgu='nix-collect-garbage -d'

# DELIBERATELY NOT ALIASED: nix-env -i / nix-env -e.
# os/nixos.capabilities declares them because the schema needs a true imperative verb
# and they ARE one (per-user, and they survive `nixos-rebuild switch`). But they are the
# documented anti-pattern — a user-profile generation is exactly the state a rebuild
# will not reproduce. Declaring them is honesty; putting them two keystrokes away would
# be promotion. Install by declaring it in nix/home.nix, or reach for `nxsh`.

# ── WSL-only niceties ─────────────────────────────────────────────────────────
# NixOS-WSL is a real target. WSL detection is Core's (_core_is_wsl in
# core/zsh/00-tools.zsh, dotfiles-core#449) — the lint gate fails an OS layer that grows
# its own back. The function guard keeps this quiet if the layer is ever sourced without
# Core's 00-tools.zsh; it is NOT a local fallback.
if (( $+functions[_core_is_wsl] )) && _core_is_wsl; then
  alias open='explorer.exe'
  command -v wslview >/dev/null && alias xdg-open='wslview'
  [[ -n "${WINHOME:-}" ]] && alias cdwin='cd "$WINHOME"'
fi

# ── auto-start/attach tmux for interactive terminals ─────────────────────────
# Skip inside an existing tmux, VS Code's integrated terminal, and non-TTYs.
#
# Escape hatch: export DOTFILES_NO_AUTOTMUX=1 to disable entirely. Every OS layer in the
# fleet must honour this knob — core/scripts/gen-hero-tape.sh REFUSES to render a repo's
# hero whose layer auto-attaches without it, because the tape exports it before sourcing
# the zshrc.
#
# Set it in ~/.zshenv, or in the environment for a single session. NOT in
# ~/.config/zsh/99-local.zsh: the loader sources fragments in NN order, so this file
# (band 80) has already run by the time band 99 is read — the flag would be set too
# late to suppress anything.
if [[ -z "${DOTFILES_NO_AUTOTMUX:-}" ]] \
   && command -v tmux >/dev/null 2>&1 \
   && [[ -z "${TMUX:-}" && -t 1 && "${TERM_PROGRAM:-}" != "vscode" ]]; then
  tmux attach -t main 2>/dev/null || tmux new-session -s main
fi
