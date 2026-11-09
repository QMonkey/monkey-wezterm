# monkey-wezterm

## Introduction

monkey-wezterm is a [WezTerm](https://wezterm.org/) terminal configuration built around the Sonokai color scheme and a minimalist tab line.

**Positioning:** a cross-platform GUI terminal — a Windows entry point into a WSL development workflow, and a consistent terminal on Linux/macOS.

## Features

- Sonokai color scheme with a minimalist, font-independent tab line
- Minimalist tab line via [tabline.wez](https://github.com/michaelbrusegard/tabline.wez) (mode / workspace / cwd / domain, no font dependency)
- Kitty keyboard protocol enabled
- Windows: automatic WSL domains in the launch menu, PowerShell entry, `wsl.exe --cd ~` as default shell
- Maximized on start, 90% background opacity
- Quick select, workspace-aware tabs, toast-notification driven config reload (`CTRL|SHIFT+R`) and plugin update (`CTRL|SHIFT+U`)

## Requirements

- WezTerm 20240127+ (for `config_builder`, the plugin API and the kitty keyboard protocol; the one-click installer builds a current WezTerm from source)
- A Rust toolchain (rustup) — only needed to build; the installer sets it up

## Installation

Pick one of the two ways below: a one-click script, or manual setup.

### Option 1: One-click install

Build WezTerm from source (distro packages lag far behind) and install monkey-wezterm automatically:

```bash
curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-wezterm/master/install.sh | bash 2>&1 | tee monkey-wezterm-install.log
```

> The one-liner needs `git` besides `curl` itself: the installer clones this repository into `~/Documents/monkey-wezterm` before it can install anything. If `git` is missing, the script stops with an error — install it with your system's package manager and re-run the same command.

What the script does, step by step:

1. Pre-authorize `sudo` once — the only password entry of the whole run — and install a **temporary** NOPASSWD sudoers drop-in for the invoking user, removed automatically on exit. `./get-deps` runs many sudo calls across a 10–30 minute cargo build, and WSL2 clock jumps invalidate tickets; NOPASSWD makes the run immune to both. If the drop-in cannot be installed, or is written but not parsed, the run falls back to the sudo timestamp: one re-authentication on a long run, and a privileged step that cannot prompt fails and is reported instead.
2. Set up the build environment: rustup (non-interactive), a distro index refresh (`./get-deps` does not run one, and fresh/WSL images ship stale lists), the wezterm source tree with submodules (missing submodules fail with a confusing zlib error), and the system libraries via wezterm's own `./get-deps` script (knows the package names for all supported distros)
3. Build with `cargo build --release` and install the `wezterm` / `wezterm-gui` / `wezterm-mux-server` binaries to `/usr/local/bin` (skipped when an wezterm >= 20240127 is already installed)
4. Clone monkey-wezterm to `~/Documents/monkey-wezterm` (or update it if already cloned)
5. Symlink `~/.config/wezterm/wezterm.lua` to the repo, then verify with `checkhealth.sh`

> The script keeps the WezTerm source tree at `~/Documents/wezterm` (no cleanup), so you can rebuild later with `git pull` + `git submodule update --init --recursive` + `cargo build --release` — the submodule step is not optional, a partial submodule tree breaks the build (step 2).
>
> The cargo build is the long pole: 10–30 minutes with no output — the script announces it so the wait is explainable.
>
> `INSTALL_DIR` and `WEZTERM_SRC_DIR` override the two directories — set them in the environment of the `bash` that runs the script (`curl -fsSL … | INSTALL_DIR=~/work/monkey-wezterm bash`); `~/Documents/monkey-wezterm` and `~/Documents/wezterm` are the defaults.

### Option 2: Manual installation

```bash
git clone --depth=1 --branch=main --recursive https://github.com/wez/wezterm.git ~/Documents/wezterm
cd ~/Documents/wezterm && ./get-deps && cargo build --release
sudo cp target/release/{wezterm,wezterm-gui,wezterm-mux-server} /usr/local/bin/
git clone https://github.com/QMonkey/monkey-wezterm ~/Documents/monkey-wezterm
mkdir -p ~/.config/wezterm
ln -sf ~/Documents/monkey-wezterm/.wezterm.lua ~/.config/wezterm/wezterm.lua
```

### `checkhealth.sh`

`./checkhealth.sh` prints the dependency report and exits 1 when a required item
failed. A required item is the wezterm version gate (>= 20240127) or the
`wezterm.lua` symlink; `Plugins` and `Rust toolchain` are advisory only — plugins
live under `~/.local/share/wezterm/plugins/`, where tabline.wez is cloned
automatically on the first `wezterm` start.

- `-i, --install` — if a required item failed, hand the whole job over to
  `install.sh`: building wezterm needs the full toolchain, so this is a source
  build rather than a piecemeal package install. The run ends with `install.sh`'s
  own output and exit status
- `--skip-check-config` — skip the config-file checks; `install.sh` passes this,
  because the verification step runs only after the symlink is in place
- `-h, --help` — usage
- `SUDO_DROPIN` (environment, with `--install`) — `0` authenticates once up front
  and rides the sudo timestamp, `1` installs the temporary NOPASSWD drop-in
  described in step 1. Default `0` for a manual run, `1` when an installer chained
  the call; an explicit value always wins

## `scripts/` (shared framework)

The `scripts/` directory is a [git subtree](https://git-scm.com/docs/git-subtree)
of [monkey-scripts](https://github.com/QMonkey/monkey-scripts) — the shared
install/checkhealth framework that this repo's `install.sh` and
`checkhealth.sh` are built on. Do not edit it here; update it from upstream:

```bash
# first-time fetch (cloned without the subtree):
git subtree add -P scripts https://github.com/QMonkey/monkey-scripts.git master
# later updates:
git subtree pull -P scripts --squash https://github.com/QMonkey/monkey-scripts.git master
```

The one-click installer works without a subtree: on the `curl | bash` path it
clones _this_ repo straight into the install directory (`~/Documents/monkey-wezterm`)
and runs the `install.sh` from that clone, so the installer and the `scripts/`
it loads always come from the same revision. If that directory already exists
but is not a git clone, the installer refuses to touch it and tells you so.
The subtree above is committed and pushed, so
a regular `git clone` of this repo already contains `scripts/` —
there is nothing extra to clone or pull; updates arrive through a plain
`git pull`. Only a checkout from before that commit lacks `scripts/`:
`git pull` (or re-running `install.sh`, which pulls that checkout in place)
fixes it.

## Key bindings

| Key               | Action                                     |
| ----------------- | ------------------------------------------ |
| `CTRL+SHIFT+R`    | Reload configuration (with toast feedback) |
| `CTRL+SHIFT+U`    | Update plugins (with toast feedback)       |
| `CTRL+SHIFT+W`    | Close pane (with confirm)                  |
| `CTRL+SHIFT+Q`    | Quit application                           |
| `CTRL+SHIFT+O`    | Quick select                               |
| `CTRL+SHIFT+T`    | New tab (Windows: fuzzy launch menu)       |
| `CTRL+SHIFT+1..9` | Activate tab 1–9                           |

## Update

```bash
cd ~/Documents/monkey-wezterm && git pull   # config
cd ~/Documents/wezterm && git pull --ff-only && git submodule update --init --recursive && cargo build --release
sudo cp target/release/{wezterm,wezterm-gui,wezterm-mux-server} /usr/local/bin/
```
