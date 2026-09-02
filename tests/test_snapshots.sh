#!/usr/bin/env bash
################################################################################
# test_snapshots.sh - Tests for network mapping and snapshot index selection
################################################################################

cd "$(dirname "$0")"
source test_framework.sh

DEBUG_MODE="${DEBUG_MODE:-false}"
source ../src/lib/logging.sh
source ../src/lib/constants.sh
source ../src/lib/network.sh
source ../src/lib/snapshots.sh

test_suite "Network URL and spec mapping"

assert_equals "https://bepolia.snapshots.berachain.com" \
	"$(network_snapshot_host bepolia)" \
	"bepolia snapshot host"
assert_equals "https://snapshots.berachain.com" \
	"$(network_snapshot_host mainnet)" \
	"mainnet snapshot host"
assert_equals "https://bepolia.snapshots.berachain.com/index.csv" \
	"$(network_snapshot_index_url bepolia)" \
	"bepolia index URL"
assert_equals "https://snapshots.berachain.com/index.csv" \
	"$(network_snapshot_index_url mainnet)" \
	"mainnet index URL"
assert_empty "$(network_snapshot_host devnet)" \
	"devnet has no snapshot host"

assert_equals "testnet" "$(network_beacon_chain_spec bepolia)" \
	"bepolia beacond chain-spec is testnet"
assert_equals "mainnet" "$(network_beacon_chain_spec mainnet)" \
	"mainnet beacond chain-spec is mainnet"
assert_equals "devnet" "$(network_beacon_chain_spec devnet)" \
	"devnet beacond chain-spec is devnet"
assert_equals "bepolia" "$(network_reth_chain bepolia)" \
	"bepolia reth --chain is bepolia"
assert_equals "mainnet" "$(network_reth_chain mainnet)" \
	"mainnet reth --chain is mainnet"
assert_empty "$(network_reth_chain devnet)" \
	"devnet has no reth chain preset"

assert_equals "https://bepolia.rpc.berachain.com" \
	"$(network_public_el_rpc bepolia)" \
	"bepolia public EL RPC"
assert_equals "https://rpc.berachain.com" \
	"$(network_public_el_rpc mainnet)" \
	"mainnet public EL RPC"
assert_empty "$(network_public_el_rpc devnet)" \
	"devnet has no public EL RPC"

assert_equals "80069" "$(network_chain_id bepolia)" "bepolia chain id"
assert_equals "80094" "$(network_chain_id mainnet)" "mainnet chain id"
assert_equals "${SEED_DATA_BASE_URL}/80069" "$(network_seed_data_url bepolia)" \
	"bepolia seed-data URL"
assert_equals "${SEED_DATA_BASE_URL}/80094" "$(network_seed_data_url mainnet)" \
	"mainnet seed-data URL"

assert_equals "v1.4.1" "$(network_recommended_beacond_version bepolia)" \
	"bepolia recommended beacond version"
assert_equals "v1.4.4" "$(network_recommended_berareth_version bepolia)" \
	"bepolia recommended bera-reth version"
assert_equals "v1.4.1" "$(network_recommended_beacond_version mainnet)" \
	"mainnet recommended beacond version"

assert_success 'is_public_network bepolia' "bepolia is public"
assert_success 'is_public_network mainnet' "mainnet is public"
assert_failure 'is_public_network devnet' "devnet is not public"

test_suite "Role to snapshot type mapping"

assert_equals "pruned" "$(snapshot_type_for_role validator)" \
	"validator defaults to pruned"
assert_equals "pruned" "$(snapshot_type_for_role rpc-pruned)" \
	"rpc-pruned defaults to pruned"
assert_equals "archive" "$(snapshot_type_for_role rpc-full)" \
	"rpc-full defaults to archive"
assert_equals "archive" "$(snapshot_type_for_role validator archive)" \
	"--snapshot-type archive overrides validator"
assert_equals "pruned" "$(snapshot_type_for_role rpc-full pruned)" \
	"--snapshot-type pruned overrides rpc-full"

