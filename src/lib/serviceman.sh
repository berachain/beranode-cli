#!/usr/bin/env bash
set -euo pipefail
################################################################################
# serviceman.sh - OS service-manager helpers (macOS launchd / Linux systemd)
################################################################################
#
# serviceman mode runs the same native binaries as local mode, but start/stop
# go through the host service manager instead of background PIDs.
#
# macOS:  user-domain launchd (LaunchAgents). Logs: beranodes/logs/ via plist.
# Linux:  systemd user units + journald. Logs: journald and beranodes/logs/.
#
################################################################################

: "${DEBUG_MODE:=false}"

################################################################################
# Platform dispatch
################################################################################

# Prints: launchd | systemd | ""
serviceman_backend() {
	if [[ "${IS_MACOS}" == "true" ]]; then
		echo "launchd"
	elif [[ "${IS_LINUX}" == "true" ]]; then
		echo "systemd"
	else
		echo ""
	fi
}

serviceman_backend_description() {
	case "$(serviceman_backend)" in
	launchd) echo "launchd (user LaunchAgents)" ;;
	systemd) echo "systemd (user units) + journald" ;;
	*) echo "unavailable on this platform" ;;
	esac
}

# Ensures the host service manager for --mode serviceman is present.
serviceman_require() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: serviceman_require" >&2

	case "$(serviceman_backend)" in
	launchd)
		serviceman_require_launchd
		;;
	systemd)
		serviceman_require_systemd
		;;
	*)
		log_error "serviceman mode is only available on macOS (launchd) and Linux (systemd)."
		log_error "Use 'beranode init --mode local' or '--mode docker' on this platform."
		return 1
		;;
	esac
}

################################################################################
# Shared identity helpers
################################################################################

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

serviceman_manifest_path() {
	local beranodes_dir="$1"
	case "$(serviceman_backend)" in
	systemd) echo "${beranodes_dir}${BERANODES_PATH_SERVICES}/systemd.json" ;;
	*) echo "${beranodes_dir}${BERANODES_PATH_SERVICES}/launchd.json" ;;
	esac
}

serviceman_write_fresh_manifest() {
	local beranodes_dir="$1"
	local domain="$2"
	local abs backend
	abs=$(serviceman_abspath "${beranodes_dir}")
	backend=$(serviceman_backend)
	mkdir -p "${abs}${BERANODES_PATH_SERVICES}"
	jq -n \
		--arg backend "${backend}" \
		--arg domain "${domain}" \
		--arg dir "${abs}" \
		'{backend: $backend, domain: $domain, beranodes_dir: $dir, services: []}' \
		>"$(serviceman_manifest_path "${abs}")"
}

serviceman_manifest_add() {
	local beranodes_dir="$1"
	local label="$2"
	local component="$3"
	local node_index="$4"
	local artifact="$5"
	local log_file="$6"
	local abs manifest tmp backend domain
	abs=$(serviceman_abspath "${beranodes_dir}")
	manifest=$(serviceman_manifest_path "${abs}")
	backend=$(serviceman_backend)
	if [[ ! -f "${manifest}" ]]; then
		case "${backend}" in
		systemd) domain="user" ;;
		*) domain=$(serviceman_launchd_domain) ;;
		esac
		serviceman_write_fresh_manifest "${abs}" "${domain}"
	fi
	tmp=$(mktemp)
	if [[ "${backend}" == "systemd" ]]; then
		jq \
			--arg label "${label}" \
			--arg component "${component}" \
			--argjson index "${node_index}" \
			--arg unit "${artifact}" \
			--arg log "${log_file}" \
			'.services += [{label: $label, component: $component, node_index: $index, unit: $unit, log: $log}]' \
			"${manifest}" >"${tmp}"
	else
		jq \
			--arg label "${label}" \
			--arg component "${component}" \
			--argjson index "${node_index}" \
			--arg plist "${artifact}" \
			--arg log "${log_file}" \
			'.services += [{label: $label, component: $component, node_index: $index, plist: $plist, log: $log}]' \
			"${manifest}" >"${tmp}"
	fi
	mv "${tmp}" "${manifest}"
}

