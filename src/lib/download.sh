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

  log_info "Checking binary from: $release_url"

  # Check if the URL doesn't return a 404 before using it
  local response=$(curl -s -w "\n%{http_code}" "$release_url")
  local http_status=$(echo "$response" | tail -n1)
  local response_body=$(echo "$response" | sed '$d')

  if [[ "$http_status" == "404" ]]; then
    log_error "Release URL not found (404): $release_url"
    return 1
  fi

  # Check if the response is valid JSON (for GitHub API)
  if ! echo "$response_body" | jq . >/dev/null 2>&1; then
    log_error "Response from $release_url is not valid JSON."
    return 1
  fi

  local version=$(echo "$response_body" | jq -r '.tag_name')
  if [[ "$version" == "null" ]]; then
    log_error "Failed to get version from response"
    return 1
  fi

  log_info "Using version: $version"
  echo "$response_body"
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
# Helper: extract_download_url
# Description: Extracts binary download URL from GitHub release response
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

  local download_url=$(echo "$response_body" | jq -r ".assets[] | select(.name | contains(\"$arch\") and endswith(\".tar.gz\") and (contains(\".sig\") | not)) | .browser_download_url")

  if [[ -z "$download_url" ]]; then
    log_error "No download URL found for the required binary for '$arch'."
    return 1
  fi

  echo "$download_url"
  return 0
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

  # Rename the extracted file to the binary name
  local file_name="${tar_file_name%.tar.gz}"
  mv "${bin_dir}/${file_name}" "${bin_dir}/${binary_name}"

  # Set executable permissions
  chmod +x "${bin_dir}/${binary_name}"

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

  local binary_version=$("$binary_path" $version_flag 2>&1)
  if [[ -z "$binary_version" ]]; then
    log_error "Failed to get version from ${binary_name}."
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
        if [[ ! "$check_version_tag" =~ ^(latest|v\.?[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+(\.[0-9]+)?)?)$ ]]; then
          log_error "--version-tag must match format (latest or v<MAJ>.<MIN>.<PATCH> or v<MAJ>.<MIN>.<PATCH>-rc<N>) (e.g., latest, v0.7.1, v0.7.1-rc2)"
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
  local release_url="${release_base_url}/releases$( [[ "$version_tag" == "latest" ]] && echo "/latest" || echo "/tags/${version_tag}" )"

  # Step 1: Fetch release information
  local response_body
  response_body=$(fetch_github_release "$release_url") || return 1

  # Step 2: Detect platform and architecture
  local arch
  arch=$(detect_platform_arch) || return 1

  # Step 3: Extract download URL
  local download_url
  download_url=$(extract_download_url "$response_body" "$arch") || return 1

  # Step 4: Download and extract binary
  download_and_extract_binary "$download_url" "$bin_dir" "$binary_to_download" || return 1

  # Step 5: Verify binary is executable
  verify_binary "${bin_dir}/${binary_to_download}" "$version_cmd_flag" || return 1

  return 0
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

