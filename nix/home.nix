# nix/home.nix — the home-manager half of dotfiles-NixOS.
#
# ┌──────────────────────────────────────────────────────────────────────────────┐
# │ THIS FILE DECLARES NO FILES. No home.file, no programs.zsh, and exactly ONE   │
# │ xdg.configFile (tpm, below, with the mechanism written out). That is not a    │
# │ style preference — it is the only arrangement that works, and it was measured.│
# └──────────────────────────────────────────────────────────────────────────────┘
#
# WHY (core/NON-MUTABLE-HOST-PROPOSAL.md §5 R3, dotgibson/dotfiles-core#1004, measured on a
# booted NixOS 25.05 guest and on a mutable host):
#
#   · The driver WINS every collision, silently. home-manager links a home path at a
#     symlink in the store which points at the checkout — two hops. blib_link sees a
#     symlink whose target is not the checkout, calls it wrong, and replaces it. A
#     differing symlink is a RELINK, not a foreign file, so there is no backup and no
#     warning. Measured: 25 of 28 home-manager links relinked on the first driver run.
#
#   · home-manager TOLERATES that — right up until it cannot. Its collision check
#     compares CONTENT (`cmp -s`), and a direct link into the checkout has the same bytes
#     as its own two-hop one, so for 27 of 28 paths it printed "in the way … will be
#     skipped since they are the same" and carried on. The 28th was $ZDOTDIR/.zshrc: the
#     driver's is the v4 loader, home-manager's is its own initContent, DIFFERENT BYTES —
#     and `-b` does not help, because home-manager backs up only a REGULAR foreign file,
#     never a foreign symlink (`[[ ! -L "$targetPath" && -n "$HOME_MANAGER_BACKUP_EXT" ]]`,
#     modules/files/check-link-targets.sh, release-25.05). Exit 1 at checkLinkTargets,
#     before a single link is touched.
#
# So a home cannot have two link owners, and the whole fight is over ONE file: the zsh
# entry. Turn programs.zsh on here and this home becomes one home-manager can no longer
# activate at all until that link is removed — and the driver's next run would put it back.
#
# THE SPLIT, therefore:  nix/ owns packages, PATH, tpm and the login-shell declaration.
#                        bootstrap.sh owns every link and the zsh entry.
# Both run. Neither fights. home-manager's own collision check is what keeps it stable.
{ config, pkgs, lib, ... }:

{
  home.stateVersion = "25.05";

  # Standalone home-manager REPLACES the user profile on its first `switch`, and the
  # `home-manager` binary the installer put there goes with it unless this module carries
  # it (measured — the second switch was "home-manager: command not found"). Redundant
  # under the NixOS module, load-bearing standalone, and this file is meant to work both
  # ways. See nix/README.md.
  programs.home-manager.enable = true;

  # STANDALONE USERS: uncomment and set these two. The NixOS module sets both for you, so
  # they are commented rather than defaulted — a wrong default here is worse than an
  # explicit edit, and `lib.mkDefault` still needs a value to hand you.
  # home.username = "you";
  # home.homeDirectory = "/home/you";

  # ── packages ────────────────────────────────────────────────────────────────
  # This is the half of the boundary that replaces install/packages.txt: there is no such
  # file in this repo, and `make packages-check` is a stub by design. The set mirrors
  # dotfiles-Fedora's 38 names, translated to nixpkgs attributes.
  #
  # Notes where the attribute is NOT the obvious name:
  #   yq-go      — mikefarah's Go yq, which is what Core's aliases expect. Plain `yq` in
  #                nixpkgs is kislyuk's Python one. Same split core/PORTING-MATRIX.md
  #                footnotes for every other archive.
  #   du-dust    — installs the `dust` binary.
  #   git-delta  — installs `delta`.
  #   fd         — nixpkgs calls it `fd` (Fedora's is `fd-find`).
  #   nix-index  — NOT cosmetic. os/nixos.capabilities declares
  #                PKG_OWNS=nix-locate --top-level, and nix-locate ships here. Without
  #                this line that declaration is a promise the box cannot keep.
  #
  # Deliberately absent from Fedora's list: `flatpak` (a system service, not a home
  # package — declare it in configuration.nix if you want it) and `git-subtree` (a
  # separate RPM on Fedora; it is inside nixpkgs' `git`).
  home.packages = with pkgs; [
    # shell + multiplexer + editor
    zsh tmux neovim
    # the prompt and history
    starship atuin
    # the modern-CLI core
    eza bat fd ripgrep zoxide fzf git-delta btop tealdeer duf procs du-dust
    jq yq-go glow gum
    # vcs
    git jujutsu lazygit
    # session + files + runtimes
    sesh yazi mise direnv carapace
    # build toolchain (tree-sitter parsers compile locally; some ship C++ scanners)
    gcc gnumake cargo tree-sitter
    # providers and net/misc
    python3Packages.pynvim curl wget w3m htop gawk openssh
    # clipboard: Core's clip/clip-paste drive these
    wl-clipboard xclip
    # PKG_OWNS' database — see the note above
    nix-index
  ];

  # ── PATH ────────────────────────────────────────────────────────────────────
  # Three owners of the same two directories, each for a different process, which is
  # fine and is why it is written down: this for login sessions, os/nixos.zsh for
  # interactive shells, and blib_user_bindirs_on_path for bootstrap time.
  home.sessionPath = [
    "${config.home.homeDirectory}/.local/bin"
    "${config.home.homeDirectory}/.cargo/bin"
  ];

  # ── tpm: the ONE xdg.configFile, and the mechanism that makes it safe ───────
  # Everything else the driver links is contested. tpm is not, and the reason is exact:
  # blib_link_core does NOT blib_link tpm. It is a PRESENCE GUARD —
  #
  #     if [[ ! -d "$config/tmux/plugins/tpm" ]]; then ... git clone --depth=1 ...
  #
  # (core/lib/bootstrap-lib.sh) — and `[[ -d ]]` FOLLOWS SYMLINKS. So a home-manager-owned
  # tpm makes the driver skip its clone entirely, in every mode, and there is nothing to
  # relink. Verified end to end: a pre-existing ~/.config/tmux/plugins/tpm survives a full
  # --links-only run untouched.
  #
  # And it is strictly better than what the driver would have done: a rev-locked fetch
  # instead of an unpinned `--depth=1` clone of master. nixpkgs 25.05 carries no
  # tmuxPlugins.tpm (measured), so this is a fetchGit rather than a package.
  #
  # Delete this block and the driver's clone takes over on the next run. Nothing breaks
  # either way — which is the property that makes it the one safe exception.
  xdg.configFile."tmux/plugins/tpm".source = builtins.fetchGit {
    url = "https://github.com/tmux-plugins/tpm";
    ref = "refs/tags/v3.1.0";
    rev = "7bdb7ca33c9cc6440a600202b50142f401b6fe21";
  };

  # ── what this file must NEVER grow ──────────────────────────────────────────
  # programs.zsh          — the deadlock above. bootstrap.sh owns ~/.zshrc and
  #                         $ZDOTDIR/.zshrc.
  # home.file / xdg.configFile for anything the driver links (the zsh fragments, nvim,
  #                         tmux.conf, starship.toml, gitconfig, lazygit, atuin, jj,
  #                         tealdeer) — the driver relinks them silently and you lose
  #                         the declaration with no error to read.
  # home.activation seeding from the checkout — on NixOS this module is evaluated and
  #                         activated at SYSTEM activation, before any clone exists. The
  #                         R3 probe's mise seed fired on Fedora and silently did not on
  #                         NixOS, for exactly this reason. Seeding is bootstrap.sh's.
}