################################################################################
# macOS launchd
################################################################################

serviceman_require_launchd() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: serviceman_require_launchd" >&2

	if [[ "${IS_MACOS}" != "true" ]]; then
		if [[ "${IS_LINUX}" == "true" ]]; then
			serviceman_require_systemd
			return $?
		fi
		log_error "serviceman mode is only available on macOS (launchd) and Linux (systemd)."
		return 1
	fi

	if ! command -v launchctl >/dev/null 2>&1; then
		log_error "launchctl not found. macOS launchd is required for --mode serviceman."
		return 1
	fi

	return 0
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

serviceman_launchd_service_state() {
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

################################################################################
# Linux systemd + journald
################################################################################

# True when the systemctl and journalctl binaries are on PATH.
serviceman_systemd_binaries_present() {
	command -v systemctl >/dev/null 2>&1 && command -v journalctl >/dev/null 2>&1
}

# True when systemd is the running init (not merely packaged).
serviceman_systemd_is_init() {
	[[ -d /run/systemd/system ]]
}

# True when journald is accepting connections.
serviceman_journald_is_running() {
	[[ -S /run/systemd/journal/socket ]] || [[ -S /run/systemd/journal/stdout ]] || [[ -d /run/systemd/journal ]]
}

# Sets XDG_RUNTIME_DIR / session bus when a user systemd instance exists.
serviceman_systemd_prepare_env() {
	local uid rundir
	uid="$(id -u)"
	rundir="${XDG_RUNTIME_DIR:-/run/user/${uid}}"
	if [[ -z "${XDG_RUNTIME_DIR:-}" && -d "${rundir}" ]]; then
		export XDG_RUNTIME_DIR="${rundir}"
	fi
	if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -n "${XDG_RUNTIME_DIR:-}" && -S "${XDG_RUNTIME_DIR}/bus" ]]; then
		export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"
	fi
}

# True when `systemctl --user` can talk to the user instance.
serviceman_systemd_user_available() {
	serviceman_systemd_prepare_env
	systemctl --user show-environment >/dev/null 2>&1
}

serviceman_systemd_user_dir() {
	echo "${XDG_CONFIG_HOME:-${HOME}/.config}/systemd/user"
}

serviceman_unit_filename() {
	local label="$1"
	echo "${label}.service"
}

serviceman_user_unit_path() {
	local label="$1"
	echo "$(serviceman_systemd_user_dir)/$(serviceman_unit_filename "${label}")"
}

serviceman_repo_unit_path() {
	local beranodes_dir="$1"
	local label="$2"
	echo "${beranodes_dir}${BERANODES_PATH_SERVICES}/$(serviceman_unit_filename "${label}")"
}

serviceman_systemd_runner_path() {
	local beranodes_dir="$1"
	echo "${beranodes_dir}${BERANODES_PATH_SERVICES}/${SERVICEMAN_SYSTEMD_RUNNER_NAME}"
}

