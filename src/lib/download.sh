# =============================================================================
# Download Module - Binary Download Utilities
# =============================================================================

################################################################################
# Helper: fetch_github_release
# Description: Fetches GitHub release information and validates response
#
# Arguments:
#   $1 - release_url: Full GitHub API release URL
#
# Returns:
#   0 - Success (prints response body)
#   1 - Failure (404, invalid JSON, or missing version)
################################################################################
fetch_github_release() {
	local release_url="$1"

	# Logs must go to stderr: callers capture stdout as the JSON body.
	log_info "Checking binary from: $release_url" >&2

	# Check if the URL doesn't return a 404 before using it
	local response=$(curl -s -w "\n%{http_code}" "$release_url")
	local http_status=$(echo "$response" | tail -n1)
	local response_body=$(echo "$response" | sed '$d')

	if [[ "$http_status" == "404" ]]; then
		log_error "Release URL not found (404): $release_url"
		return 1
	fi

	# Check if the response is valid JSON (for GitHub API)
	if ! printf '%s\n' "$response_body" | jq . >/dev/null 2>&1; then
		log_error "Response from $release_url is not valid JSON."
		return 1
	fi

	local version=$(printf '%s\n' "$response_body" | jq -r '.tag_name')
	if [[ "$version" == "null" ]]; then
		log_error "Failed to get version from response"
		return 1
	fi

	log_info "Using version: $version" >&2
	printf '%s\n' "$response_body"
	return 0
}

################################################################################
# Helper: detect_platform_arch
# Description: Detects platform and architecture string
#
# Returns:
#   0 - Success (prints arch string like "darwin-arm64")
#   1 - Failure (unsupported platform)
################################################################################
detect_platform_arch() {
	local arch="unknown"

	if [[ "$IS_MACOS" == true ]]; then
		arch="darwin-arm64"
	elif [[ "$IS_LINUX" == true ]]; then
		if [[ "$IS_LINUX_ARM" == true ]]; then
			arch="linux-arm64"
		else
			arch="linux-amd64"
		fi
	else
		log_error "Unsupported platform: $PLATFORM - $ARCH"
		return 1
	fi

	echo "$arch"
	return 0
}

################################################################################
# Helper: release_asset_name_patterns
# Description: Asset-name substrings for a CLI platform arch.
#              beacond (Go) uses GOOS-GOARCH (darwin-arm64, linux-amd64).
#              bera-reth (Rust) uses cargo target triples
#              (aarch64-apple-darwin, x86_64-unknown-linux-gnu).
#
# Arguments:
#   $1 - arch: Architecture string from detect_platform_arch
#
# Returns:
#   0 - Success (prints space-separated substrings, Go-style first)
################################################################################
release_asset_name_patterns() {
	local arch="$1"

	case "$arch" in
	darwin-arm64)
		echo "darwin-arm64 aarch64-apple-darwin"
		;;
	linux-arm64)
		echo "linux-arm64 aarch64-unknown-linux-gnu"
		;;
	linux-amd64)
		echo "linux-amd64 x86_64-unknown-linux-gnu"
		;;
	*)
		echo "$arch"
		;;
	esac
	return 0
}

