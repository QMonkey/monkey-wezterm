#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# monkey-wezterm one-shot installer
# Usage: curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-wezterm/master/install.sh | bash
#
# Builds wezterm from source (rustup + distro deps + cargo build), clones
# this repo, links the config and runs checkhealth.sh for verification.
#
# The shared installer (sudo, packages, clone, symlinks, completion) lives
# in scripts/ — a `git subtree` of github.com/QMonkey/monkey-scripts. On
# the curl|bash path there is no checkout at all, so install.sh clones
# THIS repo and runs the copy of install.sh inside it — that copy carries
# its own scripts/, so both come from the same revision.
# ──────────────────────────────────────────────────────────────

# ──────────────────────── repository identity ────────────────────────
# Declared before the framework is sourced: the bootstrap below needs both
# values, and clones into the very directory clone_monkey_project would
# have used — one clone per run, not two.
PROJECT=monkey-wezterm
PROJECT_REPO=https://github.com/QMonkey/monkey-wezterm.git
INSTALL_DIR="${INSTALL_DIR:-$HOME/Documents/monkey-wezterm}"

# No scripts/ next to this file: either a checkout predating the subtree
# commit (pull it in and carry on) or `curl | bash`, which has no checkout
# at all. The latter clones THIS project and runs the install.sh from that
# checkout, so installer and scripts/ always come from the same revision.
_monkey_scripts="$(dirname "${BASH_SOURCE[0]:-$0}")/scripts"
if [ ! -f "$_monkey_scripts/install.sh" ]; then
	_monkey_self="${BASH_SOURCE[0]:-$0}"
	_monkey_dir="$(dirname "$_monkey_self")"
	if [ -f "$_monkey_self" ] && [ -d "$_monkey_dir/.git" ]; then
		git -C "$_monkey_dir" pull --ff-only || true
		_monkey_scripts="$_monkey_dir/scripts"
		if [ ! -f "$_monkey_scripts/install.sh" ]; then
			echo "monkey-scripts missing from $_monkey_dir (no scripts/ subtree)." >&2
			echo "  git -C $_monkey_dir pull    # outdated checkout — or the repo never added the subtree" >&2
			exit 1
		fi
	else
		# curl|bash: no checkout at all. Get one that carries scripts/ and
		# hand over to its installer, so install.sh and scripts/ can never be
		# different revisions. clone_monkey_project cannot do this job — it
		# lives in the very scripts/ being fetched. INSTALL_DIR is where the
		# framework's clone step would have put the checkout too, so that step
		# only confirms it.

		if ! command -v git >/dev/null 2>&1; then
			echo "git is required to clone $PROJECT — install it first (e.g. sudo apt-get install git), then re-run." >&2
			exit 1
		fi
		if [ -d "$INSTALL_DIR/.git" ]; then
			# An install already lives here: update it, then run that one.
			git -C "$INSTALL_DIR" pull --ff-only || true
		elif [ -d "$INSTALL_DIR" ] && [ -n "$(ls -A "$INSTALL_DIR")" ]; then
			# git clone would refuse too, so say why in our own words.
			echo "$INSTALL_DIR is not empty and is not a git clone." >&2
			echo "  move it aside, delete it, or set INSTALL_DIR elsewhere." >&2
			exit 1
		else
			# No retry() available yet — the framework loads only after this
		# clone succeeds — so inline the standard 3 attempts. A failed clone
		# leaves a partial directory behind; remove it so the next attempt
		# cannot trip over "already exists". This branch only runs on a
		# fresh install (INSTALL_DIR did not exist or was empty), so the rm
		# can never delete pre-existing data.
		_monkey_rc=1
		for _monkey_attempt in 1 2 3; do
			if git clone "$PROJECT_REPO" "$INSTALL_DIR"; then
				_monkey_rc=0
				break
			fi
			rm -rf "$INSTALL_DIR"
			if [ "$_monkey_attempt" -lt 3 ]; then
				sleep 2
			fi
		done
		[ "$_monkey_rc" -eq 0 ] || exit 1
		fi
		# </dev/null: on the curl|bash path stdin is the script pipe, and the
		# inner installer must not read what is left of the outer one.
		exec bash "$INSTALL_DIR/install.sh" "$@" </dev/null
	fi
fi
# shellcheck source=/dev/null
. "$_monkey_scripts/install.sh"

# ──────────────────────── layout & data ────────────────────────
WEZTERM_SRC_DIR="${WEZTERM_SRC_DIR:-$HOME/Documents/wezterm}"
CHECKHEALTH_POS=after_links # the original verifies AFTER the config link
CHECKHEALTH_MODE=verify     # plain run — --install would recurse into here
INSTALL_INFO=(
	"wezterm source: ${CYAN}$WEZTERM_SRC_DIR${NC} (kept for future updates)"
)
SUMMARY_LINES=(
	"  Config:   ${CYAN}$INSTALL_DIR/.wezterm.lua${NC} → ${CYAN}~/.config/wezterm/wezterm.lua${NC}"
	"  Plugins:  ${CYAN}~/.local/share/wezterm/plugins/${NC} (tabline.wez, auto-cloned on first start)"
	""
	"  Run ${CYAN}wezterm${NC} to start."
	"  Update wezterm: ${CYAN}cd $WEZTERM_SRC_DIR && git pull --ff-only && git submodule update --init --recursive && cargo build --release && sudo cp target/release/{wezterm,wezterm-gui} /usr/local/bin/${NC}"
	"  Update monkey-wezterm: ${CYAN}cd $INSTALL_DIR && git pull${NC}"
)

