#!/usr/bin/env bash
set -euo pipefail
################################################################################
# deps.sh - Host dependency detection and local install
################################################################################
#
# Detects the OS (macOS / Linux distro) and package manager (Homebrew, apt,
# apk, dnf, yum, pacman, zypper), checks tools the CLI needs, logs each
# version, and can install missing ones locally after a prompt.
#
# Install methods:
#   - Package manager for curl, wget, gzip, tar, lz4, jq
#   - Homebrew formulae, or foundryup (~/.foundry) for Foundry/cast
#   - Homebrew formulae, or rustup (~/.cargo) for Rust
#
# Test overrides (optional):
#   DEPS_UNAME_OVERRIDE, DEPS_OS_RELEASE_FILE, DEPS_EUID_OVERRIDE, DEPS_DRY_RUN
#
################################################################################

: "${DEBUG_MODE:=false}"

readonly DEPS_FOUNDRY_INSTALL_URL="https://foundry.paradigm.xyz"
readonly DEPS_RUSTUP_INSTALL_URL="https://sh.rustup.rs"

# Populated by deps_check_all: tool ids that are missing or too old.
DEPS_MISSING=()

################################################################################
# Platform
################################################################################

deps_uname() {
	echo "${DEPS_UNAME_OVERRIDE:-$(uname -s)}"
}

deps_arch() {
	echo "${DEPS_ARCH_OVERRIDE:-$(uname -m)}"
}

# Prints: macos | linux | windows | unknown
deps_os_family() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: deps_os_family" >&2

	case "$(deps_uname)" in
	Darwin) echo macos ;;
	Linux) echo linux ;;
	MINGW* | CYGWIN* | MSYS*) echo windows ;;
	*) echo unknown ;;
	esac
}

deps_os_release_field() {
	local key="$1"
	local file="${DEPS_OS_RELEASE_FILE:-/etc/os-release}"
	local line=""
	local value=""

	[[ -f "$file" ]] || return 0
	while IFS= read -r line || [[ -n "$line" ]]; do
		case "$line" in
		"${key}="*)
			value="${line#*=}"
			value="${value%\"}"
			value="${value#\"}"
			value="${value%\'}"
			value="${value#\'}"
			echo "$value"
			return 0
			;;
		esac
	done <"$file"
}

deps_to_lower() {
	local s="${1:-}"
	if command -v tr >/dev/null 2>&1; then
		printf '%s' "$s" | tr '[:upper:]' '[:lower:]'
	else
		printf '%s' "$s"
	fi
}

deps_linux_id() {
	deps_to_lower "$(deps_os_release_field ID)"
}

deps_linux_id_like() {
	deps_to_lower "$(deps_os_release_field ID_LIKE)"
}

# Human-readable OS string, including distro / macOS version when available.
deps_os_pretty() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: deps_os_pretty" >&2

	local family pretty version_id
	family="$(deps_os_family)"
	case "$family" in
	macos)
		if command -v sw_vers >/dev/null 2>&1; then
			pretty="$(sw_vers -productName 2>/dev/null || true)"
			version_id="$(sw_vers -productVersion 2>/dev/null || true)"
			if [[ -n "$pretty" && -n "$version_id" ]]; then
				echo "${pretty} ${version_id}"
				return 0
			fi
		fi
		echo "macOS"
		;;
	linux)
		pretty="$(deps_os_release_field PRETTY_NAME)"
		if [[ -n "$pretty" ]]; then
			echo "$pretty"
			return 0
		fi
		echo "Linux"
		;;
	windows)
		echo "Windows"
		;;
	*)
		echo "$(deps_uname)"
		;;
	esac
}

################################################################################
# Package manager
################################################################################

deps_euid() {
	echo "${DEPS_EUID_OVERRIDE:-$(id -u)}"
}

# Prints sudo prefix including trailing space, or empty when already root.
deps_sudo_prefix() {
	if [[ "$(deps_euid)" -eq 0 ]]; then
		echo ""
		return 0
	fi
	if command -v sudo >/dev/null 2>&1; then
		echo "sudo "
		return 0
	fi
	echo ""
}

