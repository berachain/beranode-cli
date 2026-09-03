#!/usr/bin/env bash
################################################################################
# test_init.sh - Tests for init re-initialize / fresh-start wipe
################################################################################

cd "$(dirname "$0")"
source test_framework.sh

DEBUG_MODE="${DEBUG_MODE:-false}"
source ../src/lib/logging.sh
source ../src/lib/constants.sh
source ../src/lib/argparse.sh

serviceman_stop_all() {
	: # no-op for unit tests
}

source ../src/commands/init.sh

TEST_ROOT=$(mktemp -d "${PWD}/.tmp-test-init.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT

seed_beranodes_tree() {
	local root="$1"
	mkdir -p "${root}/nodes/0-validator" "${root}/bin" "${root}/tmp" "${root}/logs"
	echo '{}' >"${root}/beranodes.config.json"
	echo 'binary' >"${root}/bin/beacond"
}

test_suite "init --help mentions force flags"

help_out="$(show_init_help)"
assert_contains "$help_out" "--force" "help mentions --force"
assert_contains "$help_out" "--yes" "help mentions --yes"
assert_contains "$help_out" "-y" "help mentions -y"
assert_contains "$help_out" "Wipe an existing beranodes directory" \
	"help describes a fresh-start wipe"
assert_contains "$help_out" "includes snapshots/" \
	"help says --force also deletes snapshots/"
assert_contains "$help_out" "--vals" "help mentions --vals alias"
assert_contains "$help_out" "--rpcs" "help mentions --rpcs"
assert_contains "$help_out" "--snapshot-type" "help mentions --snapshot-type"
assert_contains "$help_out" "default: pruned" "snapshot-type defaults to pruned"
assert_failure 'echo "$help_out" | grep -q -- "--full-nodes"' \
	"help no longer mentions --full-nodes"
assert_failure 'echo "$help_out" | grep -q -- "--pruned-nodes"' \
	"help no longer mentions --pruned-nodes"

test_suite "split_equals_flag"

split=$(split_equals_flag "--snapshot-type=archive")
assert_equals $'--snapshot-type\tarchive' "$split" \
	"--snapshot-type=archive splits into flag and value"
split=$(split_equals_flag "--vals=2")
assert_equals $'--vals\t2' "$split" \
	"--vals=2 splits into flag and value"
assert_failure 'split_equals_flag --snapshot-type' \
	"space-separated flags are not equals-form"

test_suite "init_reinit_existing_beranodes"

MISSING="${TEST_ROOT}/missing"
assert_success 'init_reinit_existing_beranodes "'"$MISSING"'" true' \
	"missing directory is a no-op with --force"
assert_success 'init_reinit_existing_beranodes "'"$MISSING"'" false' \
	"missing directory is a no-op without --force"

KEEP="${TEST_ROOT}/keep"
seed_beranodes_tree "$KEEP"
assert_failure 'echo n | init_reinit_existing_beranodes "'"$KEEP"'" false' \
	"answering n leaves the tree and aborts"
assert_file_exists "${KEEP}/beranodes.config.json" "config remains after decline"
assert_dir_exists "${KEEP}/nodes" "nodes remain after decline"

WIPE="${TEST_ROOT}/wipe"
seed_beranodes_tree "$WIPE"
mkdir -p "${WIPE}/snapshots/bepolia"
echo 'archive' >"${WIPE}/snapshots/bepolia/keep-me.tar.lz4"
assert_success 'echo y | init_reinit_existing_beranodes "'"$WIPE"'" false' \
	"answering y wipes the tree but keeps snapshots/"
assert_dir_exists "${WIPE}/snapshots/bepolia" "prompted re-init preserves snapshots/"
assert_file_exists "${WIPE}/snapshots/bepolia/keep-me.tar.lz4" \
	"prompted re-init keeps snapshot archives"
assert_failure 'test -e "'"$WIPE"'/beranodes.config.json"' \
	"prompted re-init removes config"

FORCE="${TEST_ROOT}/force"
seed_beranodes_tree "$FORCE"
mkdir -p "${FORCE}/snapshots/bepolia"
echo 'archive' >"${FORCE}/snapshots/bepolia/keep-me.tar.lz4"
assert_success 'init_reinit_existing_beranodes "'"$FORCE"'" true' \
	"--force wipes without a prompt"
assert_failure 'test -d "'"$FORCE"'"' "directory is removed after --force"
assert_failure 'test -d "'"$FORCE"'/snapshots"' "snapshots/ is removed with --force"

YES_ALIAS="${TEST_ROOT}/yes-alias"
seed_beranodes_tree "$YES_ALIAS"
assert_success 'init_reinit_existing_beranodes "'"$YES_ALIAS"'" true' \
	"--yes/-y share the same force path as --force"

print_results
