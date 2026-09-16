# Security Policy

`dotfiles-NixOS` ships **configuration plus one wiring script**, and the wiring script
is unusually inert for this fleet: it **installs nothing and never escalates**.

That is not a claim about intent, it is a property of the design. Packages, `PATH`, tpm
and the login-shell declaration belong to `nix/` — see [`nix/README.md`](nix/README.md).
`bootstrap.sh` therefore ships no `bootstrap_provision` hook and sets
`BOOTSTRAP_LOGIN_SHELL=0`, and with both of those absent Core's driver never resolves a
privilege escalator at all. No `sudo`, no package manager, no third-party repository, no
write outside `$HOME`. The login shell is **printed as a declaration for you to apply**,
never changed by this repo.

So the surface worth reporting on is narrower than a sibling OS repo's:

- **A tracked file that leaks a secret.** This repo is public (keys themselves are denied
  by `.gitignore`). A leaked token or private key here is public the moment it lands.
- **A path in `bootstrap.sh` that writes outside `$HOME`, escalates, or can be coerced
  into trusting untrusted input.** Any of those would contradict the paragraph above,
  which makes it a bug in the boundary and worth a report.
- **A `nix/` module that would take ownership of a path the driver links** — in
  particular anything adding `programs.zsh`, `home.file`, or an `xdg.configFile` beyond
  the documented tpm exception. That is a correctness trap rather than a classic
  vulnerability, but it silently breaks a user's ability to activate home-manager at all,
  so report it here.
- **A shell fragment in `os/nixos.zsh` that runs at shell-startup time** and can be
  influenced by the environment or the working directory.

The vendored `core/` tree is **not** in scope — it is a copy of
[`dotfiles-core`](https://github.com/dotgibson/dotfiles-core) and is overwritten on the
next sync. Report those upstream, where a fix can actually land.

## Reporting a vulnerability

**Please do not open a public issue for a security report.** Use GitHub's private
vulnerability reporting: the **Security** tab → **Report a vulnerability**. That keeps
details private until a fix is out.

Include, where you can:

- the file and line, and whether it runs at wiring time or shell-startup time,
- how it is reached (a `bootstrap.sh` flag, a sourced fragment, a home-manager
  activation), and
- a minimal reproduction.

You can expect an acknowledgement within a few days.

## Scope

In scope: `bootstrap.sh`, `nix/*`, `os/*`, `zsh/*`, `test/*`, and this repo's workflows.

Out of scope: anything under `core/` (report to `dotfiles-core`), nixpkgs and
home-manager themselves, and the upstream tools `nix/home.nix` declares — report those to
their own projects.