# Echoes the manager name if `bin` is on PATH. Used by deps_detect_package_manager.
deps_mgr_if_present() {
	local name="$1"
	local bin="$2"
	if command -v "$bin" >/dev/null 2>&1; then
		echo "$name"
		return 0
	fi
	return 1
}

# Prints: brew | apt | apk | dnf | yum | pacman | zypper | none
deps_detect_package_manager() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: deps_detect_package_manager" >&2

	local family distro like

	family="$(deps_os_family)"
	if [[ "$family" == "macos" ]]; then
		if command -v brew >/dev/null 2>&1; then
			echo brew
		else
			echo none
		fi
		return 0
	fi

	if [[ "$family" != "linux" ]]; then
		echo none
		return 0
	fi

	distro="$(deps_linux_id)"
	like="$(deps_linux_id_like)"

	case "$distro" in
	debian | ubuntu | linuxmint | pop | raspbian | elementary | zorin)
		deps_mgr_if_present apt apt-get && return 0
		;;
	alpine)
		deps_mgr_if_present apk apk && return 0
		;;
	fedora | rhel | centos | rocky | almalinux | ol | amzn | mageia)
		deps_mgr_if_present dnf dnf && return 0
		deps_mgr_if_present yum yum && return 0
		;;
	arch | manjaro | endeavouros | garuda)
		deps_mgr_if_present pacman pacman && return 0
		;;
	opensuse* | sles | sled)
		deps_mgr_if_present zypper zypper && return 0
		;;
	esac

	case " $like " in
	*" debian "* | *" ubuntu "*)
		deps_mgr_if_present apt apt-get && return 0
		;;
	*" rhel "* | *" fedora "* | *" centos "*)
		deps_mgr_if_present dnf dnf && return 0
		deps_mgr_if_present yum yum && return 0
		;;
	*" suse "* | *" opensuse "*)
		deps_mgr_if_present zypper zypper && return 0
		;;
	*" arch "*)
		deps_mgr_if_present pacman pacman && return 0
		;;
	*" alpine "*)
		deps_mgr_if_present apk apk && return 0
		;;
	esac

	deps_mgr_if_present apt apt-get && return 0
	deps_mgr_if_present apk apk && return 0
	deps_mgr_if_present dnf dnf && return 0
	deps_mgr_if_present yum yum && return 0
	deps_mgr_if_present pacman pacman && return 0
	deps_mgr_if_present zypper zypper && return 0

	echo none
}

deps_package_manager_label() {
	case "${1:-}" in
	brew) echo "Homebrew" ;;
	apt) echo "apt" ;;
	apk) echo "apk" ;;
	dnf) echo "dnf" ;;
	yum) echo "yum" ;;
	pacman) echo "pacman" ;;
	zypper) echo "zypper" ;;
	none) echo "none" ;;
	*) echo "${1:-unknown}" ;;
	esac
}

deps_package_manager_version() {
	local mgr="${1:-}"
	local raw=""

	case "$mgr" in
	brew)
		raw="$(brew --version 2>/dev/null | head -1 || true)"
		;;
	apt)
		raw="$(apt-get --version 2>/dev/null | head -1 || true)"
		;;
	apk)
		raw="$(apk --version 2>/dev/null | head -1 || true)"
		;;
	dnf)
		raw="$(dnf --version 2>/dev/null | head -1 || true)"
		;;
	yum)
		raw="$(yum --version 2>/dev/null | head -1 || true)"
		;;
	pacman)
		raw="$(pacman -V 2>/dev/null | head -1 || true)"
		;;
	zypper)
		raw="$(zypper --version 2>/dev/null | head -1 || true)"
		;;
	*)
		echo ""
		return 0
		;;
	esac

	deps_extract_version "$raw"
}

################################################################################
# Versions
################################################################################

