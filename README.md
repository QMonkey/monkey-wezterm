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

- WezTerm 20240127+ (for `config_builder` and the plugin API; the one-click installer builds a current WezTerm from source)
- A Rust toolchain (rustup) — only needed to build; the installer sets it up

## Installation

Pick one of the two ways below: a one-click script, or manual setup.

### Option 1: One-click install

Build WezTerm from source (distro packages lag far behind) and install monkey-wezterm automatically:

```bash
curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-wezterm/master/install.sh | bash
```

What the script does, step by step:

1. Set up the build environment: rustup (non-interactive), the wezterm source tree with submodules (missing submodules fail with a confusing zlib error), and the system libraries via wezterm's own `./get-deps` script (knows the package names for all supported distros)
2. Pre-authorize `sudo` once — the only password entry of the whole run — and install a **temporary** NOPASSWD sudoers drop-in for the invoking user, removed automatically on exit. `./get-deps` runs many sudo calls across a 10–30 minute cargo build, and WSL2 clock jumps invalidate tickets; NOPASSWD makes the run immune to both. If the drop-in cannot be installed, the script falls back to a background keepalive plus lazy re-authentication
3. Build with `cargo build --release` and install the `wezterm` / `wezterm-gui` / `wezterm-mux-server` binaries to `/usr/local/bin` (skipped when an wezterm >= 20240127 is already installed)
4. Clone monkey-wezterm to `~/Documents/monkey-wezterm` (or update it if already cloned)
5. Symlink `~/.config/wezterm/wezterm.lua` to the repo, then verify with `checkhealth.sh`

> The script keeps the WezTerm source tree at `~/Documents/wezterm` (no cleanup), so you can rebuild later with `git pull` + `cargo build --release`.
>
> The cargo build is the long pole: 10–30 minutes with no output — the script announces it so the wait is explainable.

### Option 2: Manual installation

```bash
git clone --depth=1 --branch=main --recursive https://github.com/wez/wezterm.git ~/Documents/wezterm
cd ~/Documents/wezterm && ./get-deps && cargo build --release
sudo cp target/release/{wezterm,wezterm-gui,wezterm-mux-server} /usr/local/bin/
git clone https://github.com/QMonkey/monkey-wezterm ~/Documents/monkey-wezterm
mkdir -p ~/.config/wezterm
ln -sf ~/Documents/monkey-wezterm/.wezterm.lua ~/.config/wezterm/wezterm.lua
```

## Key bindings

| Key   | Action      |                                            |
| ----- | ----------- | ------------------------------------------ |
| `CTRL | SHIFT+R`    | Reload configuration (with toast feedback) |
| `CTRL | SHIFT+U`    | Update plugins (with toast feedback)       |
| `CTRL | SHIFT+W`    | Close pane (with confirm)                  |
| `CTRL | SHIFT+Q`    | Quit application                           |
| `CTRL | SHIFT+O`    | Quick select                               |
| `CTRL | SHIFT+T`    | New tab (Windows: fuzzy launch menu)       |
| `CTRL | SHIFT+1..9` | Activate tab 1–9                           |

## Update

```bash
cd ~/Documents/monkey-wezterm && git pull   # config
cd ~/Documents/wezterm && git pull --ff-only && git submodule update --init --recursive && cargo build --release
sudo cp target/release/{wezterm,wezterm-gui} /usr/local/bin/
```
