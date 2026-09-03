#!/usr/bin/env bash
################################################################################
# test_deps.sh - Tests for host dependency detection and install helpers
################################################################################

cd "$(dirname "$0")"
source test_framework.sh

DEBUG_MODE="${DEBUG_MODE:-false}"
source ../src/lib/logging.sh
source ../src/lib/constants.sh
source ../src/lib/deps.sh
source ../src/commands/deps.sh

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

write_os_release() {
	local dest="$1"
	shift
	mkdir -p "$(dirname "$dest")"
	: >"$dest"
	for line in "$@"; do
		printf '%s\n' "$line" >>"$dest"
	done
}

make_fake_bin() {
	local dir="$1"
	local name="$2"
	local script="${3:-exit 0}"
	mkdir -p "$dir"
	printf '#!/bin/sh\n%s\n' "$script" >"${dir}/${name}"
	chmod +x "${dir}/${name}"
}

test_suite "OS family detection"

assert_equals "macos" "$(DEPS_UNAME_OVERRIDE=Darwin deps_os_family)" "Darwin is macos"
assert_equals "linux" "$(DEPS_UNAME_OVERRIDE=Linux deps_os_family)" "Linux is linux"
assert_equals "windows" "$(DEPS_UNAME_OVERRIDE=MINGW64_NT-10.0 deps_os_family)" "MINGW is windows"
assert_equals "windows" "$(DEPS_UNAME_OVERRIDE=CYGWIN_NT-10.0 deps_os_family)" "CYGWIN is windows"
assert_equals "unknown" "$(DEPS_UNAME_OVERRIDE=FreeBSD deps_os_family)" "FreeBSD is unknown"

test_suite "Linux distro from os-release"

UBUNTU_REL="${TEST_ROOT}/ubuntu-os-release"
ALPINE_REL="${TEST_ROOT}/alpine-os-release"
FEDORA_REL="${TEST_ROOT}/fedora-os-release"
ARCH_REL="${TEST_ROOT}/arch-os-release"
SUSE_REL="${TEST_ROOT}/suse-os-release"
MINT_REL="${TEST_ROOT}/mint-os-release"

write_os_release "$UBUNTU_REL" \
	'NAME="Ubuntu"' \
	'VERSION_ID="24.04"' \
	'ID=ubuntu' \
	'ID_LIKE=debian' \
	'PRETTY_NAME="Ubuntu 24.04.1 LTS"'

write_os_release "$ALPINE_REL" \
	'NAME="Alpine Linux"' \
	'ID=alpine' \
	'VERSION_ID="3.20.3"' \
	'PRETTY_NAME="Alpine Linux v3.20"'

write_os_release "$FEDORA_REL" \
	'NAME="Fedora Linux"' \
	'ID=fedora' \
	'VERSION_ID="41"' \
	'PRETTY_NAME="Fedora Linux 41"'

write_os_release "$ARCH_REL" \
	'NAME="Arch Linux"' \
	'ID=arch' \
	'PRETTY_NAME="Arch Linux"'

write_os_release "$SUSE_REL" \
	'NAME="openSUSE Tumbleweed"' \
	'ID="opensuse-tumbleweed"' \
	'ID_LIKE="suse opensuse"' \
	'PRETTY_NAME="openSUSE Tumbleweed"'

write_os_release "$MINT_REL" \
	'ID=linuxmint' \
	'ID_LIKE="ubuntu debian"' \
	'PRETTY_NAME="Linux Mint 22"'

assert_equals "ubuntu" "$(DEPS_OS_RELEASE_FILE="$UBUNTU_REL" deps_linux_id)" "ubuntu ID"
assert_equals "debian" "$(DEPS_OS_RELEASE_FILE="$UBUNTU_REL" deps_linux_id_like)" "ubuntu ID_LIKE"
assert_equals "alpine" "$(DEPS_OS_RELEASE_FILE="$ALPINE_REL" deps_linux_id)" "alpine ID"
assert_equals "fedora" "$(DEPS_OS_RELEASE_FILE="$FEDORA_REL" deps_linux_id)" "fedora ID"
assert_equals "opensuse-tumbleweed" "$(DEPS_OS_RELEASE_FILE="$SUSE_REL" deps_linux_id)" "opensuse ID"

assert_equals "Ubuntu 24.04.1 LTS" \
	"$(DEPS_UNAME_OVERRIDE=Linux DEPS_OS_RELEASE_FILE="$UBUNTU_REL" deps_os_pretty)" \
	"pretty name from PRETTY_NAME"
