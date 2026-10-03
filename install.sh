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
# No scripts/ next to this file: either a checkout predating the subtree
# commit (pull it in and carry on), a .git-less directory (zip/tarball),
# or `curl | bash`, which has no checkout at all. The latter two bootstrap
# through INSTALL_DIR and run the install.sh from that checkout, so
# installer and scripts/ always come from the same revision.
_monkey_scripts="$(dirname "${BASH_SOURCE[0]:-$0}")/scripts"
if [ ! -f "$_monkey_scripts/install.sh" ]; then
	_monkey_self="${BASH_SOURCE[0]:-$0}"
	_monkey_dir="$(dirname "$_monkey_self")"
	if [ -f "$_monkey_self" ] && [ -d "$_monkey_dir/.git" ]; then
		# Outdated checkout: update it in place and keep running from it.
		git -C "$_monkey_dir" pull --ff-only || true
		if [ ! -f "$_monkey_dir/scripts/install.sh" ]; then
			echo "monkey-scripts missing from $_monkey_dir (no scripts/ subtree)." >&2
			echo "  git -C $_monkey_dir pull    # outdated checkout — or the repo never added the subtree" >&2
			exit 1
		fi
		_monkey_scripts="$_monkey_dir/scripts"
	else
		# curl|bash or a .git-less directory: the only path to a
		# same-revision scripts/ is the INSTALL_DIR checkout.
		# clone_monkey_project cannot do this job — it lives in the very
		# scripts/ being fetched. INSTALL_DIR is where the framework's clone
		# step would have put the checkout too, so that step only confirms it.
		if [ -d "$INSTALL_DIR/.git" ]; then
			# An install already lives here: update it, then run that one.
			git -C "$INSTALL_DIR" pull --ff-only || true
		elif [ -d "$INSTALL_DIR" ] && [ -n "$(ls -A "$INSTALL_DIR")" ]; then
			# git clone would refuse too, so say why in our own words.
			echo "$INSTALL_DIR is not empty and is not a git clone." >&2
			echo "  move it aside, delete it, or set INSTALL_DIR elsewhere." >&2
			exit 1
		else
			# Fresh clone — the ONLY sub-branch where git is hard-required:
			# the pull sub-branch above degrades gracefully without it, and
			# a zip/tarball must not fail here just for a missing git.
			if ! command -v git >/dev/null 2>&1; then
				echo "git is required to clone $PROJECT — install it first (e.g. sudo apt-get install git), then re-run." >&2
				exit 1
			fi
			# No retry() available yet — the framework loads only after this
			# clone succeeds — so inline the standard 3 attempts. A failed
			# clone leaves a partial directory behind; remove it so the next
			# attempt cannot trip over "already exists". This branch only
			# runs on a fresh install (INSTALL_DIR did not exist or was
			# empty), so the rm can never delete pre-existing data.
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
SYMLINKS=(
	"$INSTALL_DIR/.wezterm.lua|$HOME/.config/wezterm/wezterm.lua"
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

ensure_wezterm_source() {
	clone_repo --depth=1 --branch=main https://github.com/wez/wezterm.git "$WEZTERM_SRC_DIR" ||
		fail "wezterm source clone failed."
	# Submodules are fetched after BOTH paths of clone_repo (fresh clone and
	# pull) — git submodule update is idempotent (already-checked-out
	# submodules are skipped), so one unconditional call covers both.
	info "Fetching submodules..."
	retry -t 1800 -s "git submodule wezterm" git -C "$WEZTERM_SRC_DIR" submodule update --init --recursive ||
		fail "wezterm submodule fetch failed — re-run the installer to resume."
}

install_build_deps() {
	# git is needed to clone the sources; every other system dependency is
	# installed by wezterm's own ./get-deps script, which knows the package
	# names for all supported distros (and macOS via brew). ensure_git and
	# ensure_rustup live in the shared framework (pkg.sh).
	ensure_git
	ensure_rustup
	# apt lists on fresh/WSL images are often stale or lack the universe
	# index that some of wezterm's ./get-deps packages live in — get-deps
	# does not run apt-get update itself. refresh_pkg (pkg.sh) is distro-
	# aware, retried, and guarded to one refresh per run.
	refresh_pkg
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

install_main "$@"
