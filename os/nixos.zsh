# os/nixos.zsh — the NixOS interactive layer (symlinked to $ZDOTDIR/80-os.zsh by bootstrap;
# band 80 = OS-native, the range reserved for this repo's own fragment).
# Put OS-specific aliases, PATH, and package-manager bits HERE — never in Core.
# It may use any Core helper (00-tools.zsh's _cache_eval and _core_is_wsl, 05-ui.zsh's
# _core_* primitives).
#
# Core ALREADY hooks direnv/gh/uv/ty and already answers "is this WSL?" (_core_is_wsl) —
# do not re-add either here. Seven os layers each carried a copy until dotfiles-core#449,
# and the reusable lint workflow now flags a duplicate. See VENDORING.md.
