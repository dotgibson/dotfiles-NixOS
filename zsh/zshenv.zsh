# zsh/zshenv.zsh → ~/.zshenv. Point ZDOTDIR at ~/.config/zsh so the rest of the shell
# config lives under XDG. Keep this file tiny — it runs for EVERY zsh (incl. scripts).
#
# Do NOT rename this to plain `zshenv` to match the symlink: the .zsh suffix is what
# puts it in front of the lint gate's `git ls-files '*.zsh'` (#451).
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