NODES_MIXED='[{"role":"validator"},{"role":"rpc-full"},{"role":"rpc-pruned"}]'
assert_equals "pruned archive" "$(snapshot_needed_types "$NODES_MIXED")" \
	"mixed cluster needs pruned and archive"
assert_equals "archive" "$(snapshot_needed_types "$NODES_MIXED" archive)" \
	"override collapses mixed cluster to archive"
assert_equals "pruned" "$(snapshot_needed_types '[{"role":"validator"}]')" \
	"validator-only cluster needs pruned"

assert_success 'reth_uses_pruning validator' "validator uses --full"
assert_failure 'reth_uses_pruning rpc-full' "rpc-full omits --full"
assert_failure 'reth_uses_pruning validator archive' "archive override omits --full"

test_suite "snapshot_select_latest from fixture CSV"

FIXTURE=$(mktemp)
cat >"$FIXTURE" <<'EOF'
url,url_s3,type,size_bytes,created_at,sha256
https://example.com/old-beacon.tar.lz4,https://s3.example/old-beacon.tar.lz4,beacon-kit-pruned,100,2026-08-25T00:00:00Z,aaa
https://example.com/new-beacon.tar.lz4,https://s3.example/new-beacon.tar.lz4,beacon-kit-pruned,200,2026-08-27T00:00:00Z,bbb
https://example.com/el-pruned.tar.lz4,,reth-pruned,10500000000,2026-08-27T00:00:00Z,ccc
https://example.com/el-old.tar.lz4,,reth-pruned,10400000000,2026-08-26T00:00:00Z,ddd
https://example.com/archive-beacon.tar.lz4,,beacon-kit-archive,76800000000,2026-08-27T00:00:00Z,eee
EOF

BEACON_ROW=$(snapshot_select_latest "$FIXTURE" "beacon-kit-pruned")
assert_equals "https://s3.example/new-beacon.tar.lz4" \
	"$(echo "$BEACON_ROW" | awk -F'\t' '{print $1}')" \
	"picks newest beacon-kit-pruned and prefers url_s3"
assert_equals "200" \
	"$(echo "$BEACON_ROW" | awk -F'\t' '{print $2}')" \
	"returns size_bytes for newest row"
assert_equals "bbb" \
	"$(echo "$BEACON_ROW" | awk -F'\t' '{print $4}')" \
	"returns sha256 when present"

EL_ROW=$(snapshot_select_latest "$FIXTURE" "reth-pruned")
assert_equals "https://example.com/el-pruned.tar.lz4" \
	"$(echo "$EL_ROW" | awk -F'\t' '{print $1}')" \
	"falls back to url when url_s3 is empty"
assert_equals "10500000000" \
	"$(echo "$EL_ROW" | awk -F'\t' '{print $2}')" \
	"picks newest reth-pruned by created_at"

assert_failure 'snapshot_select_latest "'"$FIXTURE"'" "reth-archive"' \
	"missing type fails"

assert_equals "10.5 GB" "$(format_bytes 11274289152)" "formats ~10.5 GB"
assert_equals "unknown size" "$(format_bytes "")" "empty size is unknown"

rm -f "$FIXTURE"

test_suite "require_snapshot_tools"

if command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1 && command -v lz4 >/dev/null 2>&1; then
	assert_success 'require_snapshot_tools' "passes when curl, tar, and lz4 are on PATH"
else
	echo "  (skip) require_snapshot_tools success — curl/tar/lz4 not all installed"
fi

FAKE_BIN=$(mktemp -d)
ln -sf "$(command -v curl)" "$FAKE_BIN/curl"
ln -sf "$(command -v tar)" "$FAKE_BIN/tar"
assert_failure "PATH='$FAKE_BIN' require_snapshot_tools" "fails when lz4 is missing"

FAKE_BIN_NO_TAR=$(mktemp -d)
ln -sf "$(command -v curl)" "$FAKE_BIN_NO_TAR/curl"
if command -v lz4 >/dev/null 2>&1; then
	ln -sf "$(command -v lz4)" "$FAKE_BIN_NO_TAR/lz4"
fi
assert_failure "PATH='$FAKE_BIN_NO_TAR' require_snapshot_tools" "fails when tar is missing"
rm -rf "$FAKE_BIN" "$FAKE_BIN_NO_TAR"