assert_equals "Alpine Linux v3.20" \
	"$(DEPS_UNAME_OVERRIDE=Linux DEPS_OS_RELEASE_FILE="$ALPINE_REL" deps_os_pretty)" \
	"alpine pretty name"

test_suite "Package manager detection"

BREW_PATH="${TEST_ROOT}/bin-brew"
APT_PATH="${TEST_ROOT}/bin-apt"
APK_PATH="${TEST_ROOT}/bin-apk"
DNF_PATH="${TEST_ROOT}/bin-dnf"
YUM_PATH="${TEST_ROOT}/bin-yum"
PACMAN_PATH="${TEST_ROOT}/bin-pacman"
ZYPPER_PATH="${TEST_ROOT}/bin-zypper"
EMPTY_PATH="${TEST_ROOT}/bin-empty"
mkdir -p "$EMPTY_PATH"

make_fake_bin "$BREW_PATH" brew 'echo "Homebrew 4.4.0"'
make_fake_bin "$APT_PATH" apt-get 'echo "apt 2.7.14 (amd64)"'
make_fake_bin "$APK_PATH" apk 'echo "apk-tools 2.14.4"'
make_fake_bin "$DNF_PATH" dnf 'echo "4.21.1"'
make_fake_bin "$YUM_PATH" yum 'echo "3.4.3"'
make_fake_bin "$PACMAN_PATH" pacman 'echo "Pacman v6.1.0"'
make_fake_bin "$ZYPPER_PATH" zypper 'echo "zypper 1.14.68"'

assert_equals "brew" \
	"$(PATH="$BREW_PATH" DEPS_UNAME_OVERRIDE=Darwin deps_detect_package_manager)" \
	"macOS with brew uses Homebrew"
assert_equals "none" \
	"$(PATH="$EMPTY_PATH" DEPS_UNAME_OVERRIDE=Darwin deps_detect_package_manager)" \
	"macOS without brew reports none"
assert_equals "apt" \
	"$(PATH="$APT_PATH" DEPS_UNAME_OVERRIDE=Linux DEPS_OS_RELEASE_FILE="$UBUNTU_REL" deps_detect_package_manager)" \
	"Ubuntu uses apt"
assert_equals "apt" \
	"$(PATH="$APT_PATH" DEPS_UNAME_OVERRIDE=Linux DEPS_OS_RELEASE_FILE="$MINT_REL" deps_detect_package_manager)" \
	"Linux Mint uses apt"
assert_equals "apk" \
	"$(PATH="$APK_PATH" DEPS_UNAME_OVERRIDE=Linux DEPS_OS_RELEASE_FILE="$ALPINE_REL" deps_detect_package_manager)" \
	"Alpine uses apk"
assert_equals "dnf" \
	"$(PATH="$DNF_PATH" DEPS_UNAME_OVERRIDE=Linux DEPS_OS_RELEASE_FILE="$FEDORA_REL" deps_detect_package_manager)" \
	"Fedora uses dnf"
assert_equals "yum" \
	"$(PATH="$YUM_PATH" DEPS_UNAME_OVERRIDE=Linux DEPS_OS_RELEASE_FILE="$FEDORA_REL" deps_detect_package_manager)" \
	"Fedora falls back to yum"
assert_equals "pacman" \
	"$(PATH="$PACMAN_PATH" DEPS_UNAME_OVERRIDE=Linux DEPS_OS_RELEASE_FILE="$ARCH_REL" deps_detect_package_manager)" \
	"Arch uses pacman"
assert_equals "zypper" \
	"$(PATH="$ZYPPER_PATH" DEPS_UNAME_OVERRIDE=Linux DEPS_OS_RELEASE_FILE="$SUSE_REL" deps_detect_package_manager)" \
	"openSUSE uses zypper"
assert_equals "none" \
	"$(PATH="$EMPTY_PATH" DEPS_UNAME_OVERRIDE=Linux DEPS_OS_RELEASE_FILE="$UBUNTU_REL" deps_detect_package_manager)" \
	"Linux with no manager reports none"
assert_equals "apk" \
	"$(PATH="$APK_PATH" DEPS_UNAME_OVERRIDE=Linux DEPS_OS_RELEASE_FILE="$UBUNTU_REL" deps_detect_package_manager)" \
	"falls back to a manager present on PATH"

assert_equals "Homebrew" "$(deps_package_manager_label brew)" "brew label"
assert_equals "apt" "$(deps_package_manager_label apt)" "apt label"
assert_equals "dnf" "$(deps_package_manager_label dnf)" "dnf label"