# First X.Y / X.Y.Z token, or a lone integer (Apple gzip reports "479").
deps_extract_version() {
	local raw="${1:-}"
	local ver=""

	[[ -n "$raw" ]] || {
		echo ""
		return 0
	}
	ver="$(printf '%s\n' "$raw" | grep -oE '[0-9]+\.[0-9]+([.][0-9]+)*' | head -1 || true)"
	if [[ -z "$ver" ]]; then
		ver="$(printf '%s\n' "$raw" | grep -oE '[0-9]+' | head -1 || true)"
	fi
	echo "$ver"
}

# Returns 0 if $1 >= $2 (numeric dotted versions). Missing components count as 0.
deps_version_ge() {
	local v1="${1:-0}"
	local v2="${2:-0}"
	local i=0
	local n1=0
	local n2=0
	local -a ver1
	local -a ver2

	v1="${v1%%-*}"
	v2="${v2%%-*}"
	[[ "$v1" == "$v2" ]] && return 0

	IFS='.' read -r -a ver1 <<<"$v1"
	IFS='.' read -r -a ver2 <<<"$v2"

	for ((i = ${#ver1[@]}; i < ${#ver2[@]}; i++)); do
		ver1[i]=0
	done

	for ((i = 0; i < ${#ver1[@]}; i++)); do
		n1="${ver1[i]:-0}"
		n2="${ver2[i]:-0}"
		[[ "$n1" =~ ^[0-9]+$ ]] || n1=0
		[[ "$n2" =~ ^[0-9]+$ ]] || n2=0
		if ((10#$n1 > 10#$n2)); then
			return 0
		elif ((10#$n1 < 10#$n2)); then
			return 1
		fi
	done
	return 0
}

deps_tool_version_raw() {
	local tool="$1"

	case "$tool" in
	curl) curl --version 2>&1 | head -1 || true ;;
	wget) wget --version 2>&1 | head -1 || true ;;
	gzip) gzip --version 2>&1 | head -1 || true ;;
	tar) tar --version 2>&1 | head -1 || true ;;
	lz4)
		lz4 --version 2>&1 | head -1 || lz4 -V 2>&1 | head -1 || true
		;;
	jq) jq --version 2>&1 | head -1 || true ;;
	cast) cast --version 2>&1 | head -1 || true ;;
	rustc) rustc --version 2>&1 | head -1 || true ;;
	bash) bash --version 2>&1 | head -1 || true ;;
	*) "${tool}" --version 2>&1 | head -1 || true ;;
	esac
}

deps_tool_version() {
	local tool="$1"
	local raw=""
	local ver=""

	raw="$(deps_tool_version_raw "$tool")"
	if [[ "$tool" == "cast" ]]; then
		# "cast Version: 1.6.0-stable" or "cast 1.6.0 (abc 2024-01-01)"
		ver="$(printf '%s\n' "$raw" | awk '{print $3}')"
		ver="${ver%%-*}"
		ver="$(deps_extract_version "$ver")"
		if [[ -z "$ver" ]]; then
			ver="$(deps_extract_version "$raw")"
		fi
		echo "$ver"
		return 0
	fi
	deps_extract_version "$raw"
}

deps_is_installed() {
	command -v "$1" >/dev/null 2>&1
}

deps_tool_label() {
	case "$1" in
	cast) echo "foundry (cast)" ;;
	rustc) echo "rust (rustc)" ;;
	*) echo "$1" ;;
	esac
}

# pkg | foundry | rustup
deps_install_method() {
	case "$1" in
	cast) echo foundry ;;
	rustc) echo rustup ;;
	*) echo pkg ;;
	esac
}

# Package name for a tool on a given manager (empty if not installable that way).
deps_pkg_name() {
	local tool="$1"
	local mgr="$2"

	case "$tool" in
	curl | wget | gzip | tar | lz4 | jq)
		echo "$tool"
		;;
	cast)
		if [[ "$mgr" == "brew" ]]; then
			echo "foundry"
		else
			echo ""
		fi
		;;
	rustc)
		if [[ "$mgr" == "brew" ]]; then
			echo "rust"
		else
			echo ""
		fi
		;;
	*)
		echo ""
		;;
	esac
}