test_suite "Local latest snapshot aliases"

assert_equals "bepolia-beacond-pruned-latest.tar.lz4" \
	"$(snapshot_latest_basename bepolia beacond pruned)" \
	"bepolia beacond pruned latest name"
assert_equals "bepolia-reth-pruned-latest.tar.lz4" \
	"$(snapshot_latest_basename bepolia reth pruned)" \
	"bepolia reth pruned latest name"
assert_equals "mainnet-beacond-archive-latest.tar.lz4" \
	"$(snapshot_latest_basename mainnet beacond archive)" \
	"mainnet beacond archive latest name"

LATEST_DIR=$(mktemp -d)
touch "${LATEST_DIR}/bepolia-beacond-pruned-latest.tar.lz4"
touch "${LATEST_DIR}/bepolia-reth-pruned-latest.tar.lz4"
assert_equals "${LATEST_DIR}/bepolia-beacond-pruned-latest.tar.lz4" \
	"$(snapshot_local_latest_path "$LATEST_DIR" bepolia beacond pruned)" \
	"finds local beacond pruned-latest"
assert_equals "${LATEST_DIR}/bepolia-reth-pruned-latest.tar.lz4" \
	"$(snapshot_local_latest_path "$LATEST_DIR" bepolia reth pruned)" \
	"finds local reth pruned-latest"
assert_empty "$(snapshot_local_latest_path "$LATEST_DIR" bepolia beacond archive || true)" \
	"missing archive-latest is empty"
assert_equals "${LATEST_DIR}/bepolia-beacond-pruned-latest.tar.lz4" \
	"$(snapshot_archive_path "$LATEST_DIR" beacon-kit pruned)" \
	"restore path prefers beacond-pruned-latest alias"
assert_equals "${LATEST_DIR}/bepolia-reth-pruned-latest.tar.lz4" \
	"$(snapshot_archive_path "$LATEST_DIR" reth pruned)" \
	"restore path prefers reth-pruned-latest alias"
# Non-TTY stdin keeps existing files (return 1) instead of overwriting.
assert_failure 'prompt_overwrite_local_snapshots "'"$LATEST_DIR"'/bepolia-beacond-pruned-latest.tar.lz4" "'"$LATEST_DIR"'/bepolia-reth-pruned-latest.tar.lz4"' \
	"non-interactive prompt keeps local snapshots"
rm -rf "$LATEST_DIR"

test_suite "Extract archives into snapshots/beacond and snapshots/reth"

assert_equals "/tmp/snapshots/beacond" \
	"$(snapshot_extract_dir /tmp/snapshots beacond)" \
	"beacond unzip dir is snapshots/beacond"
assert_equals "/tmp/snapshots/reth" \
	"$(snapshot_extract_dir /tmp/snapshots reth)" \
	"reth unzip dir is snapshots/reth"

EMPTY_SRC=$(mktemp -d)
assert_equals "$EMPTY_SRC" \
	"$(snapshot_restore_copy_source "$EMPTY_SRC")" \
	"copy source is extract root when it has no data/ or DBs"
rm -rf "$EMPTY_SRC"

COPY_SRC=$(mktemp -d)
mkdir -p "${COPY_SRC}/application.db"
assert_equals "$COPY_SRC" \
	"$(snapshot_restore_copy_source "$COPY_SRC")" \
	"official beacond layout (DBs at tar root) copies from extract root"
rm -rf "$COPY_SRC"
COPY_SRC=$(mktemp -d)
mkdir -p "${COPY_SRC}/data/application.db"
assert_equals "${COPY_SRC}/data" \
	"$(snapshot_restore_copy_source "$COPY_SRC")" \
	"data/-prefixed beacond tarball copies from extract/data"
rm -rf "$COPY_SRC"