test_suite "Install command generation"

assert_equals "brew install lz4 jq" \
	"$(DEPS_EUID_OVERRIDE=1000 deps_pkg_install_cmd brew lz4 jq)" \
	"brew never uses sudo"
assert_equals "apk add --no-cache lz4 jq" \
	"$(DEPS_EUID_OVERRIDE=0 deps_pkg_install_cmd apk lz4 jq)" \
	"apk as root has no sudo"
assert_equals "apt-get update && apt-get install -y curl lz4" \
	"$(DEPS_EUID_OVERRIDE=0 deps_pkg_install_cmd apt curl lz4)" \
	"apt as root has no sudo"
assert_equals "dnf install -y jq" \
	"$(DEPS_EUID_OVERRIDE=0 deps_pkg_install_cmd dnf jq)" \
	"dnf as root"
assert_equals "yum install -y jq" \
	"$(DEPS_EUID_OVERRIDE=0 deps_pkg_install_cmd yum jq)" \
	"yum as root"
assert_equals "pacman -Sy --noconfirm jq" \
	"$(DEPS_EUID_OVERRIDE=0 deps_pkg_install_cmd pacman jq)" \
	"pacman as root"
assert_equals "zypper --non-interactive install jq" \
	"$(DEPS_EUID_OVERRIDE=0 deps_pkg_install_cmd zypper jq)" \
	"zypper as root"

APK_SUDO="$(DEPS_EUID_OVERRIDE=1000 deps_pkg_install_cmd apk lz4)"
assert_contains "$APK_SUDO" "apk add --no-cache lz4" "non-root apk command includes apk add"
if command -v sudo >/dev/null 2>&1; then
	assert_contains "$APK_SUDO" "sudo " "non-root apk command prefixes sudo"
else
	skip_test "sudo not installed — skip sudo prefix assertion"
fi

test_suite "Package names and install methods"

assert_equals "lz4" "$(deps_pkg_name lz4 brew)" "lz4 brew package"
assert_equals "lz4" "$(deps_pkg_name lz4 apt)" "lz4 apt package"
assert_equals "jq" "$(deps_pkg_name jq apk)" "jq apk package"
assert_equals "foundry" "$(deps_pkg_name cast brew)" "cast maps to foundry on brew"
assert_empty "$(deps_pkg_name cast apt)" "cast is not an apt package"
assert_equals "rust" "$(deps_pkg_name rustc brew)" "rustc maps to rust on brew"
assert_empty "$(deps_pkg_name rustc dnf)" "rustc uses rustup off brew"
assert_equals "pkg" "$(deps_install_method curl)" "curl is pkg"
assert_equals "foundry" "$(deps_install_method cast)" "cast is foundry"
assert_equals "rustup" "$(deps_install_method rustc)" "rustc is rustup"
assert_equals "foundry (cast)" "$(deps_tool_label cast)" "cast label"
assert_equals "rust (rustc)" "$(deps_tool_label rustc)" "rustc label"

test_suite "Version parsing"

assert_equals "8.7.1" "$(deps_extract_version 'curl 8.7.1 (x86_64-apple-darwin23.0)')" \
	"parses curl version"
assert_equals "1.9.4" "$(deps_extract_version '*** LZ4 command line interface 64-bits v1.9.4, by Yann Collet ***')" \
	"parses lz4 version"
assert_equals "1.7.1" "$(deps_extract_version 'jq-1.7.1')" "parses jq version"
assert_equals "4.4.0" "$(deps_extract_version 'Homebrew 4.4.0')" "parses Homebrew version"
assert_equals "479" "$(deps_extract_version 'Apple gzip 479')" "parses integer-only Apple gzip version"
assert_equals "1.6.0" "$(deps_extract_version 'cast Version: 1.6.0-stable')" "strips foundry suffix via extract"
assert_empty "$(deps_extract_version '')" "empty raw version"

assert_success 'deps_version_ge 1.6.0 1.6.0' "equal versions"
assert_success 'deps_version_ge 1.7.0 1.6.0' "newer major/minor"
assert_success 'deps_version_ge 1.6.1 1.6.0' "newer patch"
assert_success 'deps_version_ge 1.6.0-stable 1.6.0' "strips -stable suffix"
assert_failure 'deps_version_ge 1.5.9 1.6.0' "older version fails"
assert_failure 'deps_version_ge 1.6.0 1.6.1' "patch behind fails"

