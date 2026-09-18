#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# monkey-wezterm one-shot installer
# Usage: curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-wezterm/master/install.sh | bash
# ──────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="${INSTALL_DIR:-$HOME/Documents/monkey-wezterm}"
WEZTERM_SRC_DIR="${WEZTERM_SRC_DIR:-$HOME/Documents/wezterm}"
SUDOERS_D_DIR="${SUDOERS_D_DIR:-/etc/sudoers.d}"
SUDO_NOPASSWD=0
NOPASSWD_DROPIN="$SUDOERS_D_DIR/zz-monkey-wezterm-nopasswd"

# Never let a missing HOME fail later under `set -u`.
[ -n "${HOME:-}" ] || {
	echo "[FAIL] \$HOME is not set — cannot determine install locations." >&2
	exit 1
}

info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok() { echo -e "${GREEN}[  OK]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() {
	echo -e "${RED}[FAIL]${NC}  $*"
	exit 1
}

# ────────────────── OS / WSL detection ──────────────────

os_detect() {
	case "$(uname -s)" in
	Linux)
		if [ -f /etc/os-release ]; then
			# shellcheck disable=SC1091
			. /etc/os-release
			case "${ID:-}" in
			ubuntu | debian | linuxmint | pop | elementary | zorin) echo "debian" ;;
			arch | manjaro | endeavouros) echo "arch" ;;
			opensuse* | suse | sles) echo "opensuse" ;;
			centos | rhel | fedora | rocky | almalinux | ol) echo "centos" ;;
			*) echo "linux-unknown" ;;
			esac
		else
			echo "linux-unknown"
		fi
		;;
	Darwin) echo "macos" ;;
	*) echo "unknown" ;;
	esac
}

