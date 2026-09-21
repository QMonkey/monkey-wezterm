#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS="[${GREEN}✓${NC}]"
FAIL="[${RED}✗${NC}]"
WARN="[${YELLOW}!${NC}]"

ALL_PASSED=true
INSTALL_MODE=false
SKIP_CONFIG_CHECKS=false

usage() {
	cat <<EOF
Usage: $0 [OPTIONS]

Check and optionally install dependencies for monkey-wezterm.

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

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
		-i | --install) INSTALL_MODE=true ;;
		--skip-check-config) SKIP_CONFIG_CHECKS=true ;;
		-h | --help) usage ;;
		*)
			echo "Unknown option: $1"
			usage
			;;
		esac
		shift
	done
}

# ──────────────────────────── helpers ────────────────────────────

# WSL interop appends the WINDOWS PATH to ours, so tools installed on the
# Windows side appear as /mnt/c/... shims. They are NOT Linux binaries.
# Treat /mnt/* resolutions as "not installed".
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

# wezterm versions are date-based: "wezterm 20240127-113934-3aa51d5a".
# The config needs 20240127+ (config_builder, plugin API, kitty keyboard).
wezterm_at_least() {
	have_native_cmd wezterm || return 1
	local ver
	ver=$(wezterm --version 2>/dev/null | grep -oE '[0-9]{8}' | head -1)
	[[ -z "$ver" ]] && return 1
	((ver >= 20240127))
}

os_detect() {
	case "$(uname -s)" in
	Linux) echo "linux" ;;
	Darwin) echo "macos" ;;
	*) echo "unknown" ;;
	esac
}

# ──────────────────── phases ────────────────────────────

print_header() {
	echo -e "${BOLD}monkey-wezterm dependency check${NC}"
	echo ""
}

print_wezterm_version() {
	echo -e "${BOLD}wezterm${NC}"
	if wezterm_at_least; then
		echo -e "  ${PASS} $(wezterm --version 2>/dev/null | head -1)"
	else
		if have_native_cmd wezterm; then
			echo -e "  ${FAIL} $(wezterm --version 2>/dev/null | head -1) (need >= 20240127 for config_builder / plugin API)"
		else
			echo -e "  ${FAIL} wezterm (not found)"
		fi
		ALL_PASSED=false
	fi
	echo ""
}

print_platform() {
	echo -e "${BOLD}Platform${NC}"
	echo -e "  OS: ${CYAN}$(uname -s)${NC}"
	echo ""
}

check_config_files() {
	# --skip-check-config (passed by install.sh): the config symlinks are
	# the installer's job, and judging them here would misreport a state
	# the installer is about to create. Standalone runs (the manual
	# diagnosis entry point) still get the full check.
	if $SKIP_CONFIG_CHECKS; then
		echo -e "  ${WARN} config checks skipped (handled by the installer)"
		return 0
	fi
	echo -e "${BOLD}Config files${NC}"
	local conf="${HOME}/.config/wezterm/wezterm.lua"
	if [[ -L "$conf" ]]; then
		local target
		target=$(readlink -f "$conf" 2>/dev/null || readlink "$conf")
		if [[ -f "$target" ]]; then
			echo -e "  ${PASS} wezterm.lua → ${target}"
		else
			echo -e "  ${FAIL} wezterm.lua symlink broken → ${target}"
			ALL_PASSED=false
		fi
	elif [[ -f "$conf" ]]; then
		echo -e "  ${WARN} $conf exists but is not a symlink"
	else
		echo -e "  ${FAIL} $conf not found (run: mkdir -p ~/.config/wezterm && ln -s $(pwd)/.wezterm.lua $conf)"
		ALL_PASSED=false
	fi
	echo ""
}

check_plugins() {
	echo -e "${BOLD}Plugins${NC}"
	local plugins_dir="${HOME}/.local/share/wezterm/plugins"
	if [[ -d "$plugins_dir" && -n "$(ls -A "$plugins_dir" 2>/dev/null)" ]]; then
		echo -e "  ${PASS} plugins cloned ($plugins_dir)"
	else
		echo -e "  ${WARN} plugins not cloned yet (tabline.wez auto-clones on first wezterm start)"
	fi
	echo ""
}

check_rust_toolchain() {
	echo -e "${BOLD}Rust toolchain${NC} (only needed to build wezterm from source)"
	if have_native_cmd cargo; then
		echo -e "  ${PASS} cargo $($HOME/.cargo/bin/cargo --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
	else
		echo -e "  ${WARN} rustup/cargo not installed (run install.sh to build wezterm)"
	fi
	echo ""
}

print_summary() {
	if $ALL_PASSED; then
		echo -e "${GREEN}${BOLD}All required dependencies satisfied.${NC}"
		exit 0
	else
		echo -e "${RED}${BOLD}Some required dependencies are missing.${NC}"
		if ! $INSTALL_MODE; then
			echo -e "Run ${CYAN}$0 --install${NC} to install them automatically."
		fi
		exit 1
	fi
}

# ──────────────────── main ────────────────────

main() {
	parse_args "$@"
	print_header
	print_wezterm_version
	print_platform
	check_config_files
	check_plugins
	check_rust_toolchain
	if $INSTALL_MODE && ! $ALL_PASSED; then
		# The only hard dependency is wezterm itself, and building it needs
		# the full toolchain — that is install.sh's job, not a piecemeal
		# install here.
		local script_dir
		script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
		if [ -f "$script_dir/install.sh" ]; then
			bash "$script_dir/install.sh"
		else
			echo -e "${RED}install.sh not found next to checkhealth.sh — run it from the repo, or see https://wezterm.org/installation${NC}"
			exit 1
		fi
		return 0
	fi
	print_summary
}

main "$@"