################################################################################
# Install command generation
################################################################################

# Prints the shell command used to install the given packages (not executed).
# Remaining args are package names.
deps_pkg_install_cmd() {
	local mgr="$1"
	shift
	local sudo_pfx=""
	local pkgs=""

	if [[ $# -eq 0 ]]; then
		echo ""
		return 0
	fi
	pkgs="$*"
	sudo_pfx="$(deps_sudo_prefix)"

	case "$mgr" in
	brew)
		echo "brew install ${pkgs}"
		;;
	apt)
		echo "${sudo_pfx}apt-get update && ${sudo_pfx}apt-get install -y ${pkgs}"
		;;
	apk)
		echo "${sudo_pfx}apk add --no-cache ${pkgs}"
		;;
	dnf)
		echo "${sudo_pfx}dnf install -y ${pkgs}"
		;;
	yum)
		echo "${sudo_pfx}yum install -y ${pkgs}"
		;;
	pacman)
		echo "${sudo_pfx}pacman -Sy --noconfirm ${pkgs}"
		;;
	zypper)
		echo "${sudo_pfx}zypper --non-interactive install ${pkgs}"
		;;
	*)
		echo ""
		;;
	esac
}

################################################################################
# Check / log
################################################################################

deps_log_platform() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: deps_log_platform" >&2

	local family pretty arch mgr mgr_label mgr_ver bash_ver bash_path

	family="$(deps_os_family)"
	pretty="$(deps_os_pretty)"
	arch="$(deps_arch)"
	mgr="$(deps_detect_package_manager)"
	mgr_label="$(deps_package_manager_label "$mgr")"
	mgr_ver="$(deps_package_manager_version "$mgr")"

	log_info "beranode v${BERANODE_VERSION}"
	log_info "Platform: ${pretty} (${family}/${arch})"

	bash_path="$(command -v bash 2>/dev/null || echo bash)"
	bash_ver="$(deps_tool_version bash)"
	if [[ -n "$bash_ver" ]]; then
		log_info "bash version ${bash_ver} (${bash_path})"
	else
		log_info "bash (${bash_path})"
	fi

	if [[ "$mgr" == "none" ]]; then
		if [[ "$family" == "macos" ]]; then
			log_warn "Homebrew is not installed. Install it from https://brew.sh to manage packages on macOS."
		elif [[ "$family" == "linux" ]]; then
			log_warn "No supported Linux package manager found (apt, apk, dnf, yum, pacman, zypper)."
		elif [[ "$family" == "windows" ]]; then
			log_error "Windows is not supported. Use macOS or Linux."
		else
			log_warn "Unsupported platform: $(deps_uname)"
		fi
	elif [[ -n "$mgr_ver" ]]; then
		log_info "Package manager: ${mgr_label} version ${mgr_ver}"
	else
		log_info "Package manager: ${mgr_label}"
	fi
}

deps_check_tool() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: deps_check_tool" >&2

	local tool="$1"
	local label path ver min_ver

	label="$(deps_tool_label "$tool")"

	if ! deps_is_installed "$tool"; then
		log_warn "${label} is not installed"
		DEPS_MISSING+=("$tool")
		return 1
	fi

	path="$(command -v "$tool")"
	ver="$(deps_tool_version "$tool")"
	if [[ -n "$ver" ]]; then
		log_success "Found ${label} version ${ver} (${path})"
	else
		log_success "Found ${label} (${path})"
	fi

	if [[ "$tool" == "cast" ]]; then
		min_ver="${SUPPORTED_CAST_VERSION}"
		if [[ -z "$ver" ]] || ! deps_version_ge "$ver" "$min_ver"; then
			log_warn "cast version ${ver:-unknown} is older than required ${min_ver}"
			DEPS_MISSING+=("$tool")
			return 1
		fi
	fi
	return 0
}

