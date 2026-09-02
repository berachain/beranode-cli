#!/usr/bin/env bash
set -euo pipefail
################################################################################
# serviceman.sh - OS service-manager helpers (macOS launchd)
################################################################################
#
# serviceman mode runs the same native binaries as local mode, but start/stop
# go through the host service manager instead of background PIDs.
#
# macOS: user-domain launchd (LaunchAgents). Linux systemd is not implemented.
#
################################################################################

: "${DEBUG_MODE:=false}"

################################################################################
# Platform / launchctl
################################################################################

serviceman_require_launchd() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: serviceman_require_launchd" >&2

	if [[ "${IS_MACOS}" != "true" ]]; then
		if [[ "${IS_LINUX}" == "true" ]]; then
			log_error "serviceman mode on Linux (systemd) is not implemented yet."
			log_error "Use 'beranode init --mode local' or '--mode docker' on this platform."
		else
			log_error "serviceman mode is only available on macOS (launchd)."
		fi
		return 1
	fi

	if ! command -v launchctl >/dev/null 2>&1; then
		log_error "launchctl not found. macOS launchd is required for --mode serviceman."
		return 1
	fi

	return 0
}

serviceman_abspath() {
	local path="$1"
	if [[ -z "${path}" ]]; then
		echo ""
		return 1
	fi
	if [[ "${path}" == /* ]]; then
		echo "${path}"
		return 0
	fi
	(cd "${path}" && pwd)
}

serviceman_path_hash() {
	local path="$1"
	if command -v shasum >/dev/null 2>&1; then
		printf '%s' "${path}" | shasum -a 256 | awk '{print substr($1,1,8)}'
	else
		printf '%s' "${path}" | sha256sum | awk '{print substr($1,1,8)}'
	fi
}

serviceman_sanitize_label_part() {
	local raw="$1"
	local cleaned
	cleaned=$(printf '%s' "${raw}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')
	if [[ -z "${cleaned}" ]]; then
		cleaned="node"
	fi
	printf '%s' "${cleaned}"
}

serviceman_xml_escape() {
	local s="$1"
	s=${s//&/\&amp;}
	s=${s//</\&lt;}
	s=${s//>/\&gt;}
	s=${s//\"/\&quot;}
	s=${s//\'/\&apos;}
	printf '%s' "${s}"
}

serviceman_launchd_domain() {
	local uid
	uid="$(id -u)"
	if launchctl print "gui/${uid}" >/dev/null 2>&1; then
		echo "gui/${uid}"
	else
		echo "user/${uid}"
	fi
}

serviceman_launchagents_dir() {
	echo "${HOME}/Library/LaunchAgents"
}

serviceman_label() {
	local beranodes_dir="$1"
	local moniker="$2"
	local node_index="$3"
	local component="$4"
	local abs hash mono
	abs=$(serviceman_abspath "${beranodes_dir}")
	hash=$(serviceman_path_hash "${abs}")
	mono=$(serviceman_sanitize_label_part "${moniker}")
	component=$(serviceman_sanitize_label_part "${component}")
	echo "${SERVICEMAN_LAUNCHD_LABEL_PREFIX}.${hash}.${mono}.${node_index}.${component}"
}

serviceman_plist_filename() {
	local label="$1"
	echo "${label}.plist"
}

serviceman_user_plist_path() {
	local label="$1"
	echo "$(serviceman_launchagents_dir)/$(serviceman_plist_filename "${label}")"
}

serviceman_repo_plist_path() {
	local beranodes_dir="$1"
	local label="$2"
	echo "${beranodes_dir}${BERANODES_PATH_SERVICES}/$(serviceman_plist_filename "${label}")"
}

serviceman_manifest_path() {
	local beranodes_dir="$1"
	echo "${beranodes_dir}${BERANODES_PATH_SERVICES}/launchd.json"
}

################################################################################
# Plist generation
################################################################################

# Writes a launchd plist. Remaining args after the named parameters are
# ProgramArguments (executable + flags).
#
# $1 beranodes_dir  $2 label  $3 working_dir  $4 log_file  $5... program args
serviceman_write_plist() {
	local beranodes_dir="$1"
	local label="$2"
	local working_dir="$3"
	local log_file="$4"
	shift 4

	local user_plist repo_plist
	user_plist=$(serviceman_user_plist_path "${label}")
	repo_plist=$(serviceman_repo_plist_path "${beranodes_dir}" "${label}")

	mkdir -p "$(serviceman_launchagents_dir)"
	mkdir -p "${beranodes_dir}${BERANODES_PATH_SERVICES}"
	mkdir -p "$(dirname "${log_file}")"
	mkdir -p "${working_dir}"

	local args_xml=""
	local arg
	for arg in "$@"; do
		args_xml="${args_xml}		<string>$(serviceman_xml_escape "${arg}")</string>
"
	done

	local plist_body
	plist_body=$(cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$(serviceman_xml_escape "${label}")</string>
	<key>ProgramArguments</key>
	<array>
${args_xml}	</array>
	<key>WorkingDirectory</key>
	<string>$(serviceman_xml_escape "${working_dir}")</string>
	<key>StandardOutPath</key>
	<string>$(serviceman_xml_escape "${log_file}")</string>
	<key>StandardErrorPath</key>
	<string>$(serviceman_xml_escape "${log_file}")</string>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>ThrottleInterval</key>
	<integer>${SERVICEMAN_LAUNCHD_THROTTLE_INTERVAL}</integer>
	<key>ProcessType</key>
	<string>Background</string>
</dict>
</plist>
EOF
)

	printf '%s\n' "${plist_body}" >"${repo_plist}"
	cp -f "${repo_plist}" "${user_plist}"
	echo "${user_plist}"
}

################################################################################
# Manifest
################################################################################

serviceman_write_fresh_manifest() {
	local beranodes_dir="$1"
	local domain="$2"
	local abs
	abs=$(serviceman_abspath "${beranodes_dir}")
	mkdir -p "${abs}${BERANODES_PATH_SERVICES}"
	jq -n \
		--arg domain "${domain}" \
		--arg dir "${abs}" \
		'{domain: $domain, beranodes_dir: $dir, services: []}' \
		>"$(serviceman_manifest_path "${abs}")"
}

serviceman_manifest_add() {
	local beranodes_dir="$1"
	local label="$2"
	local component="$3"
	local node_index="$4"
	local plist="$5"
	local log_file="$6"
	local abs manifest tmp
	abs=$(serviceman_abspath "${beranodes_dir}")
	manifest=$(serviceman_manifest_path "${abs}")
	if [[ ! -f "${manifest}" ]]; then
		serviceman_write_fresh_manifest "${abs}" "$(serviceman_launchd_domain)"
	fi
	tmp=$(mktemp)
	jq \
		--arg label "${label}" \
		--arg component "${component}" \
		--argjson index "${node_index}" \
		--arg plist "${plist}" \
		--arg log "${log_file}" \
		'.services += [{label: $label, component: $component, node_index: $index, plist: $plist, log: $log}]' \
		"${manifest}" >"${tmp}"
	mv "${tmp}" "${manifest}"
}

################################################################################
# launchctl bootstrap / bootout
################################################################################

serviceman_bootout() {
	local domain="$1"
	local label="$2"
	launchctl bootout "${domain}/${label}" >/dev/null 2>&1 || true
}

serviceman_bootstrap() {
	local domain="$1"
	local plist="$2"
	local label="$3"

	launchctl enable "${domain}/${label}" >/dev/null 2>&1 || true
	if ! launchctl bootstrap "${domain}" "${plist}" >/dev/null 2>&1; then
		# Already loaded from a previous partial start: replace it.
		serviceman_bootout "${domain}" "${label}"
		launchctl bootstrap "${domain}" "${plist}" >/dev/null 2>&1 || {
			log_error "launchctl bootstrap failed for ${label}"
			log_error "Plist: ${plist}"
			return 1
		}
	fi
	# Ensure it is actually running (KeepAlive + RunAtLoad should, kickstart if not).
	launchctl kickstart -k "${domain}/${label}" >/dev/null 2>&1 || true
	return 0
}

serviceman_service_state() {
	local domain="$1"
	local label="$2"
	local print_out pid
	if ! print_out=$(launchctl print "${domain}/${label}" 2>/dev/null); then
		echo "offline"
		return 0
	fi
	pid=$(printf '%s\n' "${print_out}" | awk '/[[:space:]]pid = / {print $3; exit}')
	if [[ -n "${pid}" && "${pid}" != "0" ]]; then
		echo "running"
		return 0
	fi
	if printf '%s\n' "${print_out}" | grep -q 'state = running'; then
		echo "running"
		return 0
	fi
	echo "stopped"
}

serviceman_component_status() {
	local beranodes_dir="$1"
	local moniker="$2"
	local node_index="$3"
	local component="$4"
	local label domain
	label=$(serviceman_label "${beranodes_dir}" "${moniker}" "${node_index}" "${component}")
	domain=$(serviceman_launchd_domain)
	serviceman_service_state "${domain}" "${label}"
}

################################################################################
# Start / stop a node's processes
################################################################################

# Starts one process under launchd. Remaining args are the command line.
# $1 beranodes_dir  $2 moniker  $3 node_index  $4 component
# $5 working_dir  $6 log_file  $7... argv
serviceman_start_service() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: serviceman_start_service" >&2

	local beranodes_dir="$1"
	local moniker="$2"
	local node_index="$3"
	local component="$4"
	local working_dir="$5"
	local log_file="$6"
	shift 6

	serviceman_require_launchd || return 1

	local abs domain label user_plist
	abs=$(serviceman_abspath "${beranodes_dir}")
	domain=$(serviceman_launchd_domain)
	label=$(serviceman_label "${abs}" "${moniker}" "${node_index}" "${component}")

	serviceman_bootout "${domain}" "${label}"
	user_plist=$(serviceman_write_plist "${abs}" "${label}" "${working_dir}" "${log_file}" "$@")
	serviceman_bootstrap "${domain}" "${user_plist}" "${label}" || return 1
	serviceman_manifest_add "${abs}" "${label}" "${component}" "${node_index}" "${user_plist}" "${log_file}"
	log_info "launchd: ${label}"
	return 0
}

serviceman_labels_for_dir() {
	local beranodes_dir="$1"
	local abs hash manifest
	abs=$(serviceman_abspath "${beranodes_dir}") || return 0
	hash=$(serviceman_path_hash "${abs}")
	manifest=$(serviceman_manifest_path "${abs}")

	{
		if [[ -f "${manifest}" ]]; then
			jq -r '.services[].label // empty' "${manifest}" 2>/dev/null || true
		fi
		local agents prefix plist
		agents=$(serviceman_launchagents_dir)
		prefix="${SERVICEMAN_LAUNCHD_LABEL_PREFIX}.${hash}."
		for plist in "${agents}/${prefix}"*.plist; do
			[[ -f "${plist}" ]] || continue
			basename "${plist}" .plist
		done
	} | awk 'NF && !seen[$0]++'
}

serviceman_stop_all() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: serviceman_stop_all" >&2

	local beranodes_dir="$1"
	if [[ "${IS_MACOS}" != "true" ]] || ! command -v launchctl >/dev/null 2>&1; then
		return 0
	fi

	local domain label user_plist count=0
	domain=$(serviceman_launchd_domain)

	local labels
	labels=$(serviceman_labels_for_dir "${beranodes_dir}" || true)
	if [[ -z "${labels}" ]]; then
		log_info "No launchd services found for ${beranodes_dir}"
		return 0
	fi

	while IFS= read -r label; do
		[[ -z "${label}" ]] && continue
		log_info "Stopping launchd job ${label}"
		serviceman_bootout "${domain}" "${label}"
		user_plist=$(serviceman_user_plist_path "${label}")
		rm -f "${user_plist}"
		count=$((count + 1))
	done <<<"${labels}"

	log_success "Stopped ${count} launchd job(s)"
	return 0
}

serviceman_any_running() {
	local beranodes_dir="$1"
	if [[ "${IS_MACOS}" != "true" ]] || ! command -v launchctl >/dev/null 2>&1; then
		return 1
	fi
	local domain label state
	domain=$(serviceman_launchd_domain)
	local labels
	labels=$(serviceman_labels_for_dir "${beranodes_dir}" || true)
	[[ -z "${labels}" ]] && return 1
	while IFS= read -r label; do
		[[ -z "${label}" ]] && continue
		state=$(serviceman_service_state "${domain}" "${label}")
		if [[ "${state}" == "running" ]]; then
			return 0
		fi
	done <<<"${labels}"
	return 1
}

serviceman_prepare_start() {
	local beranodes_dir="$1"
	serviceman_require_launchd || return 1
	local abs
	abs=$(serviceman_abspath "${beranodes_dir}")
	log_info "Unloading any existing launchd jobs for this node set..."
	serviceman_stop_all "${abs}" || true
	serviceman_write_fresh_manifest "${abs}" "$(serviceman_launchd_domain)"
}