# WSL interop appends the WINDOWS PATH to ours, so tools installed on the
# Windows side (node, python, sudo.exe, ...) appear as /mnt/c/... shims.
# They are not Linux binaries and root's secure_path cannot see them —
# treat /mnt/* resolutions as "not installed" so the real Linux packages
# get installed instead.
have_native_cmd() {
	command -v "$1" &>/dev/null || return 1
	case "$(command -v "$1")" in
	/mnt/*) return 1 ;; # WSL Windows-interop shim
	esac
	return 0
}

# Absolute path to a LINUX sudo, or non-zero.
native_sudo() {
	local p
	have_native_cmd sudo || return 1
	p=$(command -v sudo)
	printf '%s' "$p"
}

OS=$(os_detect)

# TIOCSTI injection right: a chaining wrapper may pre-set this to its
# own name — then THIS script must not inject. Standalone runs self-claim.
ACQUIRE_TIOCSTI="${ACQUIRE_TIOCSTI:-monkey-wezterm}"

sudo_cmd() {
	# Lazy re-auth: Homebrew resets the sudo timestamp on EVERY invocation
	# (brew.sh runs `sudo --reset-timestamp` at startup), so a ticket that
	# was valid a minute ago can be dead here. Re-authenticate proactively
	# with an explanatory prompt instead of letting the command fail or
	# spring a context-free password prompt. `-n true` never prompts; the
	# interactive `-v` only runs when the ticket is actually gone.
	local sudo_bin
	sudo_bin=$(native_sudo) || {
		"$@"
		return
	}
	if ! "$sudo_bin" -n true 2>/dev/null; then
		"$sudo_bin" -v -p "[monkey-wezterm] sudo credentials needed to continue — enter your password: " || return 1
	fi
	"$sudo_bin" "$@"
}

# ────────────────── TIOCSTI injection ──────────────────
# Type <cmd> + newline into the controlling terminal: the parent shell
# executes it as if the user had typed it — AFTER this script (and any
# wrapper chaining it) has fully exited, so injection can never disturb
# the run itself. Needs python3 or perl; any failure returns non-zero so
# callers can fall back to a printed hint. Never fatal.
inject_tty() {
	local cmd="$1" tiocsti
	[ -n "$cmd" ] || return 1
	# No writable controlling terminal (CI, nested pipes) — nothing to
	# inject into. access(W_OK) on /dev/tty fails with ENXIO when the
	# process has no controlling tty.
	[ -w /dev/tty ] || return 1
	# python3 first: termios.TIOCSTI carries the correct constant per
	# platform (Linux 0x5412, Darwin 0x80047412).
	if have_native_cmd python3; then
		python3 - "$cmd" <<'PYEOF' 2>/dev/null && return 0
import sys, os, fcntl, termios
cmd = sys.argv[1] + "\n"
try:
    fd = os.open("/dev/tty", os.O_WRONLY)
    ioctl = termios.TIOCSTI
except (OSError, AttributeError):
    sys.exit(1)
for ch in cmd:
    try:
        fcntl.ioctl(fd, ioctl, ord(ch))
    except OSError:
        sys.exit(1)
PYEOF
	fi
	# perl fallback: macOS ships /usr/bin/perl, Debian/Ubuntu perl-base is
	# Essential. TIOCSTI's value differs per platform.
	tiocsti=0x5412
	[ "$(uname -s)" = "Darwin" ] && tiocsti=0x80047412
	perl -e '
		my ($cmd, $tio) = @ARGV;
		open(my $tty, ">", "/dev/tty") or exit 1;
		for my $ch (split //, $cmd . "\n") {
			ioctl($tty, hex($tio), ord($ch)) or exit 1;
		}
	' "$cmd" "$tiocsti" 2>/dev/null && return 0
	return 1
}

# Print the login-shell profile file for the detected shell
# (used for the final PATH hint).
shell_env_files() {
	# The TARGET login shell, queried from the user database: on a
	# zsh-default machine (or after the login shell has been switched to
	# zsh) it is zsh and the env blocks belong in ~/.zprofile; on bash
	# machines they land in the bash profile files. Falls back to $SHELL,
	# then bash (macOS has no getent; its $SHELL already reflects the
	# login shell).
	local shell
	# getent does not exist on macOS — guard the call, otherwise the
	# command-not-found failure (127) would trip `set -e` and kill the
	# script before the dscl fallback below ever runs.
	if have_native_cmd getent; then
		shell=$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)
	fi
	if [ -z "$shell" ] && [ "$(uname -s)" = Darwin ]; then
		# No getent on macOS — query the directory service instead ($SHELL
		# is a login-time snapshot and goes stale right after a chsh in
		# the same session).
		shell=$(dscl . -read /Users/"$(id -un)" UserShell 2>/dev/null | awk '{print $2}')
	fi
	shell=${shell:-${SHELL:-bash}}
	shell=${shell##*/}
	shell="${shell##*/}"
	case "$shell" in
	zsh)
		printf '%s\n' "$HOME/.zprofile"
		;;
	bash)
		if [ -f "$HOME/.bash_profile" ]; then
			printf '%s\n' "$HOME/.bash_profile"
		else
			printf '%s\n' "$HOME/.profile"
		fi
		;;
	*)
		printf '%s\n' "$HOME/.profile"
		;;
	esac
}

# ────────────────── sudo setup (auth + drop-ins + keepalive) ──────────────────

SUDO_KEEPALIVE_PID=""

cleanup_sudo() {
	# Kill the keepalive (if running) and remove the temporary NOPASSWD
	# drop-in. `sudo -n rm` works while NOPASSWD is still in place — the
	# file grants it, so removal never needs a password.
	if [ -n "$SUDO_KEEPALIVE_PID" ]; then
		kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
		wait "$SUDO_KEEPALIVE_PID" 2>/dev/null
	fi
	if [ "$SUDO_NOPASSWD" -eq 1 ] && [ -n "$SUDO_BIN" ]; then
		"$SUDO_BIN" -n rm -f "$NOPASSWD_DROPIN" 2>/dev/null ||
			warn "could not remove the NOPASSWD drop-in — remove it manually: sudo rm $NOPASSWD_DROPIN"
	fi
}