# Logs every required tool and fills DEPS_MISSING. Returns 0 if all present.
deps_check_all() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: deps_check_all" >&2

	local tool
	DEPS_MISSING=()

	for tool in curl wget gzip tar lz4 jq cast rustc; do
		deps_check_tool "$tool" || true
	done

	if [[ ${#DEPS_MISSING[@]} -eq 0 ]]; then
		return 0
	fi
	return 1
}

deps_missing_csv() {
	local i
	local out=""
	if [[ ${#DEPS_MISSING[@]} -eq 0 ]]; then
		echo ""
		return 0
	fi
	for i in "${DEPS_MISSING[@]}"; do
		if [[ -z "$out" ]]; then
			out="$(deps_tool_label "$i")"
		else
			out="${out}, $(deps_tool_label "$i")"
		fi
	done
	echo "$out"
}

################################################################################
# Prompt + install
################################################################################

deps_confirm_install() {
	local assume_yes="${1:-false}"
	local answer=""

	if [[ "$assume_yes" == "true" ]]; then
		return 0
	fi

	if ! read -r -p "Do you want to install missing dependencies locally? (y/n) " answer; then
		log_error "No input available. Re-run with --yes to install, or install the tools manually."
		return 1
	fi

	case "$answer" in
	y | Y | yes | YES)
		return 0
		;;
	*)
		log_warn "Skipping install."
		return 1
		;;
	esac
}

deps_run() {
	local cmd="$1"

	log_info "Running: ${cmd}"
	if [[ "${DEPS_DRY_RUN:-false}" == "true" ]]; then
		log_info "Dry run: not executing."
		return 0
	fi
	# shellcheck disable=SC2086
	eval "$cmd"
}

deps_install_foundry() {
	local mgr="$1"
	local cmd=""

	if [[ "$mgr" == "brew" ]]; then
		cmd="$(deps_pkg_install_cmd brew foundry)"
		deps_run "$cmd" || return 1
	else
		log_info "Installing Foundry locally to ~/.foundry via foundryup"
		log_info "Installer: ${DEPS_FOUNDRY_INSTALL_URL}"
		if [[ "${DEPS_DRY_RUN:-false}" == "true" ]]; then
			log_info "Dry run: curl -L ${DEPS_FOUNDRY_INSTALL_URL} | bash"
			log_info "Dry run: foundryup"
			return 0
		fi
		if ! deps_is_installed curl; then
			log_error "curl is required to install Foundry via foundryup."
			return 1
		fi
		curl -L "${DEPS_FOUNDRY_INSTALL_URL}" | bash
		export PATH="${HOME}/.foundry/bin:${PATH}"
		hash -r 2>/dev/null || true
		if command -v foundryup >/dev/null 2>&1; then
			foundryup
		elif [[ -x "${HOME}/.foundry/bin/foundryup" ]]; then
			"${HOME}/.foundry/bin/foundryup"
		else
			log_error "foundryup was not found after the installer ran."
			return 1
		fi
		log_info "Add Foundry to PATH in new shells: export PATH=\"\$HOME/.foundry/bin:\$PATH\""
	fi
	export PATH="${HOME}/.foundry/bin:${PATH}"
	hash -r 2>/dev/null || true
	return 0
}

deps_install_rust() {
	local mgr="$1"
	local cmd=""

	if [[ "$mgr" == "brew" ]]; then
		cmd="$(deps_pkg_install_cmd brew rust)"
		deps_run "$cmd" || return 1
	else
		log_info "Installing Rust locally to ~/.cargo via rustup"
		log_info "Installer: ${DEPS_RUSTUP_INSTALL_URL}"
		if [[ "${DEPS_DRY_RUN:-false}" == "true" ]]; then
			log_info "Dry run: curl --proto '=https' --tlsv1.2 -sSf ${DEPS_RUSTUP_INSTALL_URL} | sh -s -- -y"
			return 0
		fi
		if ! deps_is_installed curl; then
			log_error "curl is required to install Rust via rustup."
			return 1
		fi
		curl --proto '=https' --tlsv1.2 -sSf "${DEPS_RUSTUP_INSTALL_URL}" | sh -s -- -y
		# shellcheck disable=SC1091
		if [[ -f "${HOME}/.cargo/env" ]]; then
			# shellcheck source=/dev/null
			source "${HOME}/.cargo/env"
		fi
		export PATH="${HOME}/.cargo/bin:${PATH}"
		log_info "Add Rust to PATH in new shells: source \"\$HOME/.cargo/env\""
	fi
	export PATH="${HOME}/.cargo/bin:${PATH}"
	hash -r 2>/dev/null || true
	return 0
}

# Installs tools listed in DEPS_MISSING using the detected package manager
# plus foundryup/rustup when needed.
deps_install_missing() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: deps_install_missing" >&2

	local mgr tool method pkg
	local pkg_list=""
	local need_foundry=false
	local need_rust=false
	local cmd=""
	local failed=0

	mgr="$(deps_detect_package_manager)"

	for tool in "${DEPS_MISSING[@]}"; do
		method="$(deps_install_method "$tool")"
		case "$method" in
		foundry) need_foundry=true ;;
		rustup) need_rust=true ;;
		pkg)
			pkg="$(deps_pkg_name "$tool" "$mgr")"
			if [[ -n "$pkg" ]]; then
				if [[ -z "$pkg_list" ]]; then
					pkg_list="$pkg"
				else
					pkg_list="${pkg_list} ${pkg}"
				fi
			else
				log_error "No package mapping for $(deps_tool_label "$tool") on ${mgr}."
				failed=1
			fi
			;;
		esac
	done

	if [[ -n "$pkg_list" ]]; then
		if [[ "$mgr" == "none" ]]; then
			log_error "Cannot install packages (${pkg_list}): no package manager detected."
			if [[ "$(deps_os_family)" == "macos" ]]; then
				log_error "Install Homebrew from https://brew.sh then re-run: beranode deps"
			fi
			failed=1
		else
			cmd="$(deps_pkg_install_cmd "$mgr" $pkg_list)"
			if [[ -z "$cmd" ]]; then
				log_error "Do not know how to install packages with ${mgr}."
				failed=1
			elif ! deps_run "$cmd"; then
				log_error "Package install failed: ${cmd}"
				failed=1
			fi
		fi
	fi

	# Foundry/rust installers need curl; install packages first.
	if [[ "$need_foundry" == "true" ]]; then
		if ! deps_install_foundry "$mgr"; then
			failed=1
		fi
	fi
	if [[ "$need_rust" == "true" ]]; then
		if ! deps_install_rust "$mgr"; then
			failed=1
		fi
	fi

	return "$failed"
}

