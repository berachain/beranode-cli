#!/usr/bin/env bash
################################################################################
# test_bump_version.sh - Tests for scripts/bump-version.sh
################################################################################

cd "$(dirname "$0")"
source test_framework.sh

# Source helpers without running main
# shellcheck source=../scripts/bump-version.sh
source ../scripts/bump-version.sh

test_suite "SemVer validation"

assert_success 'is_valid_semver "0.9.0"' "0.9.0 is valid"
assert_success 'is_valid_semver "1.2.3"' "1.2.3 is valid"
assert_success 'is_valid_semver "1.2.3-rc.1"' "1.2.3-rc.1 is valid"
assert_success 'is_valid_semver "1.0.0-alpha.1"' "1.0.0-alpha.1 is valid"
assert_success 'is_valid_semver "2.0.0-beta.2"' "2.0.0-beta.2 is valid"
assert_failure 'is_valid_semver "v0.9.0"' "v-prefix is not valid"
assert_failure 'is_valid_semver "0.9"' "incomplete version is invalid"
assert_failure 'is_valid_semver "1.2.3-rc"' "prerelease without number is invalid"
assert_failure 'is_valid_semver ""' "empty string is invalid"

test_suite "Version calculation"

assert_equals "0.9.1" "$(calculate_new_version "0.9.0" "patch")" "patch bump"
assert_equals "0.10.0" "$(calculate_new_version "0.9.0" "minor")" "minor bump"
assert_equals "1.0.0" "$(calculate_new_version "0.9.0" "major")" "major bump"
assert_equals "2.5.3" "$(calculate_new_version "0.9.0" "2.5.3")" "explicit version"
assert_equals "0.9.1" "$(calculate_new_version "0.9.0-rc.1" "patch")" "patch uses numeric core of prerelease"
assert_equals "1.0.0-rc.1" "$(calculate_new_version "0.9.0" "1.0.0-rc.1")" "explicit prerelease"

test_suite "Version comparison"

assert_success 'version_gt "0.9.1" "0.9.0"' "patch is greater"
assert_success 'version_gt "0.10.0" "0.9.9"' "minor is greater"
assert_success 'version_gt "1.0.0" "0.9.0"' "major is greater"
assert_success 'version_gt "1.0.0" "1.0.0-rc.1"' "stable is greater than prerelease"
assert_success 'version_gt "1.0.0-rc.2" "1.0.0-rc.1"' "later prerelease is greater"
assert_failure 'version_gt "0.9.0" "0.9.1"' "older patch is not greater"
assert_failure 'version_gt "1.0.0-rc.1" "1.0.0"' "prerelease is not greater than stable"
assert_failure 'version_gt "0.9.0" "0.9.0"' "equal versions are not greater"

test_suite "Prerelease detection"

assert_success 'is_prerelease_version "1.0.0-rc.1"' "rc is a prerelease"
assert_failure 'is_prerelease_version "1.0.0"' "stable is not a prerelease"

test_suite "Core version"

assert_equals "1.2.3" "$(core_version "1.2.3")" "stable core is unchanged"
assert_equals "1.2.3" "$(core_version "1.2.3-rc.1")" "prerelease core strips suffix"

test_suite "Changelog notes extraction"

CHANGELOG_FILE=$(mktemp)
trap 'rm -f "$CHANGELOG_FILE"' EXIT
cat >"$CHANGELOG_FILE" <<'EOF'
# Changelog

## [Unreleased]

### Added

- upcoming

## [1.0.0] - 2026-08-01

### Summary

First stable release

### Added

- feature a

## [0.9.0] - 2026-02-16

### Added

- older item

[Unreleased]: https://github.com/berachain/beranode-cli/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/berachain/beranode-cli/compare/v0.9.0...v1.0.0
[0.9.0]: https://github.com/berachain/beranode-cli/releases/tag/v0.9.0
EOF

notes=$(extract_changelog_notes "1.0.0")
assert_contains "$notes" "First stable release" "notes include summary"
assert_contains "$notes" "feature a" "notes include added items"
assert_not_contains "$notes" "upcoming" "notes do not include unreleased"
assert_not_contains "$notes" "older item" "notes do not include previous version"

test_suite "Changelog promotion"

GITHUB_REPO="berachain/beranode-cli"
update_changelog "1.1.0" "1.0.0" "Bump tooling" "- README.md"
promoted=$(cat "$CHANGELOG_FILE")
assert_contains "$promoted" "## [1.1.0] - " "new version section exists"
assert_contains "$promoted" "Bump tooling" "summary is included"
assert_contains "$promoted" "- README.md" "changed files are included"
assert_contains "$promoted" "- upcoming" "unreleased entries are preserved"
assert_contains "$promoted" "[Unreleased]: https://github.com/berachain/beranode-cli/compare/v1.1.0...HEAD" "unreleased compare link updated"
assert_contains "$promoted" "[1.1.0]: https://github.com/berachain/beranode-cli/compare/v1.0.0...v1.1.0" "new version compare link added"
assert_contains "$promoted" "## [1.0.0] - 2026-08-01" "previous version remains"
assert_success 'changelog_has_version "1.1.0"' "changelog reports new version"

# After promotion, Unreleased should be an empty template
CHANGELOG_FILE="$CHANGELOG_FILE" # keep using temp file
assert_failure 'unreleased_has_entries' "unreleased is empty after promotion"

test_suite "CLI helpers"

assert_equals "0.9.0" "$(../scripts/bump-version.sh --current)" "--current prints BERANODE_VERSION"
assert_success '../scripts/bump-version.sh --help >/dev/null' "--help exits successfully"
assert_success '../scripts/bump-version.sh patch --dry-run --yes >/dev/null' "dry-run patch exits successfully"

print_results