# Quotes one ExecStart / unit-file word for systemd (not shell).
# systemd expands $VAR and %i; double them so they stay literal.
serviceman_systemd_quote() {
	local s="${1-}"
	s=${s//\\/\\\\}
	s=${s//\"/\\\"}
	s=${s//\$/\$\$}
	s=${s//\%/%%}
	printf '"%s"' "${s}"
}

serviceman_write_systemd_runner() {
	local dest="$1"
	mkdir -p "$(dirname "${dest}")"
	cat >"${dest}" <<'RUNNER'
#!/usr/bin/env bash
# Mirror stdout/stderr to a log file while leaving the original stdout
# (journald via StandardOutput=journal) intact. exec keeps systemd MainPID
# as the node binary.
set -euo pipefail
log_file="$1"
shift
mkdir -p "$(dirname "${log_file}")"
: >>"${log_file}"
exec > >(tee -a "${log_file}")
exec 2>&1
exec "$@"
RUNNER
	chmod +x "${dest}"
}

# Writes a systemd user unit. Remaining args after the named parameters are
# the command line (executable + flags).
#
# $1 beranodes_dir  $2 label  $3 working_dir  $4 log_file  $5... program args
serviceman_write_unit() {
	local beranodes_dir="$1"
	local label="$2"
	local working_dir="$3"
	local log_file="$4"
	shift 4

	local user_unit repo_unit runner unit_name exec_line arg
	user_unit=$(serviceman_user_unit_path "${label}")
	repo_unit=$(serviceman_repo_unit_path "${beranodes_dir}" "${label}")
	runner=$(serviceman_systemd_runner_path "${beranodes_dir}")
	unit_name=$(serviceman_unit_filename "${label}")

	mkdir -p "$(serviceman_systemd_user_dir)"
	mkdir -p "${beranodes_dir}${BERANODES_PATH_SERVICES}"
	mkdir -p "$(dirname "${log_file}")"
	mkdir -p "${working_dir}"

	serviceman_write_systemd_runner "${runner}"

	exec_line="$(serviceman_systemd_quote "${runner}") $(serviceman_systemd_quote "${log_file}")"
	for arg in "$@"; do
		exec_line="${exec_line} $(serviceman_systemd_quote "${arg}")"
	done

	local unit_body
	unit_body=$(cat <<EOF
[Unit]
Description=Beranode ${label}
Documentation=man:journalctl(1)

[Service]
Type=simple
WorkingDirectory=$(serviceman_systemd_quote "${working_dir}")
ExecStart=${exec_line}
Restart=always
RestartSec=${SERVICEMAN_SYSTEMD_RESTART_SEC}
StartLimitIntervalSec=0
TimeoutStopSec=${SERVICEMAN_SYSTEMD_TIMEOUT_STOP_SEC}
KillMode=control-group
LimitNOFILE=${SERVICEMAN_SYSTEMD_LIMIT_NOFILE}
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${label}

[Install]
WantedBy=default.target
EOF
)

	printf '%s\n' "${unit_body}" >"${repo_unit}"
	cp -f "${repo_unit}" "${user_unit}"
	echo "${user_unit}"
}

serviceman_require_systemd() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: serviceman_require_systemd" >&2

	if [[ "${IS_LINUX}" != "true" ]]; then
		log_error "systemd serviceman mode is only available on Linux."
		return 1
	fi

	if ! command -v systemctl >/dev/null 2>&1; then
		log_error "systemctl not found. systemd is required for --mode serviceman on Linux."
		log_error "Install systemd, or use 'beranode init --mode local' or '--mode docker'."
		return 1
	fi

	if ! serviceman_systemd_is_init; then
		log_error "systemd is not the active init system (missing /run/systemd/system)."
		log_error "Use 'beranode init --mode local' or '--mode docker' on this host."
		return 1
	fi

	if ! command -v journalctl >/dev/null 2>&1; then
		log_error "journalctl not found. systemd-journald is required for --mode serviceman on Linux."
		return 1
	fi

	if ! serviceman_journald_is_running; then
		log_error "systemd-journald does not appear to be running (no journal socket under /run/systemd/journal)."
		log_error "Start systemd-journald, or use 'beranode init --mode local' or '--mode docker'."
		return 1
	fi

	if ! command -v tee >/dev/null 2>&1; then
		log_error "tee not found. It is required to mirror logs to beranodes/logs/ under systemd."
		return 1
	fi

	serviceman_systemd_prepare_env
	if ! serviceman_systemd_user_available; then
		log_error "systemd user instance is not available (systemctl --user failed)."
		log_error "Log in with a systemd user session (XDG_RUNTIME_DIR=/run/user/$(id -u))."
		log_error "On a headless host you may need: sudo loginctl enable-linger $(id -un)"
		return 1
	fi

	return 0
}

serviceman_systemd_ensure_linger() {
	local user linger
	user="$(id -un)"
	command -v loginctl >/dev/null 2>&1 || return 0
	linger=$(loginctl show-user "${user}" --property=Linger --value 2>/dev/null || echo "no")
	if [[ "${linger}" == "yes" ]]; then
		return 0
	fi
	if loginctl enable-linger "${user}" >/dev/null 2>&1; then
		log_info "Enabled systemd lingering for ${user} so user units survive logout."
		return 0
	fi
	log_warn "systemd lingering is not enabled for ${user}."
	log_warn "User services may stop on logout. Enable with: sudo loginctl enable-linger ${user}"
	return 0
}

serviceman_systemd_stop_unit() {
	local label="$1"
	local unit_name user_unit
	unit_name=$(serviceman_unit_filename "${label}")
	user_unit=$(serviceman_user_unit_path "${label}")
	serviceman_systemd_prepare_env
	systemctl --user disable --now "${unit_name}" >/dev/null 2>&1 || true
	systemctl --user reset-failed "${unit_name}" >/dev/null 2>&1 || true
	rm -f "${user_unit}"
}

serviceman_systemd_start_unit() {
	local label="$1"
	local user_unit="$2"
	local unit_name
	unit_name=$(serviceman_unit_filename "${label}")
	serviceman_systemd_prepare_env
	systemctl --user daemon-reload >/dev/null 2>&1 || true
	if ! systemctl --user enable --now "${unit_name}" >/dev/null 2>&1; then
		log_error "systemctl --user enable --now failed for ${unit_name}"
		log_error "Unit: ${user_unit}"
		return 1
	fi
	return 0
}

serviceman_systemd_service_state() {
	local label="$1"
	local unit_name load_state active_state
	unit_name=$(serviceman_unit_filename "${label}")
	serviceman_systemd_prepare_env
	load_state=$(systemctl --user show "${unit_name}" -p LoadState --value 2>/dev/null || echo "not-found")
	if [[ "${load_state}" == "not-found" || -z "${load_state}" ]]; then
		echo "offline"
		return 0
	fi
	active_state=$(systemctl --user show "${unit_name}" -p ActiveState --value 2>/dev/null || echo "unknown")
	case "${active_state}" in
	active | activating | reloading)
		echo "running"
		;;
	inactive | failed | deactivating)
		echo "stopped"
		;;
	*)
		echo "offline"
		;;
	esac
}