# Full check (+ optional install). check_only=true skips the prompt/install.
# assume_yes=true skips the prompt.
deps_ensure() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: deps_ensure" >&2

	local check_only="${1:-false}"
	local assume_yes="${2:-false}"
	local family

	print_header "Checking Dependencies"
	deps_log_platform

	family="$(deps_os_family)"
	if [[ "$family" == "windows" || "$family" == "unknown" ]]; then
		log_error "beranode requires macOS or Linux."
		return 1
	fi

	echo ""
	if deps_check_all; then
		log_success "All required dependencies are installed."
		return 0
	fi

	echo ""
	log_warn "Missing or outdated: $(deps_missing_csv)"

	if [[ "$check_only" == "true" ]]; then
		log_info "Check-only mode: not installing. Re-run 'beranode deps' to install."
		return 1
	fi

	echo ""
	log_info "Installs use the local package manager, plus foundryup/rustup when needed."
	if ! deps_confirm_install "$assume_yes"; then
		return 1
	fi

	echo ""
	print_header "Installing Dependencies"
	if ! deps_install_missing; then
		log_error "Some installs failed. See messages above."
	fi

	echo ""
	print_header "Re-checking Dependencies"
	DEPS_MISSING=()
	hash -r 2>/dev/null || true
	if deps_check_all; then
		log_success "All required dependencies are installed."
		return 0
	fi

	log_error "Still missing or outdated: $(deps_missing_csv)"
	log_error "Install those tools manually, then re-run 'beranode deps --check'."
	return 1
}
