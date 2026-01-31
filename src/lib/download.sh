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
					log_warn "Config directory not found at $config_dir, using default directory ${BERANODES_PATH_DEFAULT}"
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
            log_error "--binary-to-download is not set to ether '${BIN_BERARETH}' or '${BIN_BEACONKIT}'"
            return 1
          fi
          binary_to_download="$check_binary_to_download"
          shift 2
        else
          log_erorr "--binary-to-download is not set to ether '${BIN_BERARETH}' or '${BIN_BEACONKIT}'"
          return 1
        fi
        ;;
      --version-tag)
        if [[ -n "$2" ]]; then
          # version_tag="$2"
          check_version_tag="$2"
          if [[ ! "$check_version_tag" =~ ^(latest|v\.?[0-9]+\.[0-9]+\.[0-9]+(-rc[0-9]+(\.[0-9]+)?)?)$ ]]; then
            log_error "--version-tag must match format (latest or v<MAJ>.<MIN>.<PATCH> or v<MAJ>.<MIN>.<PATCH>-rc<N>) (e.g., latest, v0.6.0, v0.6.0-rc2)"
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
  
  # Download bera-reth binary
  if [[ "$binary_to_download" == "$BIN_BERARETH" ]]; then
    local release_url="${RELEASE_BERARETH}/releases$( [[ "$version_tag" == "latest" ]] && echo "/latest" || echo "/tags/${version_tag}" )"
    local download_url=""

    log_info "Checking bera-reth binary from: $release_url"
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
      log_error "Failed to get version from response: $response"
      return 1
    fi

    log_info "Using version: $version"

    local arch="unknown"
    if [[ "$IS_MACOS" == true ]]; then
      arch="darwin-arm64"
      download_url=$(echo "$response_body" | jq -r '.assets[] | select(.name | contains("darwin-arm64") and endswith(".tar.gz") and (contains(".sig") | not)) | .browser_download_url')
    elif [[ "$IS_LINUX" == true ]]; then
      if [[ "$IS_LINUX_ARM" == true ]]; then
        arch="linux-arm64"
        download_url=$(echo "$response" | jq -r '.assets[] | select(.name | contains("linux-arm64") and endswith(".tar.gz") and (contains(".sig") | not)) | .browser_download_url')
      else
        arch="linux-amd64"
        download_url=$(echo "$response" | jq -r '.assets[] | select(.name | contains("linux-amd64") and endswith(".tar.gz") and (contains(".sig") | not)) | .browser_download_url')
      fi
    else
      log_error "Unsupported platform: $PLATFORM - $ARCH"
      return 1
    fi

    if [[ -z "$download_url" ]]; then
      log_error "No download URL found for the required binary for '$arch'."
      return 1
    fi

    # Ensure the bin directory exists
    ensure_dir_exists "${config_dir}${BERANODES_PATH_BIN}" "binary directory: ${config_dir}${BERANODES_PATH_BIN}"

    log_info "Downloading $binary_to_download from $download_url"

    # curl -L --output "${config_dir}${BERANODES_PATH_BIN}/${binary_to_download}.tar.gz" "$download_url"
    tar_file_name=$(basename "$download_url")
    curl -L --output-dir "${config_dir}${BERANODES_PATH_BIN}" -O "$download_url"
    if [[ $? -ne 0 ]]; then
      log_error "Failed to download $binary_to_download from $download_url"
      return 1
    fi
    log_success "Downloaded ${tar_file_name} to ${config_dir}${BERANODES_PATH_BIN}"

    # untar the file in that directory
    tar -xzf "${config_dir}${BERANODES_PATH_BIN}/${tar_file_name}" -C "${config_dir}${BERANODES_PATH_BIN}"

    # rename the file to the binary name
    file_name="${tar_file_name%.tar.gz}"
    mv "${config_dir}${BERANODES_PATH_BIN}/${file_name}" "${config_dir}${BERANODES_PATH_BIN}/${binary_to_download}"

    # permissions to the binary
    chmod +x "${config_dir}${BERANODES_PATH_BIN}/${binary_to_download}"

    # check if binary is executable
    local binary_version=$("${config_dir}${BERANODES_PATH_BIN}/${binary_to_download}" --version)
    if [[ ! -x "${config_dir}${BERANODES_PATH_BIN}/${binary_to_download}" ]] || [[ -z "$binary_version" ]]; then
      log_error "Binary ${binary_to_download} is not executable."
      return 1
    fi
    log_success "Binary ${binary_to_download} is executable."
    log_info $binary_version
  # Download beacond binary
  elif [[ "$binary_to_download" == "$BIN_BEACONKIT" ]]; then
    local release_url="${RELEASE_BEACONKIT}/releases$( [[ "$version_tag" == "latest" ]] && echo "/latest" || echo "/tags/${version_tag}" )"
    local download_url=""

    log_info "Checking beacond binary from: $release_url"
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
      log_error "Failed to get version from response: $response"
      return 1
    fi

    log_info "Using version: $version"
    local arch="unknown"
    if [[ "$IS_MACOS" == true ]]; then
      arch="darwin-arm64"
      download_url=$(echo "$response_body" | jq -r '.assets[] | select(.name | contains("darwin-arm64") and endswith(".tar.gz") and (contains(".sig") | not)) | .browser_download_url')
    elif [[ "$IS_LINUX" == true ]]; then
      if [[ "$IS_LINUX_ARM" == true ]]; then
        arch="linux-arm64"
        download_url=$(echo "$response" | jq -r '.assets[] | select(.name | contains("linux-arm64") and endswith(".tar.gz") and (contains(".sig") | not)) | .browser_download_url')
      else
        arch="linux-amd64"
        download_url=$(echo "$response" | jq -r '.assets[] | select(.name | contains("linux-amd64") and endswith(".tar.gz") and (contains(".sig") | not)) | .browser_download_url')
      fi
    else
      log_error "Unsupported platform: $PLATFORM - $ARCH"
      return 1
    fi

    if [[ -z "$download_url" ]]; then
      log_error "No download URL found for the required binary for '$arch'."
      return 1
    fi

    # Ensure the bin directory exists
    ensure_dir_exists "${config_dir}${BERANODES_PATH_BIN}" "binary directory: ${config_dir}${BERANODES_PATH_BIN}"

    log_info "Downloading $binary_to_download from $download_url"

    # curl -L --output "${config_dir}${BERANODES_PATH_BIN}/${binary_to_download}.tar.gz" "$download_url"
    tar_file_name=$(basename "$download_url")
    curl -L --output-dir "${config_dir}${BERANODES_PATH_BIN}" -O "$download_url"
    if [[ $? -ne 0 ]]; then
      log_error "Failed to download $binary_to_download from $download_url"
      return 1
    fi
    log_success "Downloaded ${tar_file_name} to ${config_dir}${BERANODES_PATH_BIN}"

    # untar the file in that directory
    tar -xzf "${config_dir}${BERANODES_PATH_BIN}/${tar_file_name}" -C "${config_dir}${BERANODES_PATH_BIN}"

    # rename the file to the binary name
    file_name="${tar_file_name%.tar.gz}"
    mv "${config_dir}${BERANODES_PATH_BIN}/${file_name}" "${config_dir}${BERANODES_PATH_BIN}/${binary_to_download}"

    # permissions to the binary
    chmod +x "${config_dir}${BERANODES_PATH_BIN}/${binary_to_download}"

    # check if binary is executable
    local binary_version=$("${config_dir}${BERANODES_PATH_BIN}/${binary_to_download}" version)
    if [[ ! -x "${config_dir}${BERANODES_PATH_BIN}/${binary_to_download}" ]] || [[ -z "$binary_version" ]]; then
      log_error "Binary ${binary_to_download} is not executable."
      return 1
    fi
    log_success "Binary ${binary_to_download} is executable."
    log_info $binary_version
  fi
}