################################################################################
# Start / stop / status (backend-agnostic)
################################################################################

serviceman_service_state() {
	local domain="$1"
	local label="$2"
	case "$(serviceman_backend)" in
	systemd)
		serviceman_systemd_service_state "${label}"
		;;
	*)
		serviceman_launchd_service_state "${domain}" "${label}"
		;;
	esac
}

serviceman_component_status() {
	local beranodes_dir="$1"
	local moniker="$2"
	local node_index="$3"
	local component="$4"
	local label domain
	label=$(serviceman_label "${beranodes_dir}" "${moniker}" "${node_index}" "${component}")
	case "$(serviceman_backend)" in
	systemd)
		serviceman_systemd_service_state "${label}"
		;;
	*)
		domain=$(serviceman_launchd_domain)
		serviceman_launchd_service_state "${domain}" "${label}"
		;;
	esac
}

# Prints the PID of a running component, or empty if it is not running.
# launchd: job PID. systemd: prefers the beacond/bera-reth child of the
# wrapper (MainPID is the log-tee runner); falls back to MainPID.
serviceman_component_pid() {
	local beranodes_dir="$1"
	local moniker="$2"
	local node_index="$3"
	local component="$4"
	local label
	label=$(serviceman_label "${beranodes_dir}" "${moniker}" "${node_index}" "${component}")
	case "$(serviceman_backend)" in
	systemd)
		serviceman_systemd_component_pid "${label}" "${component}"
		;;
	*)
		serviceman_launchd_component_pid "${label}"
		;;
	esac
}