# ──────────────────────── build steps (verbatim) ────────────────────────

ensure_rustup() {
	if have_native_cmd cargo; then
		ok "rust toolchain already installed."
		return 0
	fi
	# Official rustup installer (BUILD.md: Rust 1.71+ required). Downloaded
	# fully before executing, with retries — `curl | sh` would run a
	# truncated script if the connection drops mid-stream.
	info "Installing rustup (non-interactive)..."
	local rustup_init="/tmp/rustup_init.$$.sh"
	if retry -t 1800 -s "rustup installer download" curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o "$rustup_init"; then
		# The -y run downloads the whole toolchain (hundreds of MB) — long
		# timeout, retried: rustup-init is idempotent, a retry continues.
		retry -t 3600 -s "rustup toolchain install" sh "$rustup_init" -y
		rm -f "$rustup_init"
	else
		fail "rustup installer download failed — install it manually: https://rust-lang.org/tools/install/"
	fi
	# rustup installs into ~/.cargo — put cargo on PATH for this run (the
	# cargo build below runs in this same script). Not `[ ... ] && . ...`:
	# a missing file would make the function return non-zero and, under
	# set -e, silently abort the whole script.
	if [ -f "$HOME/.cargo/env" ]; then . "$HOME/.cargo/env"; fi
	have_native_cmd cargo || fail "rustup installation failed — install it manually: https://rust-lang.org/tools/install/"
	ok "rustup installed."
}

ensure_wezterm_source() {
	if [ -d "$WEZTERM_SRC_DIR/.git" ]; then
		info "wezterm source already exists at $WEZTERM_SRC_DIR — pulling latest..."
		retry -s "git pull" git -C "$WEZTERM_SRC_DIR" pull --ff-only ||
			warn "git pull failed — building from existing source."
		retry -s "git submodule update" git -C "$WEZTERM_SRC_DIR" submodule update --init --recursive ||
			warn "submodule update failed — build may fail with a zlib error."
	else
		# BUILD.md: submodules are REQUIRED (missing them fails with a
		# confusing zlib error), hence --recursive. A failed clone leaves a
		# partial directory behind, which would make every later attempt
		# (and re-run) fail with "already exists" — clean it up before
		# giving up, but only when git created it (.git inside) or it is
		# empty, never when it holds pre-existing user data.
		info "Cloning wezterm source (with submodules)..."
		if ! retry -t 1800 -s "git clone wezterm" git clone --depth=1 --branch=main --recursive https://github.com/wez/wezterm.git "$WEZTERM_SRC_DIR"; then
			if [ -d "$WEZTERM_SRC_DIR" ] && { [ -z "$(ls -A "$WEZTERM_SRC_DIR")" ] || [ -d "$WEZTERM_SRC_DIR/.git" ]; }; then
				rm -rf "$WEZTERM_SRC_DIR"
			fi
			fail "wezterm source clone failed after 3 attempts."
		fi
	fi
}

install_build_deps() {
	# git is needed to clone the sources; every other system dependency is
	# installed by wezterm's own ./get-deps script, which knows the package
	# names for all supported distros (and macOS via brew).
	if ! have_native_cmd git; then
		info "Installing git..."
		install_pkg git || :
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
	# get-deps drives the distro package manager over the network — exactly
	# the kind of call that fails transiently, so give it the standard
	# retries. It is idempotent (already-installed packages are skipped).
	(cd "$WEZTERM_SRC_DIR" && retry -t 1800 -s "wezterm get-deps" ./get-deps) ||
		warn "get-deps failed — install the libraries listed in wezterm docs/install/source.md manually."
}

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
	retry -t 1800 -s "cargo build wezterm" cargo build --release 2>&1 | tee /tmp/wezterm-build.log || {
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

# ──────────────────────── project steps ────────────────────────

# No blank line before the first step: the original runs it right after
# setup_sudo; the trailing blank is its own.
install_step_prepare() {
	install_build_deps
	echo ""
}

install_step_tool() {
	build_wezterm
	echo ""
}

# The original force-links with ln -sf and reports a fixed, repo-relative
# path — kept verbatim (overrides the shared setup_symlinks).
setup_symlinks() {
	info "Setting up configuration symlinks..."
	mkdir -p "$HOME/.config/wezterm"
	ln -sf "$INSTALL_DIR/.wezterm.lua" "$HOME/.config/wezterm/wezterm.lua"
	ok ".config/wezterm/wezterm.lua → $INSTALL_DIR/.wezterm.lua"
}

install_main "$@"