if command -v lz4 >/dev/null 2>&1; then
	SNAP_ROOT=$(mktemp -d)
	# Official layout: CometBFT DBs at the archive root (not under data/).
	mkdir -p "${SNAP_ROOT}/payload/application.db"
	echo "snapshot-db" >"${SNAP_ROOT}/payload/application.db/CURRENT"
	(cd "${SNAP_ROOT}/payload" && tar cf - application.db | lz4 -c >"${SNAP_ROOT}/bepolia-beacond-pruned-latest.tar.lz4")
	mkdir -p "${SNAP_ROOT}/el/db"
	echo "reth-db" >"${SNAP_ROOT}/el/db/mdbx.dat"
	(cd "${SNAP_ROOT}/el" && tar cf - db | lz4 -c >"${SNAP_ROOT}/bepolia-reth-pruned-latest.tar.lz4")

	assert_success 'extract_lz4_tar "'"${SNAP_ROOT}/bepolia-beacond-pruned-latest.tar.lz4"'" "'"${SNAP_ROOT}/beacond"'"' \
		"extracts beacond archive with lz4 -dc | tar -xvf - -C"
	assert_equals "snapshot-db" "$(cat "${SNAP_ROOT}/beacond/application.db/CURRENT")" \
		"official beacond tarball unzips DBs at snapshots/beacond root"

	assert_success 'extract_lz4_tar "'"${SNAP_ROOT}/bepolia-reth-pruned-latest.tar.lz4"'" "'"${SNAP_ROOT}/reth"'"' \
		"extracts reth archive with lz4 -dc | tar -xvf - -C"
	assert_equals "reth-db" "$(cat "${SNAP_ROOT}/reth/db/mdbx.dat")" \
		"bepolia-reth-pruned-latest.tar.lz4 unzips into snapshots/reth"

	DEST_LIST=$(mktemp)
	NODE_DEST="${SNAP_ROOT}/nodes/0-validator/beacond/data"
	mkdir -p "${NODE_DEST}/application.db"
	echo "empty-init" >"${NODE_DEST}/application.db/CURRENT"
	echo "keep-me" >"${NODE_DEST}/priv_validator_state.json"
	echo "$NODE_DEST" >"$DEST_LIST"
	assert_success 'snapshot_restore_layer "'"${SNAP_ROOT}/bepolia-beacond-pruned-latest.tar.lz4"'" "'"${SNAP_ROOT}/beacond"'" "'"$DEST_LIST"'"' \
		"restore extracts then copies into node beacond/data"
	assert_equals "snapshot-db" "$(cat "${SNAP_ROOT}/beacond/application.db/CURRENT")" \
		"restore keeps unzipped tree in snapshots/beacond"
	assert_equals "snapshot-db" "$(cat "${NODE_DEST}/application.db/CURRENT")" \
		"restore copies CometBFT DBs into beacond/data"
	assert_equals "keep-me" "$(cat "${NODE_DEST}/priv_validator_state.json")" \
		"restore does not overwrite priv_validator_state.json"
	assert_failure 'test -d "'"${SNAP_ROOT}/nodes/0-validator/beacond/application.db"'"' \
		"restore does not leave DBs in the beacond home"
	rm -f "$DEST_LIST"

	REST_ROOT=$(mktemp -d)
	mkdir -p "${REST_ROOT}/snapshots" "${REST_ROOT}/nodes/0-validator/beacond/data" "${REST_ROOT}/nodes/0-validator/bera-reth"
	cp "${SNAP_ROOT}/bepolia-beacond-pruned-latest.tar.lz4" "${REST_ROOT}/snapshots/"
	cp "${SNAP_ROOT}/bepolia-reth-pruned-latest.tar.lz4" "${REST_ROOT}/snapshots/"
	echo "bepolia-beacond-pruned-latest.tar.lz4" >"${REST_ROOT}/snapshots/beacon-kit-pruned.name"
	echo "bepolia-reth-pruned-latest.tar.lz4" >"${REST_ROOT}/snapshots/reth-pruned.name"
	mkdir -p "${REST_ROOT}/nodes/0-validator/beacond/data/application.db"
	echo "empty-init" >"${REST_ROOT}/nodes/0-validator/beacond/data/application.db/CURRENT"
	mkdir -p "${REST_ROOT}/nodes/0-validator/beacond/state.db"
	echo "stray" >"${REST_ROOT}/nodes/0-validator/beacond/state.db/CURRENT"
	assert_success 'restore_network_snapshots "'"$REST_ROOT"'" '"'"'[{"role":"validator"}]'"'"' pruned false' \
		"restore_network_snapshots succeeds for a validator node"
	assert_equals "snapshot-db" "$(cat "${REST_ROOT}/nodes/0-validator/beacond/data/application.db/CURRENT")" \
		"restore_network_snapshots copies DBs into beacond/data"
	assert_failure 'test -d "'"${REST_ROOT}/nodes/0-validator/beacond/application.db"'"' \
		"restore_network_snapshots does not copy DBs into the beacond home"
	assert_failure 'test -d "'"${REST_ROOT}/nodes/0-validator/beacond/state.db"'"' \
		"restore_network_snapshots removes stray DBs left in the beacond home"
	assert_equals "reth-db" "$(cat "${REST_ROOT}/nodes/0-validator/bera-reth/db/mdbx.dat")" \
		"restore_network_snapshots still copies reth into bera-reth"
	rm -rf "$REST_ROOT"

	# data/-prefixed tarball must unwrap into beacond/data, not beacond/data/data.
	WRAP_ROOT=$(mktemp -d)
	mkdir -p "${WRAP_ROOT}/payload/data/state.db"
	echo "wrapped" >"${WRAP_ROOT}/payload/data/state.db/CURRENT"
	(cd "${WRAP_ROOT}/payload" && tar cf - data | lz4 -c >"${WRAP_ROOT}/wrapped.tar.lz4")
	WRAP_DEST="${WRAP_ROOT}/node/beacond/data"
	WRAP_LIST=$(mktemp)
	echo "$WRAP_DEST" >"$WRAP_LIST"
	assert_success 'snapshot_restore_layer "'"${WRAP_ROOT}/wrapped.tar.lz4"'" "'"${WRAP_ROOT}/extract"'" "'"$WRAP_LIST"'"' \
		"restore unwraps data/ prefix"
	assert_equals "wrapped" "$(cat "${WRAP_DEST}/state.db/CURRENT")" \
		"data/-prefixed archive lands in beacond/data, not data/data"
	assert_failure 'test -d "'"${WRAP_DEST}/data"'"' \
		"restore does not nest data/ under beacond/data"
	rm -f "$WRAP_LIST"
	rm -rf "$WRAP_ROOT" "$SNAP_ROOT"