serviceman_launchd_component_pid() {
	local label="$1"
	local domain print_out pid
	if [[ "${IS_MACOS}" != "true" ]] || ! command -v launchctl >/dev/null 2>&1; then
		echo ""
		return 1
	fi
	domain=$(serviceman_launchd_domain)
	if ! print_out=$(launchctl print "${domain}/${label}" 2>/dev/null); then
		echo ""
		return 1
	fi
	pid=$(printf '%s\n' "${print_out}" | awk '/[[:space:]]pid = / {print $3; exit}')
	if [[ -n "${pid}" && "${pid}" != "0" && "${pid}" =~ ^[0-9]+$ ]]; then
		echo "${pid}"
		return 0
	fi
	echo ""
	return 1
}

serviceman_systemd_component_pid() {
	local label="$1"
	local component="$2"
	local unit_name main_pid child_pid comm
	if [[ "${IS_LINUX}" != "true" ]] || ! command -v systemctl >/dev/null 2>&1; then
		echo ""
		return 1
	fi
	unit_name=$(serviceman_unit_filename "${label}")
	serviceman_systemd_prepare_env
	main_pid=$(systemctl --user show "${unit_name}" -p MainPID --value 2>/dev/null) || main_pid=""
	if [[ -z "${main_pid}" || "${main_pid}" == "0" || ! "${main_pid}" =~ ^[0-9]+$ ]]; then
		echo ""
		return 1
	fi
	# Wrapper is `bash runner log_file <binary> ... | tee`. Prefer the binary.
	local children=""
	children=$(pgrep -P "${main_pid}" 2>/dev/null || true)
	if [[ -z "${children}" && -r "/proc/${main_pid}/task/${main_pid}/children" ]]; then
		children=$(tr ' ' '\n' <"/proc/${main_pid}/task/${main_pid}/children" 2>/dev/null || true)
	fi
	while IFS= read -r child_pid; do
		[[ "${child_pid}" =~ ^[0-9]+$ ]] || continue
		comm=$(ps -o comm= -p "${child_pid}" 2>/dev/null | tr -d ' ')
		case "${comm}" in
		*"${component}"*)
			echo "${child_pid}"
			return 0
			;;
		esac
	done <<<"${children}"
	echo "${main_pid}"
	return 0
}

# Starts one process under the host service manager. Remaining args are argv.
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

	serviceman_require || return 1

	local abs label
	abs=$(serviceman_abspath "${beranodes_dir}")
	label=$(serviceman_label "${abs}" "${moniker}" "${node_index}" "${component}")

	case "$(serviceman_backend)" in
	systemd)
		local user_unit
		serviceman_systemd_stop_unit "${label}"
		user_unit=$(serviceman_write_unit "${abs}" "${label}" "${working_dir}" "${log_file}" "$@")
		serviceman_systemd_start_unit "${label}" "${user_unit}" || return 1
		serviceman_manifest_add "${abs}" "${label}" "${component}" "${node_index}" "${user_unit}" "${log_file}"
		log_info "systemd: ${label}.service"
		log_info "journald: journalctl --user -u ${label}.service -f"
		;;
	*)
		local domain user_plist
		domain=$(serviceman_launchd_domain)
		serviceman_bootout "${domain}" "${label}"
		user_plist=$(serviceman_write_plist "${abs}" "${label}" "${working_dir}" "${log_file}" "$@")
		serviceman_bootstrap "${domain}" "${user_plist}" "${label}" || return 1
		serviceman_manifest_add "${abs}" "${label}" "${component}" "${node_index}" "${user_plist}" "${log_file}"
		log_info "launchd: ${label}"
		;;
	esac
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
		local prefix="${SERVICEMAN_LAUNCHD_LABEL_PREFIX}.${hash}."
		case "$(serviceman_backend)" in
		systemd)
			local units unit
			units=$(serviceman_systemd_user_dir)
			for unit in "${units}/${prefix}"*.service; do
				[[ -f "${unit}" ]] || continue
				basename "${unit}" .service
			done
			;;
		*)
			local agents plist
			agents=$(serviceman_launchagents_dir)
			for plist in "${agents}/${prefix}"*.plist; do
				[[ -f "${plist}" ]] || continue
				basename "${plist}" .plist
			done
			;;
		esac
	} | awk 'NF && !seen[$0]++'
}