################################################################################
# Helper: isolate_json_object
# Description: Returns the first JSON object in a payload. Callers that capture
#              fetch_github_release may prefix the body with [INFO] log lines;
#              jq then treats "[INFO]" as an array and fails with
#              "Invalid numeric literal at line 1, column 2".
################################################################################
isolate_json_object() {
	local payload="$1"

	if [[ "$payload" == *"{"* ]]; then
		printf '%s\n' "${payload#"${payload%%\{*}"}"
	else
		printf '%s\n' "$payload"
	fi
}

################################################################################
# Helper: extract_download_url
# Description: Extracts binary download URL from GitHub release response.
#              Matches both Go (darwin-arm64) and Rust (aarch64-apple-darwin)
#              asset naming conventions used by beacond and bera-reth.
#
# Arguments:
#   $1 - response_body: GitHub API response JSON
#   $2 - arch: Architecture string (e.g., "darwin-arm64")
#
# Returns:
#   0 - Success (prints download URL)
#   1 - Failure (no URL found)
################################################################################
extract_download_url() {
	local response_body="$1"
	local arch="$2"
	local pattern download_url=""
	local json
	json=$(isolate_json_object "$response_body")

	local patterns
	patterns=$(release_asset_name_patterns "$arch")

	for pattern in $patterns; do
		download_url=$(printf '%s\n' "$json" | jq -r --arg pattern "$pattern" \
			'[.assets[]? | select(.name | type == "string" and contains($pattern) and endswith(".tar.gz")) | .browser_download_url][0] // empty' 2>/dev/null) || download_url=""
		if [[ -n "$download_url" && "$download_url" != "null" ]]; then
			printf '%s\n' "$download_url"
			return 0
		fi
	done

	log_error "No download URL found for the required binary for '$arch'."
	return 1
}

################################################################################
# Helper: download_and_extract_binary
# Description: Downloads and extracts a binary tarball
#
# Arguments:
#   $1 - download_url: URL to download from
#   $2 - bin_dir: Directory to extract to
#   $3 - binary_name: Name for the final binary
#
# Returns:
#   0 - Success
#   1 - Failure (download or extraction failed)
################################################################################
download_and_extract_binary() {
	local download_url="$1"
	local bin_dir="$2"
	local binary_name="$3"

	# Ensure the bin directory exists
	ensure_dir_exists "$bin_dir" "binary directory: $bin_dir"

	log_info "Downloading $binary_name from $download_url"

	local tar_file_name=$(basename "$download_url")
	curl -L --output-dir "$bin_dir" -O "$download_url"
	if [[ $? -ne 0 ]]; then
		log_error "Failed to download $binary_name from $download_url"
		return 1
	fi
	log_success "Downloaded ${tar_file_name} to ${bin_dir}"

	# Extract the tarball
	tar -xzf "${bin_dir}/${tar_file_name}" -C "$bin_dir"
	if [[ $? -ne 0 ]]; then
		log_error "Failed to extract ${tar_file_name}"
		return 1
	fi

	install_extracted_binary "$bin_dir" "$binary_name" "$tar_file_name" || return 1

	return 0
}

################################################################################
# Helper: install_extracted_binary
# Description: Moves an extracted release binary into place.
#              beacond archives contain a file named like the tarball stem
#              (beacond-v1.4.1-darwin-arm64). bera-reth archives contain a
#              file named bera-reth (the cargo binary).
#
# Arguments:
#   $1 - bin_dir: Directory the tarball was extracted into
#   $2 - binary_name: Expected final binary name
#   $3 - tar_file_name: Original tarball filename
#
# Returns:
#   0 - Success
#   1 - Failure (extracted binary not found)
################################################################################
install_extracted_binary() {
	local bin_dir="$1"
	local binary_name="$2"
	local tar_file_name="$3"
	local dest_path="${bin_dir}/${binary_name}"
	local archive_stem="${tar_file_name%.tar.gz}"
	local named_like_archive="${bin_dir}/${archive_stem}"

	if [[ -f "$named_like_archive" ]]; then
		mv -f "$named_like_archive" "$dest_path"
	elif [[ ! -f "$dest_path" ]]; then
		log_error "Failed to locate extracted binary '${binary_name}' in ${bin_dir}"
		return 1
	fi

	chmod +x "$dest_path"
	return 0
}

################################################################################
# Helper: verify_binary
# Description: Verifies that a binary is executable and gets its version
#
# Arguments:
#   $1 - binary_path: Full path to binary
#   $2 - version_flag: Flag to get version (e.g., "--version" or "version")
#
# Returns:
#   0 - Success (prints version)
#   1 - Failure (binary not executable or no version)
################################################################################
verify_binary() {
	local binary_path="$1"
	local version_flag="$2"
	local binary_name=$(basename "$binary_path")

	if [[ ! -x "$binary_path" ]]; then
		log_error "Binary ${binary_name} is not executable."
		return 1
	fi

	local binary_version
	local exit_code
	binary_version=$("$binary_path" $version_flag 2>&1) || exit_code=$?
	exit_code=${exit_code:-0}

	if [[ $exit_code -ne 0 ]] || [[ -z "$binary_version" ]]; then
		log_warn "Binary ${binary_name} exists but could not execute (exit code: ${exit_code})."
		log_warn "This may be a cross-platform binary (e.g., Linux binary on macOS)."
		return 1
	fi

	log_success "Binary ${binary_name} is executable."
	log_info "$binary_version"
	return 0
}

################################################################################
# Function: download_beranodes_binary
# Description: Downloads either bera-reth or beacond binary from GitHub releases
#
# This function has been refactored to eliminate duplication between
# bera-reth and beacond download logic by extracting common patterns
# into helper functions.
################################################################################
download_beranodes_binary() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: download_beranodes_binary" >&2

	# Local variables
	local config_dir="${BERANODES_PATH_DEFAULT}"
	local bin_dir="${config_dir}${BERANODES_PATH_BIN}"
	local binary_to_download="" # either $BIN_BERARETH or $BIN_BEACONKIT
	local version_tag="latest"
	local is_docker=false

	# Parse flags
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--config-dir)
			if [[ -n "$2" ]]; then
				check_dir="$2"
				if [[ ! -d "$check_dir" ]]; then
					log_warn "Config directory not found at $check_dir, using default directory ${BERANODES_PATH_DEFAULT}"
				else
					config_dir="$check_dir"
					bin_dir="${config_dir}${BERANODES_PATH_BIN}"
				fi
				shift 2
			else
				log_warn "--config-dir is not set. defaulting to ${BERANODES_PATH_DEFAULT}"
				shift
			fi
			;;
		--binary-to-download)
			if [[ -n "$2" ]]; then
				check_binary_to_download="$2"
				if [[ "$check_binary_to_download" != "$BIN_BERARETH" && "$check_binary_to_download" != "$BIN_BEACONKIT" ]]; then
					log_error "--binary-to-download is not set to either '${BIN_BERARETH}' or '${BIN_BEACONKIT}'"
					return 1
				fi
				binary_to_download="$check_binary_to_download"
				shift 2
			else
				log_error "--binary-to-download is not set to either '${BIN_BERARETH}' or '${BIN_BEACONKIT}'"
				return 1
			fi
			;;
		--version-tag)
			if [[ -n "$2" ]]; then
				check_version_tag="$2"
				if [[ ! "$check_version_tag" =~ $VERSION_TAG_REGEX ]]; then
			log_error "--version-tag must match format (latest or v<MAJ>.<MIN>.<PATCH> or v<MAJ>.<MIN>.<PATCH>-rc.N) (e.g., latest, v0.9.0, v1.4.2-rc.0)"
					return 1
				fi
				version_tag="$check_version_tag"
				log_info "Using version tag: $version_tag"
				shift 2
			else
				log_warn "--version-tag is not set. defaulting to ${version_tag}"
				shift
			fi
			;;
		--docker)
			is_docker=true
			shift
			;;
		*)
			log_error "Unknown option: $1"
			return 1
			;;
		esac
	done

	# Determine release URL based on binary type
	local release_base_url=""
	local version_cmd_flag=""

	if [[ "$binary_to_download" == "$BIN_BERARETH" ]]; then
		release_base_url="$RELEASE_BERARETH"
		version_cmd_flag="--version"
	elif [[ "$binary_to_download" == "$BIN_BEACONKIT" ]]; then
		release_base_url="$RELEASE_BEACONKIT"
		version_cmd_flag="version"
	else
		log_error "No binary specified. Use --binary-to-download option."
		return 1
	fi

	# Construct full release URL
	local release_url="${release_base_url}/releases$([[ "$version_tag" == "latest" ]] && echo "/latest" || echo "/tags/${version_tag}")"

	# Step 1: Fetch release information
	local response_body
	response_body=$(fetch_github_release "$release_url") || return 1

	# Step 2: Detect platform and architecture
	local arch
	arch=$(detect_platform_arch) || return 1

	# Step 3: Extract download URL
	local download_url
	if download_url=$(extract_download_url "$response_body" "$arch"); then
		# Step 4: Download and extract binary
		download_and_extract_binary "$download_url" "$bin_dir" "$binary_to_download" || return 1

		# Step 5: Verify binary is executable
		verify_binary "${bin_dir}/${binary_to_download}" "$version_cmd_flag" || return 1
	else
		# Fallback: No pre-built binary available for this platform.
		# Build from source targeting the native OS/architecture.
		log_warn "No pre-built binary available for '${arch}'. Building from source..."
		build_binary_from_source "$binary_to_download" "$bin_dir" "$version_tag" || return 1
	fi

	return 0
}

