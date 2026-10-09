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

# ──────────────────────── version gate ────────────────────────
# wezterm versions are date-based: "wezterm 20240127-113934-3aa51d5a".
# The config needs 20240127+ (config_builder, plugin API, kitty keyboard);
# the [0-9]{8} regex lifts the date out of the full version string.
MAIN_VERSION="wezterm|ver:20240127|wezterm|none|[0-9]{8}"
MAIN_VERSION_TITLE="wezterm"

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

# wezterm's Platform section is uname only — no package-manager line.
print_platform() {
	echo -e "${BOLD}Platform${NC}"
	echo -e "  OS: ${CYAN}$(uname -s)${NC}"
	echo ""
}

# ──────────────────────── sections ────────────────────────
# src|dst|desc|mode|name|hint — the generic check_config_files covers every
# case the old override handled (broken symlink → fail, plain file → warn,
# missing → fail with the re-link hint).
REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_LINKS=(
	"$REPO_DIR/.wezterm.lua|$HOME/.config/wezterm/wezterm.lua|wezterm.lua|||wezterm.lua not found (run: mkdir -p ~/.config/wezterm && ln -s $REPO_DIR/.wezterm.lua ~/.config/wezterm/wezterm.lua)"
)
# title|note|type|params|ok|incomplete|missing — the trailing "/" in params
# requires a NON-EMPTY directory (a bare plugins/ dir means nothing cloned).
# {ver} in an ok message expands to the tool's first version number.
ADVISORY_SECTIONS=(
	"Plugins||path|$HOME/.local/share/wezterm/plugins/|plugins cloned||plugins not cloned yet (tabline.wez auto-clones on first wezterm start)"
	"Rust toolchain|(only needed to build wezterm from source)|cmd|cargo|cargo {ver}||rustup/cargo not installed (run install.sh to build wezterm)"
)

# --install hands the whole job over to install.sh (building wezterm needs
# the full toolchain — not a piecemeal install here). Delegation ends the
# script with install.sh's own output and exit status propagated: no summary.
checkhealth_extra() {
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