serviceman_stop_all() {
	[[ "$DEBUG_MODE" == "true" ]] && echo "[DEBUG] Function: serviceman_stop_all" >&2

	local beranodes_dir="$1"
	local labels label count=0

	case "$(serviceman_backend)" in
	systemd)
		if [[ "${IS_LINUX}" != "true" ]] || ! command -v systemctl >/dev/null 2>&1; then
			return 0
		fi
		labels=$(serviceman_labels_for_dir "${beranodes_dir}" || true)
		if [[ -z "${labels}" ]]; then
			log_info "No systemd user units found for ${beranodes_dir}"
			return 0
		fi
		while IFS= read -r label; do
			[[ -z "${label}" ]] && continue
			log_info "Stopping systemd unit ${label}.service"
			serviceman_systemd_stop_unit "${label}"
			count=$((count + 1))
		done <<<"${labels}"
		serviceman_systemd_prepare_env
		systemctl --user daemon-reload >/dev/null 2>&1 || true
		log_success "Stopped ${count} systemd unit(s)"
		;;
	launchd)
		if [[ "${IS_MACOS}" != "true" ]] || ! command -v launchctl >/dev/null 2>&1; then
			return 0
		fi
		local domain user_plist
		domain=$(serviceman_launchd_domain)
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
		;;
	*)
		return 0
		;;
	esac
	return 0
}

serviceman_any_running() {
	local beranodes_dir="$1"
	local label state labels

	case "$(serviceman_backend)" in
	systemd)
		if [[ "${IS_LINUX}" != "true" ]] || ! command -v systemctl >/dev/null 2>&1; then
			return 1
		fi
		;;
	launchd)
		if [[ "${IS_MACOS}" != "true" ]] || ! command -v launchctl >/dev/null 2>&1; then
			return 1
		fi
		;;
	*)
		return 1
		;;
	esac

	labels=$(serviceman_labels_for_dir "${beranodes_dir}" || true)
	[[ -z "${labels}" ]] && return 1
	while IFS= read -r label; do
		[[ -z "${label}" ]] && continue
		case "$(serviceman_backend)" in
		systemd)
			state=$(serviceman_systemd_service_state "${label}")
			;;
		*)
			state=$(serviceman_launchd_service_state "$(serviceman_launchd_domain)" "${label}")
			;;
		esac
		if [[ "${state}" == "running" ]]; then
			return 0
		fi
	done <<<"${labels}"
	return 1
}

serviceman_prepare_start() {
	local beranodes_dir="$1"
	serviceman_require || return 1
	local abs domain
	abs=$(serviceman_abspath "${beranodes_dir}")
	case "$(serviceman_backend)" in
	systemd)
		log_info "Stopping any existing systemd user units for this node set..."
		serviceman_stop_all "${abs}" || true
		serviceman_systemd_ensure_linger
		serviceman_write_fresh_manifest "${abs}" "user"
		serviceman_write_systemd_runner "$(serviceman_systemd_runner_path "${abs}")"
		;;
	*)
		log_info "Unloading any existing launchd jobs for this node set..."
		serviceman_stop_all "${abs}" || true
		domain=$(serviceman_launchd_domain)
		serviceman_write_fresh_manifest "${abs}" "${domain}"
		;;
	esac
}

serviceman_log_started_hint() {
	local beranodes_dir="$1"
	local abs
	abs=$(serviceman_abspath "${beranodes_dir}")
	log_info "Logs: ${abs}${BERANODES_PATH_LOGS}/"
	case "$(serviceman_backend)" in
	systemd)
		log_info "journald: journalctl --user -u ${SERVICEMAN_LAUNCHD_LABEL_PREFIX}.*.service -f"
		log_info "Units: $(serviceman_systemd_user_dir)/${SERVICEMAN_LAUNCHD_LABEL_PREFIX}.*.service"
		;;
	*)
		log_info "Plists: ${HOME}/Library/LaunchAgents/${SERVICEMAN_LAUNCHD_LABEL_PREFIX}.*.plist"
		;;
	esac
	log_info "Stop with: beranode stop"
}