else
	echo "  (skip) extract_lz4_tar — lz4 not installed"
fi

test_suite "EL enode parsing and merge"

ENODE_DIR=$(mktemp -d)
cat >"${ENODE_DIR}/el-bootnodes.txt" <<'EOF'
enode://aaa@1.1.1.1:30303,enode://bbb@2.2.2.2:30303
EOF
assert_equals "enode://aaa@1.1.1.1:30303,enode://bbb@2.2.2.2:30303" \
	"$(parse_el_enodes "${ENODE_DIR}/el-bootnodes.txt")" \
	"parses comma-separated bootnodes on one line"

cat >"${ENODE_DIR}/el-peers.txt" <<'EOF'
South Korea

enode://ccc@3.3.3.3:30303
enode://ddd@4.4.4.4:30303

Singapore

enode://eee@5.5.5.5:30303
EOF
assert_equals "enode://ccc@3.3.3.3:30303,enode://ddd@4.4.4.4:30303,enode://eee@5.5.5.5:30303" \
	"$(parse_el_enodes "${ENODE_DIR}/el-peers.txt")" \
	"parses one-enode-per-line peers and skips region headers"

assert_empty "$(parse_el_enodes "${ENODE_DIR}/missing.txt")" \
	"missing enode file yields empty"

assert_equals "enode://local@127.0.0.1:30303,enode://aaa@1.1.1.1:30303" \
	"$(merge_enodes "enode://local@127.0.0.1:30303" "enode://aaa@1.1.1.1:30303")" \
	"merge_enodes joins local then official"
assert_equals "enode://aaa@1.1.1.1:30303" \
	"$(merge_enodes "" "enode://aaa@1.1.1.1:30303")" \
	"merge_enodes skips empty local list"