setup_sudo() {
	# Keep sudo credentials alive for the whole run: the gap between the first
	# sudo (build deps) and later ones (make install) can exceed the default
	# 15-min timestamp_timeout on slow downloads/compiles. A re-auth prompt
	# then aborts unattended runs (no TTY to answer it).
	# Skip when running as root or when no native sudo is available.
	SUDO_BIN=$(native_sudo) || return 0
	if [ "$(id -u)" -eq 0 ]; then
		return 0
	fi
	# Pre-authenticate so the password is entered at the very start instead
	# of mid-run after a long download/compile, then grant NOPASSWD for the
	# rest of the run:
	#
	# Probe first (`-n true`, a command): when credentials are already
	# valid — this run's own drop-in from a previous stage, or an outer
	# installer's grant — skip the authenticate step entirely; chained
	# stages never re-prompt. Failure means no valid grant exists and
	# `sudo -v` prompts for the one password of the run.
	#
	# Why the drop-in is NOPASSWD: authentication is granted by the rule
	# itself and the timestamp is never consulted, so brew's
	# --reset-timestamp, clock jumps and plain expiry are all harmless.
	# GNU sudo resolves conflicting rules last-match-wins, so this drop-in
	# (parsed after the distro's password-required rule) always wins.
	# sudo-rs would defeat this tag for VALIDATE (max_by_key picks the
	# password-required rule) — but every sudo in this script is a command
	# or the probe, where NOPASSWD wins on both implementations.
	if ! "$SUDO_BIN" -n true 2>/dev/null; then
		"$SUDO_BIN" -v || fail "sudo authorization failed — run this script in an interactive terminal."
	fi
	# Scoped to the invoking user and REMOVED on exit (incl. Ctrl-C);
	# if the script is SIGKILLed the file survives — remove manually with
	# `sudo rm $NOPASSWD_DROPIN`. If you prefer a permanent passwordless
	# sudo, add the same line to your own sudoers drop-in instead.
	if printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$(id -un)" |
		"$SUDO_BIN" -n sh -c 'umask 077; cat >"$1" && chmod 0440 "$1" && visudo -c -f "$1" >/dev/null 2>&1 || { rm -f "$1"; exit 1; }' sh "$NOPASSWD_DROPIN" >/dev/null 2>&1; then
		SUDO_NOPASSWD=1
		ok "Temporary NOPASSWD drop-in installed for this run (auto-removed on exit)."
	else
		warn "could not install the temporary NOPASSWD drop-in — falling back to keepalive + lazy re-auth."
	fi
	if [ "$SUDO_NOPASSWD" -eq 0 ]; then
		# Fallback when NOPASSWD could not be installed: refresh the ticket
		# in the background so plain expiry does not prompt mid-run. It
		# cannot fully protect the run — brew resets the ticket by design
		# and WSL clock steps disable it — so when this stops, sudo_cmd()
		# re-authenticates lazily (one explanatory prompt) at the next
		# privileged call.
		(
			# 60s refresh against the 15-min default timeout leaves a 15x
			# margin; override via SUDO_KEEPALIVE_INTERVAL if needed.
			interval="${SUDO_KEEPALIVE_INTERVAL:-60}"
			# Kill the in-flight `sleep` child when TERMed, and wait() to
			# reap — WSL's init does not reap adopted zombies.
			trap 'kill $(jobs -p) 2>/dev/null; wait 2>/dev/null; exit 0' TERM
			while true; do
				sleep "$interval" &
				wait "$!" 2>/dev/null || exit 0
				if ! "$SUDO_BIN" -n true 2>/dev/null; then
					warn "sudo keepalive stopped — expected after a brew run; the next privileged command re-authenticates."
					exit 0
				fi
			done
		) &
		SUDO_KEEPALIVE_PID=$!
	fi
	# Recycle the background loop and drop the NOPASSWD grant on any exit
	# path (success, fail, Ctrl-C).
	trap cleanup_sudo EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
}

# ────────────────── Step 1: Set up the wezterm build environment ──────────────────

# ────────────────── package index refresh ──────────────────
# Refresh the package index before installing: a stale or missing index is
# the usual cause of "Unable to locate package" on freshly provisioned
# machines. Retried once for transient network failures; a failed refresh
# is never fatal — the install step still runs. Guarded to at most one
# refresh per run — call freely before every install.
PKG_DB_REFRESHED=0
refresh_pkg() {
	[ "$PKG_DB_REFRESHED" -eq 1 ] && return 0
	PKG_DB_REFRESHED=1
	local attempt
	for attempt in 1 2; do
		case "$OS" in
		debian) sudo_cmd apt-get update ;;
		arch) sudo_cmd pacman -Sy ;;
		opensuse) sudo_cmd zypper --non-interactive refresh ;;
		centos) sudo_cmd dnf makecache -q ;;
		macos | *) return 0 ;;
		esac && return 0
		[ "$attempt" -lt 2 ] && sleep 2
	done
	return 0
}

