#!/usr/bin/env bash
set -euo pipefail
################################################################################
# deps.sh - Check and install host dependencies
################################################################################
#
# Usage:
#   beranode deps              Check tools; prompt to install anything missing
#   beranode deps --check      Check only (exit 1 if anything is missing)
#   beranode deps --yes        Install missing tools without prompting
#
################################################################################

: "${DEBUG_MODE:=false}"

show_deps_help() {
	cat <<EOF
beranode deps - Check and install host dependencies

USAGE:
    beranode deps [OPTIONS]

OPTIONS:
    --check          Detect OS, package manager, and tools; log versions;
                     do not install (exit 1 if anything is missing)
    --yes, -y        Install missing tools locally without prompting
    --help, -h       Display this help message

DESCRIPTION:
    Detects macOS vs Linux (including distro from /etc/os-release) and the
    local package manager:

      macOS:  Homebrew (brew)
      Linux:  apt, apk, dnf, yum, pacman, zypper

    Required tools (logged with version when present):

      curl, wget, gzip, tar, lz4, jq
      foundry (cast)  >= ${SUPPORTED_CAST_VERSION}
      rust (rustc)

    Missing packages are installed with the detected manager. Foundry and
    Rust use Homebrew formulae when brew is available; otherwise they are
    installed into the user home directory with foundryup (~/.foundry) and
    rustup (~/.cargo).

EXAMPLES:
    beranode deps
    beranode deps --check
    beranode deps --yes

EXIT STATUS:
    0    All required tools are present (and meet min versions)
    1    Missing tools, user declined install, or install failed
EOF
}

cmd_deps() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: cmd_deps" >&2

	local check_only=false
	local assume_yes=false

	while [[ $# -gt 0 ]]; do
		case "$1" in
		--help | -h)
			show_deps_help
			return 0
			;;
		--check)
			check_only=true
			shift
			;;
		--yes | -y)
			assume_yes=true
			shift
			;;
		*)
			log_error "Unknown option: $1"
			echo ""
			show_deps_help
			return 1
			;;
		esac
	done

	if [[ "$check_only" == "true" && "$assume_yes" == "true" ]]; then
		log_error "Cannot combine --check and --yes."
		return 1
	fi

	deps_ensure "$check_only" "$assume_yes"
}