if command -v curl >/dev/null 2>&1; then
	curl_ver="$(deps_tool_version curl)"
	assert_not_empty "$curl_ver" "reads installed curl version"
	curl_out="$(deps_check_tool curl 2>&1)"
	assert_contains "$curl_out" "version ${curl_ver}" "logs curl version"
else
	skip_test "curl not installed — skip live version log"
fi

if command -v gzip >/dev/null 2>&1; then
	gzip_ver="$(deps_tool_version gzip)"
	assert_not_empty "$gzip_ver" "reads installed gzip version"
else
	skip_test "gzip not installed — skip live gzip version"
fi

test_suite "Missing-tool detection"

missing_count="$(
	PATH="$EMPTY_PATH"
	DEPS_MISSING=()
	deps_check_all >/dev/null 2>&1 || true
	echo "${#DEPS_MISSING[@]}"
)"
assert_equals "8" "$missing_count" "all eight tools missing when PATH is empty"

csv="$(
	PATH="$EMPTY_PATH"
	DEPS_MISSING=()
	deps_check_all >/dev/null 2>&1 || true
	deps_missing_csv
)"
assert_contains "$csv" "curl" "missing list includes curl"
assert_contains "$csv" "foundry (cast)" "missing list includes foundry"
assert_contains "$csv" "rust (rustc)" "missing list includes rust"

test_suite "Install prompt"

assert_success 'deps_confirm_install true' "--yes skips the prompt"
assert_success 'printf "y\n" | deps_confirm_install false' "y confirms install"
assert_success 'printf "yes\n" | deps_confirm_install false' "yes confirms install"
assert_failure 'printf "n\n" | deps_confirm_install false' "n declines install"
assert_failure 'printf "\n" | deps_confirm_install false' "empty answer declines"

test_suite "Dry-run package install"

dry_out="$(
	export DEPS_DRY_RUN=true
	export DEPS_EUID_OVERRIDE=0
	export DEPS_UNAME_OVERRIDE=Linux
	export DEPS_OS_RELEASE_FILE="$ALPINE_REL"
	export PATH="$APK_PATH"
	DEPS_MISSING=(lz4 jq)
	deps_install_missing 2>&1
)"
assert_contains "$dry_out" "apk add --no-cache lz4 jq" "dry-run logs apk install command"
assert_contains "$dry_out" "Dry run: not executing." "dry-run does not execute"

dry_foundry="$(
	export DEPS_DRY_RUN=true
	export DEPS_UNAME_OVERRIDE=Linux
	export DEPS_OS_RELEASE_FILE="$UBUNTU_REL"
	export PATH="$APT_PATH"
	DEPS_MISSING=(cast)
	deps_install_missing 2>&1
)"
assert_contains "$dry_foundry" "foundryup" "linux foundry dry-run uses foundryup"
assert_contains "$dry_foundry" "$DEPS_FOUNDRY_INSTALL_URL" "logs foundry installer URL"

dry_rust="$(
	export DEPS_DRY_RUN=true
	export DEPS_UNAME_OVERRIDE=Linux
	export DEPS_OS_RELEASE_FILE="$UBUNTU_REL"
	export PATH="$APT_PATH"
	DEPS_MISSING=(rustc)
	deps_install_missing 2>&1
)"
assert_contains "$dry_rust" "rustup" "linux rust dry-run uses rustup"

test_suite "deps command flags"

help_out="$(cmd_deps --help)"
assert_contains "$help_out" "beranode deps" "help mentions command"
assert_contains "$help_out" "--check" "help mentions --check"
assert_contains "$help_out" "--yes" "help mentions --yes"
assert_contains "$help_out" "Homebrew" "help mentions Homebrew"
assert_contains "$help_out" "apk" "help mentions apk"
assert_contains "$help_out" "dnf" "help mentions dnf"

assert_failure 'cmd_deps --bogus' "unknown flag fails"
assert_failure 'cmd_deps --check --yes' "cannot combine --check and --yes"

check_out="$(
	export DEPS_UNAME_OVERRIDE=Linux
	export DEPS_OS_RELEASE_FILE="$ALPINE_REL"
	export PATH="${EMPTY_PATH}:/usr/bin:/bin"
	cmd_deps --check 2>&1 || true
)"
assert_contains "$check_out" "beranode v${BERANODE_VERSION}" "logs CLI version"
assert_contains "$check_out" "Alpine Linux v3.20" "logs distro version"
assert_contains "$check_out" "Check-only mode" "--check does not install"

print_results
