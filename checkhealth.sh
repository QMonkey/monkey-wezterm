#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# monkey-wezterm dependency check
#
# The check framework lives in scripts/ (a `git subtree` of
# github.com/QMonkey/monkey-scripts) — this file only declares WHAT to check.
# ──────────────────────────────────────────────────────────────

. "$(dirname "${BASH_SOURCE[0]:-$0}")/scripts/checkhealth.sh" || {
	echo "monkey-scripts not found — update this checkout (git pull / re-clone)," >&2
	echo "or run install.sh, which bootstraps monkey-scripts itself." >&2
	exit 1
}

# ──────────────────────── identity ────────────────────────
PROJECT=monkey-wezterm

# No required/recommended lists: wezterm itself is built by install.sh
# (which is also where --install hands over to), plugins and the rust
# toolchain are informational.
CONFIG_PHASE=early # config is checked right after Platform, before plugins

# ──────────────────────── usage (wording differs) ────────────────────────
usage() {
	cat <<EOF
Usage: $0 [OPTIONS]

Check and optionally install dependencies for ${PROJECT}.

OPTIONS
  -i, --install    Install missing dependencies (delegates to install.sh)
  --skip-check-config
                   Skip config-file checks (install.sh passes this: the
                   config symlinks are linked before this script runs)
  -h, --help       Show this help

Exit code: 1 if any required dependency is missing, 0 otherwise.
EOF
	exit 0
}

# ──────────────────────── wezterm version ────────────────────────
# Printed between the title and Platform (the original's main sequence).
# Failures are folded into REQUIRED_FAILURES by checkhealth_extra —
# run_required_checks resets the counter after this hook ran.
WEZTERM_VERSION_FAILED=0

# wezterm versions are date-based: "wezterm 20240127-113934-3aa51d5a".
# The config needs 20240127+ (config_builder, plugin API, kitty keyboard).
wezterm_at_least() {
	have_native_cmd wezterm || return 1
	local ver
	ver=$(wezterm --version 2>/dev/null | grep -oE '[0-9]{8}' | head -1)
	[[ -z "$ver" ]] && return 1
	((ver >= 20240127))
}

print_header_extra() {
	echo -e "${BOLD}wezterm${NC}"
	if wezterm_at_least; then
		ok "$(wezterm --version 2>/dev/null | head -1)"
	else
		if have_native_cmd wezterm; then
			fail "$(wezterm --version 2>/dev/null | head -1) (need >= 20240127 for config_builder / plugin API)"
		else
			fail "wezterm (not found)"
		fi
		WEZTERM_VERSION_FAILED=1
	fi
	echo ""
}

# wezterm's Platform section is uname only — no package-manager line.
print_platform() {
	echo -e "${BOLD}Platform${NC}"
	echo -e "  OS: ${CYAN}$(uname -s)${NC}"
	echo ""
}

# ──────────────────────── sections ────────────────────────
check_config_files() {
	# --skip-check-config (passed by install.sh): the config symlinks are
	# the installer's job, and judging them here would misreport a state
	# the installer is about to create. Standalone runs (the manual
	# diagnosis entry point) still get the full check.
	if $SKIP_CONFIG_CHECKS; then
		warn "config checks skipped (handled by the installer)"
		return 0
	fi
	echo -e "${BOLD}Config files${NC}"
	local conf="${HOME}/.config/wezterm/wezterm.lua"
	if [[ -L "$conf" ]]; then
		local target
		target=$(readlink -f "$conf" 2>/dev/null || readlink "$conf")
		if [[ -f "$target" ]]; then
			ok "wezterm.lua → ${target}"
		else
			fail "wezterm.lua symlink broken → ${target}"
			REQUIRED_FAILURES=$((REQUIRED_FAILURES + 1))
		fi
	elif [[ -f "$conf" ]]; then
		warn "$conf exists but is not a symlink"
	else
		fail "$conf not found (run: mkdir -p ~/.config/wezterm && ln -s $(pwd)/.wezterm.lua $conf)"
		REQUIRED_FAILURES=$((REQUIRED_FAILURES + 1))
	fi
	echo ""
}

check_plugins() {
	echo -e "${BOLD}Plugins${NC}"
	local plugins_dir="${HOME}/.local/share/wezterm/plugins"
	if [[ -d "$plugins_dir" && -n "$(ls -A "$plugins_dir" 2>/dev/null)" ]]; then
		ok "plugins cloned ($plugins_dir)"
	else
		warn "plugins not cloned yet (tabline.wez auto-clones on first wezterm start)"
	fi
	echo ""
}

check_rust_toolchain() {
	echo -e "${BOLD}Rust toolchain${NC} (only needed to build wezterm from source)"
	if have_native_cmd cargo; then
		ok "cargo $($HOME/.cargo/bin/cargo --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
	else
		warn "rustup/cargo not installed (run install.sh to build wezterm)"
	fi
	echo ""
}

# Plugins + Rust toolchain run after the config section, then --install
# hands the whole job over to install.sh (building wezterm needs the full
# toolchain — not a piecemeal install here). Delegation ends the script
# with install.sh's own output and exit status propagated: no summary.
checkhealth_extra() {
	if [ "$WEZTERM_VERSION_FAILED" = 1 ]; then
		REQUIRED_FAILURES=$((REQUIRED_FAILURES + 1))
	fi
	check_plugins
	check_rust_toolchain
	if $INSTALL_MODE && [ "$REQUIRED_FAILURES" -gt 0 ]; then
		local script_dir
		script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
		if [ -f "$script_dir/install.sh" ]; then
			bash "$script_dir/install.sh"
		else
			echo -e "${RED}install.sh not found next to checkhealth.sh — run it from the repo, or see https://wezterm.org/installation${NC}"
			exit 1
		fi
		exit 0
	fi
}

checkhealth_main "$@"
