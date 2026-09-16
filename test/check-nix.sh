#!/usr/bin/env bash
# test/check-nix.sh — do the nix/ modules parse?
#
# WHY THIS EXISTS. `.nix` is the one file class in this repo that NOTHING else looks at.
# Core's reusable lint gate covers *.sh (shellcheck + bash -n), *.zsh (zsh -n), *.md
# (markdownlint) and the workflows (actionlint). A syntax error in nix/home.nix would ship
# green through every gate the fleet has and only surface on someone's `home-manager
# switch` — which, because of the boundary this repo documents, is the step they run
# BEFORE ./bootstrap.sh and therefore before anything else could warn them.
#
# WHAT IT DOES NOT DO: evaluate. `nix-instantiate --parse` is pure syntax — no channels,
# no network, no nixpkgs, no attribute resolution. So a typo'd package name in
# home.packages still passes here; that needs a real `home-manager build` against a
# channel, which is a container/VM job and is documented in nix/README.md rather than
# wired into `make test`. The distinction matters: this gate says "the file is Nix", not
# "the file is correct".
#
# SKIPS LOUDLY without nix, which is the fleet's Makefile idiom for every optional leg —
# and here it is the NORMAL case: nix is on neither a WSL dev box nor ubuntu-latest.
# .github/workflows/test.yml runs this a second time in a nixos/nix container, which is
# where the parse actually happens.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v nix-instantiate >/dev/null 2>&1; then
  echo "check-nix: nix-instantiate not installed — skipped (the nix-parse CI job runs it)"
  exit 0
fi

# A glob that matched nothing would make `nix-instantiate` read stdin and hang, and an
# empty nix/ is a broken repo rather than a passing one — the same vacuous-green shape
# the fleet's other gates refuse.
shopt -s nullglob
files=(nix/*.nix)
shopt -u nullglob
if ((${#files[@]} == 0)); then
  echo "check-nix: no nix/*.nix found — this repo's declarative half is missing" >&2
  exit 1
fi

rc=0
for f in "${files[@]}"; do
  if out="$(nix-instantiate --parse "$f" 2>&1 >/dev/null)"; then
    echo "ok   $f parses"
  else
    echo "FAIL $f does not parse" >&2
    printf '%s\n' "$out" >&2
    rc=1
  fi
done

((rc == 0)) && echo "check-nix: ${#files[@]} file(s) parse"
exit "$rc"