################################################################################
# Helper: build_binary_from_source
# Description: Builds a native binary from source inside Docker when no
#              pre-built binary is available for the current platform.
#
#              Uses cross-compilation Dockerfile templates that clone the
#              source repo and build targeting the host OS/architecture:
#                - beacond (Go):    CGO_ENABLED=0 GOOS=darwin GOARCH=arm64
#                - bera-reth (Rust): cargo-zigbuild --target aarch64-apple-darwin
#
#              The built binary is extracted via 'docker cp' and verified
#              on the host. Build images are cached for faster rebuilds.
#
# Arguments:
#   $1 - binary_to_download: Binary name (BIN_BERARETH or BIN_BEACONKIT)
#   $2 - bin_dir: Destination directory for the built binary
#   $3 - version_tag: Version tag (e.g., "latest", "v1.3.1")
#
# Returns:
#   0 - Success
#   1 - Failure
################################################################################
build_binary_from_source() {
	local binary_to_download="$1"
	local bin_dir="$2"
	local version_tag="${3:-latest}"

	# ── Step 1: Check Docker is available ─────────────────────────────────
	if ! command -v docker &>/dev/null; then
		log_error "Docker is required to build binaries from source."
		log_error "Please install Docker: https://docs.docker.com/get-docker/"
		return 1
	fi

	if ! docker info &>/dev/null; then
		log_error "Docker daemon is not running. Please start Docker and try again."
		return 1
	fi

	# ── Step 2: Determine build configuration ─────────────────────────────
	local github_repo=""
	local dockerfile_template=""
	local build_arg_name=""
	local build_image_name=""
	local binary_path_in_image="/usr/local/bin/${binary_to_download}"
	local version_cmd_flag=""

	if [[ "$binary_to_download" == "$BIN_BEACONKIT" ]]; then
		github_repo="berachain/beacon-kit"
		dockerfile_template="scripts/Dockerfile.beacond.darwin-arm64.template"
		build_arg_name="BEACON_KIT_TAG"
		build_image_name="beranode-builder-beacond-darwin-arm64"
		version_cmd_flag="version"
	elif [[ "$binary_to_download" == "$BIN_BERARETH" ]]; then
		github_repo="berachain/bera-reth"
		dockerfile_template="scripts/Dockerfile.berareth.darwin-arm64.template"
		build_arg_name="BERA_RETH_TAG"
		build_image_name="beranode-builder-bera-reth-darwin-arm64"
		version_cmd_flag="--version"
	else
		log_error "Unsupported binary for source build: ${binary_to_download}"
		return 1
	fi

	# Verify the Dockerfile template exists
	if [[ ! -f "$dockerfile_template" ]]; then
		log_error "Cross-compilation Dockerfile not found: ${dockerfile_template}"
		log_error "Make sure you are running beranode from the project root directory."
		return 1
	fi

	# ── Step 3: Resolve version tag ───────────────────────────────────────
	local resolved_tag="${version_tag}"
	if [[ "$resolved_tag" == "latest" ]]; then
		log_info "Resolving latest release tag for ${github_repo}..."
		resolved_tag=$(curl --silent "https://api.github.com/repos/${github_repo}/releases/latest" \
			| grep -o '"tag_name": *"v[^"]*"' | head -1 | cut -d'"' -f4)
		if [[ -z "$resolved_tag" ]]; then
			log_error "Failed to fetch latest release tag from GitHub for ${github_repo}."
			return 1
		fi
		log_info "Latest release: ${resolved_tag}"
	fi

	# ── Step 4: Check if build image already exists (cached) ──────────────
	local existing_image
	existing_image=$(docker images --format '{{.Repository}}:{{.Tag}}' \
		| grep "^${build_image_name}:${resolved_tag}$" 2>/dev/null || true)

	if [[ -n "$existing_image" ]]; then
		log_success "Found cached build image: ${existing_image}"
		log_info "Skipping build — extracting binary from cached image."
	else
		# ── Step 5: Build the Docker image ────────────────────────────────
		log_info "Building ${binary_to_download} for darwin-arm64 inside Docker..."
		log_warn "This may take several minutes (first build only — subsequent builds are cached)."

		local build_start_time
		build_start_time=$(date +%s)

		if ! docker build \
			-f "${dockerfile_template}" \
			--build-arg "${build_arg_name}=${resolved_tag}" \
			-t "${build_image_name}:${resolved_tag}" \
			. 2>&1; then
			log_error "Docker build failed for ${binary_to_download} (darwin-arm64)."
			log_error "Check the build output above for details."
			return 1
		fi

		local build_end_time
		build_end_time=$(date +%s)
		local build_duration=$(( build_end_time - build_start_time ))
		log_success "Docker build completed in ${build_duration}s"
	fi

	# ── Step 6: Extract binary from the build image ───────────────────────
	ensure_dir_exists "$bin_dir" "binary directory: $bin_dir"

	local container_name="beranode-build-extract-${binary_to_download}-$$"
	local dest_path="${bin_dir}/${binary_to_download}"

	log_info "Extracting ${binary_to_download} from build image..."

	if ! docker create --name "${container_name}" "${build_image_name}:${resolved_tag}" /bin/true &>/dev/null; then
		log_error "Failed to create temporary container from ${build_image_name}:${resolved_tag}"
		return 1
	fi

	if docker cp "${container_name}:${binary_path_in_image}" "${dest_path}"; then
		log_success "Extracted ${binary_to_download} to ${dest_path}"
	else
		log_error "Failed to extract binary from build image."
		docker rm "${container_name}" &>/dev/null || true
		return 1
	fi

	# Clean up temporary container (keep the image for caching)
	docker rm "${container_name}" &>/dev/null || true

	# ── Step 7: Verify the built binary on the host ───────────────────────
	chmod +x "${dest_path}"

	if verify_binary "${dest_path}" "${version_cmd_flag}"; then
		log_success "Binary '${binary_to_download}' built and verified for darwin-arm64."
		return 0
	else
		log_error "Built binary '${binary_to_download}' failed verification on this platform."
		log_error "The cross-compiled binary may not be compatible. Check build output for errors."
		return 1
	fi
}