install_with_system_mgr() {
	refresh_pkg
	case "$OS" in
	debian) sudo_cmd apt-get install -y "$@" ;;
	arch) sudo_cmd pacman -S --noconfirm "$@" ;;
	opensuse) sudo_cmd zypper --non-interactive install -y "$@" ;;
	centos)
		sudo_cmd dnf install -y epel-release || true
		sudo_cmd dnf install -y "$@"
		;;
	macos) brew install "$@" ;;
	*) return 1 ;;
	esac
}

ensure_rustup() {
	if have_native_cmd cargo; then
		ok "rust toolchain already installed."
		return 0
	fi
	# Official rustup installer (BUILD.md: Rust 1.71+ required).
	info "Installing rustup (non-interactive)..."
	curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
	# rustup installs into ~/.cargo — put cargo on PATH for this run (the
	# cargo build below runs in this same script).
	[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
	have_native_cmd cargo || fail "rustup installation failed — install it manually: https://rust-lang.org/tools/install/"
	ok "rustup installed."
}

ensure_wezterm_source() {
	if [ -d "$WEZTERM_SRC_DIR/.git" ]; then
		info "wezterm source already exists at $WEZTERM_SRC_DIR — pulling latest..."
		git -C "$WEZTERM_SRC_DIR" pull --ff-only || warn "git pull failed — building from existing source."
		git -C "$WEZTERM_SRC_DIR" submodule update --init --recursive || warn "submodule update failed — build may fail with a zlib error."
	else
		# BUILD.md: submodules are REQUIRED (missing them fails with a
		# confusing zlib error), hence --recursive.
		info "Cloning wezterm source (with submodules)..."
		git clone --depth=1 --branch=main --recursive https://github.com/wez/wezterm.git "$WEZTERM_SRC_DIR"
	fi
}

install_build_deps() {
	# git is needed to clone the sources; every other system dependency is
	# installed by wezterm's own ./get-deps script, which knows the package
	# names for all supported distros (and macOS via brew).
	if ! have_native_cmd git; then
		info "Installing git..."
		install_with_system_mgr git
		hash -r
	fi
	have_native_cmd git || fail "git installation failed — install it manually."
	ensure_rustup
	# apt lists on fresh/WSL images are often stale or lack the universe
	# index that some of wezterm's ./get-deps packages live in — get-deps
	# does not run apt-get update itself.
	if have_native_cmd apt-get; then
		sudo_cmd apt-get update -q || true
	fi
	ensure_wezterm_source
	info "Installing wezterm system dependencies via ./get-deps..."
	(cd "$WEZTERM_SRC_DIR" && ./get-deps) || warn "get-deps failed — install the libraries listed in wezterm docs/install/source.md manually."
}

# ────────────────── Step 2: Build wezterm from source ──────────────────

# wezterm versions are date-based: "wezterm 20240127-113934-3aa51d5a".
# The config needs 20240127+ (config_builder, plugin API, kitty keyboard).
wezterm_at_least() {
	have_native_cmd wezterm || return 1
	local ver
	ver=$(wezterm --version 2>/dev/null | grep -oE '[0-9]{8}' | head -1)
	[[ -z "$ver" ]] && return 1
	((ver >= 20240127))
}

build_wezterm() {
	if wezterm_at_least; then
		ok "$(wezterm --version 2>/dev/null | head -1) already installed and meets requirement (>= 20240127). Skipping build."
		return 0
	fi
	warn "wezterm 20240127+ not found or below requirement — building from source."

	pushd "$WEZTERM_SRC_DIR" >/dev/null
	# This is the long pole: a full rust release build runs 10-30 minutes
	# with NO output from cargo itself — spell out that the wait is normal.
	info "Compiling wezterm (cargo build --release) — 10-30 minutes, no output below until done..."
	cargo build --release 2>&1 | tee /tmp/wezterm-build.log || {
		fail "wezterm build failed. Check /tmp/wezterm-build.log"
	}
	popd >/dev/null

	info "Installing wezterm binaries to /usr/local/bin..."
	local bin
	for bin in wezterm wezterm-gui wezterm-mux-server; do
		if [ -x "$WEZTERM_SRC_DIR/target/release/$bin" ]; then
			sudo_cmd cp "$WEZTERM_SRC_DIR/target/release/$bin" /usr/local/bin/
			ok "$bin → /usr/local/bin/$bin"
		fi
	done
	hash -r

	if wezterm_at_least; then
		ok "$(wezterm --version 2>/dev/null | head -1) built and installed successfully."
	else
		fail "wezterm build completed but wezterm is not found in PATH."
	fi
}

# ────────────────── Step 3: Clone monkey-wezterm ──────────────────

clone_monkey_wezterm() {
	if [ -d "$INSTALL_DIR/.git" ]; then
		info "monkey-wezterm already exists at $INSTALL_DIR — pulling latest..."
		git -C "$INSTALL_DIR" pull --ff-only || warn "git pull failed — keeping existing version."
	else
		info "Cloning monkey-wezterm to $INSTALL_DIR..."
		git clone https://github.com/QMonkey/monkey-wezterm.git "$INSTALL_DIR"
	fi
	ok "monkey-wezterm ready at $INSTALL_DIR."
}

# ────────────────── Step 4: Symlink config ──────────────────

setup_symlinks() {
	info "Setting up configuration symlinks..."
	mkdir -p "$HOME/.config/wezterm"
	ln -sf "$INSTALL_DIR/.wezterm.lua" "$HOME/.config/wezterm/wezterm.lua"
	ok ".config/wezterm/wezterm.lua → $INSTALL_DIR/.wezterm.lua"
}

# ────────────────── Step 5: Verify with checkhealth.sh ──────────────────

# Plain run (no --install): everything should pass except the plugins WARN,
# which resolves on first wezterm start.
verify_checkhealth() {
	bash "$INSTALL_DIR/checkhealth.sh" || true
}

# ────────────────── Main ──────────────────

main() {
	echo ""
	echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
	echo -e "${BOLD}║      monkey-wezterm installer            ║${NC}"
	echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
	echo ""

	info "Detected OS: ${CYAN}${OS}${NC}"
	info "monkey-wezterm: ${CYAN}${INSTALL_DIR}${NC}"
	info "wezterm source: ${CYAN}${WEZTERM_SRC_DIR}${NC} (kept for future updates)"
	echo ""

	setup_sudo

	install_build_deps
	echo ""

	build_wezterm
	echo ""

	clone_monkey_wezterm
	echo ""

	setup_symlinks
	echo ""

	verify_checkhealth
	echo ""

	echo -e "${GREEN}${BOLD}monkey-wezterm installation complete!${NC}"
	echo ""
	echo -e "  Config:   ${CYAN}$INSTALL_DIR/.wezterm.lua${NC} → ${CYAN}~/.config/wezterm/wezterm.lua${NC}"
	echo -e "  Plugins:  ${CYAN}~/.local/share/wezterm/plugins/${NC} (tabline.wez, auto-cloned on first start)"
	echo ""
	echo -e "  Run ${CYAN}wezterm${NC} to start."
	echo -e "  Update wezterm: ${CYAN}cd $WEZTERM_SRC_DIR && git pull --ff-only && git submodule update --init --recursive && cargo build --release && sudo cp target/release/{wezterm,wezterm-gui} /usr/local/bin/${NC}"
	echo -e "  Update monkey-wezterm: ${CYAN}cd $INSTALL_DIR && git pull${NC}"
	echo ""
	# The .cargo/bin PATH line was added to shell rc files by rustup, but it
	# only applies to shells started AFTER this point.
	local env_file
	env_file="$(shell_env_files | head -1)"
	# ACQUIRE_TIOCSTI protocol: only the script that claimed the injection
	# right acts. When chained, the wrapper holds the right and injects once
	# at its own end — per-component hints would be redundant there.
	if [ "$ACQUIRE_TIOCSTI" != "monkey-wezterm" ]; then
		: # wrapper holds the injection right
	elif inject_tty "source ${env_file}"; then
		echo -e "  ${GREEN}Injected 'source ${env_file}' into the current terminal.${NC}"
	else
		echo -e "  ${YELLOW}New PATH takes effect in NEW shells. To use it in this terminal now:${NC}"
		echo -e "    ${CYAN}source ${env_file}${NC}    ${YELLOW}# or simply: ${CYAN}exec \$SHELL${NC}"
	fi
	echo ""
}

main "$@"