assert_empty "$(merge_enodes "" "")" \
	"merge_enodes of empties is empty"

assert_empty "$(resolve_reth_enodes bepolia "enode://local@127.0.0.1:30303" "")" \
	"public network omits auto bootnodes without an explicit override"
assert_empty "$(resolve_reth_enodes mainnet "enode://local@127.0.0.1:30303" "")" \
	"mainnet omits auto bootnodes without an explicit override"
assert_equals "enode://explicit@9.9.9.9:30303" \
	"$(resolve_reth_enodes bepolia "enode://local@127.0.0.1:30303" "enode://explicit@9.9.9.9:30303")" \
	"public network uses only the explicit override"
assert_equals "enode://local@127.0.0.1:30303" \
	"$(resolve_reth_enodes devnet "enode://local@127.0.0.1:30303" "")" \
	"devnet keeps local cluster enodes"
assert_equals "enode://local@127.0.0.1:30303,enode://explicit@9.9.9.9:30303" \
	"$(resolve_reth_enodes devnet "enode://local@127.0.0.1:30303" "enode://explicit@9.9.9.9:30303")" \
	"devnet merges local cluster with explicit override"

assert_equals "enode://aaa@127.0.0.1:30303,enode://bbb@127.0.0.1:30403" \
	"$(format_reth_enodes_at_host 127.0.0.1 aaa 30303 bbb 30403)" \
	"formats cluster enodes at 127.0.0.1 (not localhost)"
assert_equals "enode://aaa@0-val-bera-reth:30303" \
	"$(format_reth_enodes_at_host 0-val-bera-reth aaa 30303)" \
	"formats a docker service-name enode"
assert_empty "$(format_reth_enodes_at_host 127.0.0.1)" \
	"no pubkey/port pairs yields empty"
assert_empty "$(format_reth_enodes_at_host "")" \
	"empty host yields empty"
rm -rf "$ENODE_DIR"

test_suite "EL websocket flags"

assert_empty "$(format_reth_ws_flags false "" "" "")" \
	"omits --ws flags when --ws is not set"
assert_empty "$(format_reth_ws_flags "" "" "" "")" \
	"omits --ws flags when enabled is empty"
assert_equals "$(printf '%s\n' --ws --ws.addr=0.0.0.0 --ws.port=8546 '--ws.origins=*')" \
	"$(format_reth_ws_flags true "" "" "")" \
	"--ws alone uses default addr, port, and origins"
assert_equals "$(printf '%s\n' --ws --ws.addr=127.0.0.1 --ws.port=8546 '--ws.origins=*')" \
	"$(format_reth_ws_flags true "127.0.0.1" "" "")" \
	"--ws.addr overrides the default bind address"
assert_equals "$(printf '%s\n' --ws --ws.addr=0.0.0.0 --ws.port=9999 '--ws.origins=*')" \
	"$(format_reth_ws_flags true "" "9999" "")" \
	"--ws.port overrides the default port"
assert_equals "$(printf '%s\n' --ws --ws.addr=0.0.0.0 --ws.port=8546 '--ws.origins=https://app.example')" \
	"$(format_reth_ws_flags true "" "" "https://app.example")" \
	"--ws.origin overrides the default origins"
assert_equals "$(printf '%s\n' --ws --ws.addr=0.0.0.0 --ws.port=18546 '--ws.origins=*')" \
	"$(format_reth_ws_flags true "" "" "" "18546")" \
	"default port can come from the node's el_ws_port"

test_suite "Version tag regex accepts rc.0"

assert_success '[[ "v1.4.2-rc.0" =~ $VERSION_TAG_REGEX ]]' "v1.4.2-rc.0 is valid"
assert_success '[[ "v1.4.1" =~ $VERSION_TAG_REGEX ]]' "v1.4.1 is valid"
assert_success '[[ "latest" =~ $VERSION_TAG_REGEX ]]' "latest is valid"
assert_failure '[[ "1.4.1" =~ $VERSION_TAG_REGEX ]]' "missing v prefix is invalid"

print_results