download_beranodes_docker_image() {
	# Downloads the docker image for either bera-reth or beacon-kit
	# Usage:
	#   download_beranodes_docker_image --binary-to-download <BIN_BEACONKIT|BIN_BERARETH> [--version-tag <tag>]
	local binary_to_download=""
	local version_tag="latest"
	local docker_image=""
	local docker_pull_url=""

	# Parse args
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--binary-to-download)
			binary_to_download="$2"
			shift 2
			;;
		--version-tag)
			version_tag="$2"
			shift 2
			;;
		*)
			log_error "Unknown option to download_beranodes_docker_image: $1"
			return 1
			;;
		esac
	done

	if [[ -z "$binary_to_download" ]]; then
		log_error "No binary specified. Use --binary-to-download option."
		return 1
	fi

	# Resolve repo name for GitHub and Docker
	local github_repo=""
	if [[ "$binary_to_download" == "$BIN_BERARETH" ]]; then
		github_repo="berachain/bera-reth"
	elif [[ "$binary_to_download" == "$BIN_BEACONKIT" ]]; then
		github_repo="berachain/beacon-kit"
	else
		log_error "Unsupported binary for docker image: $binary_to_download"
		return 1
	fi

	# Normalize user-provided version_tag to "latest" or a direct tag
	if [[ "$version_tag" == "latest" ]]; then
		# Get latest release from GitHub API
		version_tag=$(curl --silent "https://api.github.com/repos/${github_repo}/releases/latest" | grep -o '"tag_name": *"v[^"]*"' | head -1 | cut -d'"' -f4)
		if [[ -z "$version_tag" ]]; then
			log_warn "Failed to fetch latest release tag from GitHub, defaulting to 'latest'"
			version_tag="latest"
		fi
	else
		# Validate tag exists by pinging GitHub releases API for the tag
		local tag_check
		tag_check=$(curl --silent -o /dev/null -w "%{http_code}" "https://api.github.com/repos/${github_repo}/releases/tags/${version_tag}")
		if [[ "$tag_check" != "200" ]]; then
			log_error "Version tag '${version_tag}' does not exist in ${github_repo} releases."
			return 1
		fi
	fi

	# Remove any leading 'v' for docker image tags if present
	if [[ "$version_tag" =~ ^v(.+) ]]; then
		version_tag="v${BASH_REMATCH[1]}"
	fi

	# Determine docker image
	if [[ "$binary_to_download" == "$BIN_BERARETH" ]]; then
		docker_image="${DOCKER_REGISTRY_BERARETH}"
	elif [[ "$binary_to_download" == "$BIN_BEACONKIT" ]]; then
		docker_image="${DOCKER_REGISTRY_BEACONKIT}"
	else
		log_error "Unsupported binary for docker image: $binary_to_download"
		return 1
	fi

	# Append the version tag (or "latest" by default)
	docker_pull_url="${docker_image}:${version_tag}"

	log_info "Pulling docker image: ${docker_pull_url}"
	if docker pull "${docker_pull_url}"; then
		log_success "Successfully pulled docker image: ${docker_pull_url}"
		return 0
	else
		log_error "Failed to pull docker image: ${docker_pull_url}"
		return 1
	fi
}
