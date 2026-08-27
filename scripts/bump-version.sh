#!/usr/bin/env bash
set -euo pipefail
#
# bump-version.sh - SemVer bump, changelog, git tag, and GitHub release
#
# Usage:
#   ./scripts/bump-version.sh patch
#   ./scripts/bump-version.sh minor --tag
#   ./scripts/bump-version.sh major --publish -m "Summary of this release"
#   ./scripts/bump-version.sh 1.2.3 --publish --yes
#   ./scripts/bump-version.sh 1.2.3-rc.1 --publish --prerelease
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONSTANTS_FILE="${CONSTANTS_FILE:-$ROOT_DIR/src/lib/constants.sh}"
DISPATCHER_FILE="${DISPATCHER_FILE:-$ROOT_DIR/src/core/dispatcher.sh}"
BERANODE_FILE="${BERANODE_FILE:-$ROOT_DIR/beranode}"
BUILD_SCRIPT="${BUILD_SCRIPT:-$ROOT_DIR/build.sh}"
CHANGELOG_FILE="${CHANGELOG_FILE:-$ROOT_DIR/CHANGELOG.md}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+(-((rc|alpha|beta|pre)\.?[0-9]+))?$'

usage() {
	cat <<EOF
${BOLD}bump-version.sh${RESET} - Bump version, update changelog, and publish to GitHub

${BOLD}USAGE${RESET}
    ./scripts/bump-version.sh <bump-type|version> [options]
    ./scripts/bump-version.sh --publish --yes
    ./scripts/bump-version.sh --tag --yes
    ./scripts/bump-version.sh --current
    ./scripts/bump-version.sh --notes [version]

${BOLD}BUMP TYPES${RESET}
    patch       Increment patch version (0.1.0 -> 0.1.1)
    minor       Increment minor version (0.1.0 -> 0.2.0)
    major       Increment major version (0.1.0 -> 1.0.0)

${BOLD}EXPLICIT VERSION${RESET}
    X.Y.Z           Set a stable version (e.g. 1.2.3)
    X.Y.Z-rc.N      Set a prerelease (also -alpha.N, -beta.N, -pre.N)

${BOLD}OPTIONS${RESET}
    -h, --help          Show this help message
    --current           Print the current version and exit
    --notes [version]   Print changelog notes for a version and exit
    --dry-run           Show what would change without modifying files
    -y, --yes           Skip confirmation prompt
    --tag               Commit version files and create an annotated git tag
                        (with no bump type: tag the current version)
    --publish           Tag, push, and create a GitHub Release (implies --tag)
                        (with no bump type: publish the current version)
    --draft             Create the GitHub Release as a draft
    --prerelease        Mark the GitHub Release as a prerelease
    --allow-branch      Allow --tag/--publish from a non-default branch
    --allow-dirty       Allow --tag/--publish with unrelated uncommitted files
    --skip-tests        Skip tests that --publish runs by default
    --remote NAME       Git remote to push to (default: origin)
    --repo OWNER/NAME   GitHub repo for changelog links and gh release
    -m, --message TEXT  Release summary for changelog, commit, tag, and GitHub

${BOLD}EXAMPLES${RESET}
    ./scripts/bump-version.sh patch --dry-run
    ./scripts/bump-version.sh minor --tag -m "Add status and stop commands"
    ./scripts/bump-version.sh patch --publish --yes
    ./scripts/bump-version.sh 1.0.0-rc.1 --publish --prerelease
EOF
}

die() {
	echo -e "${RED}Error: $1${RESET}" >&2
	exit 1
}

info() {
	echo -e "${BLUE}$1${RESET}"
}

success() {
	echo -e "  ${GREEN}✓${RESET} $1"
}

warn() {
	echo -e "${YELLOW}Warning: $1${RESET}"
}

is_valid_semver() {
	[[ "${1:-}" =~ $SEMVER_RE ]]
}

core_version() {
	echo "${1%%-*}"
}

is_prerelease_version() {
	[[ "$1" == *-* ]]
}

get_current_version() {
	local line version
	line=$(grep -E '^BERANODE_VERSION=' "$CONSTANTS_FILE" | head -1)
	version="${line#BERANODE_VERSION=}"
	version="${version%%#*}"
	version="${version//\"/}"
	version="${version// /}"
	echo "$version"
}

github_repo() {
	if [[ -n "${GITHUB_REPO:-}" ]]; then
		echo "$GITHUB_REPO"
		return
	fi

	local url
	url=$(git -C "$ROOT_DIR" remote get-url "${REMOTE:-origin}" 2>/dev/null || true)
	url="${url%.git}"
	url="${url%/}"
	if [[ "$url" =~ github.com[:/]([^/]+)/([^/]+)$ ]]; then
		echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
		return
	fi
	echo "berachain/beranode-cli"
}

calculate_new_version() {
	local current="$1"
	local bump_type="$2"
	local core major minor patch

	if [[ "$bump_type" != "major" && "$bump_type" != "minor" && "$bump_type" != "patch" ]]; then
		echo "$bump_type"
		return
	fi

	core=$(core_version "$current")
	IFS='.' read -r major minor patch <<<"$core"

	case "$bump_type" in
	major) echo "$((major + 1)).0.0" ;;
	minor) echo "$major.$((minor + 1)).0" ;;
	patch) echo "$major.$minor.$((patch + 1))" ;;
	esac
}

# Returns 0 if $1 is greater than $2 (numeric core, then prerelease).
version_gt() {
	local a_core b_core a_pre b_pre
	local a_maj a_min a_pat b_maj b_min b_pat

	a_core=$(core_version "$1")
	b_core=$(core_version "$2")
	a_pre="${1#"${a_core}"}"
	b_pre="${2#"${b_core}"}"
	a_pre="${a_pre#-}"
	b_pre="${b_pre#-}"

	IFS='.' read -r a_maj a_min a_pat <<<"$a_core"
	IFS='.' read -r b_maj b_min b_pat <<<"$b_core"

	if ((a_maj != b_maj)); then
		if ((a_maj > b_maj)); then return 0; else return 1; fi
	fi
	if ((a_min != b_min)); then
		if ((a_min > b_min)); then return 0; else return 1; fi
	fi
	if ((a_pat != b_pat)); then
		if ((a_pat > b_pat)); then return 0; else return 1; fi
	fi

	# Same X.Y.Z: a stable release is greater than a prerelease.
	if [[ -z "$a_pre" && -n "$b_pre" ]]; then
		return 0
	fi
	if [[ -n "$a_pre" && -z "$b_pre" ]]; then
		return 1
	fi
	if [[ -n "$a_pre" && -n "$b_pre" && "$a_pre" > "$b_pre" ]]; then
		return 0
	fi
	return 1
}

changelog_has_version() {
	grep -qE "^## \[${1}\]" "$CHANGELOG_FILE" || return 1
	return 0
}

unreleased_has_entries() {
	local hits
	hits=$(awk '/^## \[Unreleased\]/{p=1; next} /^## \[/{exit} p' "$CHANGELOG_FILE" |
		grep -v '^### ' | grep -v '^$' | grep -v '^##' || true)
	[[ -n "$hits" ]]
}

extract_changelog_notes() {
	local version="$1"
	awk -v ver="$version" '
		$0 ~ "^## \\[" ver "\\]" { found = 1; next }
		found && /^## \[/ { exit }
		found { print }
	' "$CHANGELOG_FILE"
}

changed_files_since_version() {
	local old_version="$1"
	if git -C "$ROOT_DIR" rev-parse "v${old_version}" >/dev/null 2>&1; then
		git -C "$ROOT_DIR" diff --name-only "v${old_version}...HEAD" | sed '/^$/d' | sed 's/^/- /'
	fi
}

update_changelog() {
	local new_version="$1"
	local old_version="$2"
	local description="$3"
	local changed_files="$4"
	local today repo tmp
	today=$(date +%Y-%m-%d)
	repo=$(github_repo)
	tmp=$(mktemp -d)

	awk -v d="$tmp" '
		BEGIN { section = "preamble" }
		/^\[[^]]+\]: / { section = "links" }
		/^## \[Unreleased\]/ && section != "links" { section = "unreleased"; next }
		section == "unreleased" && /^## \[/ { section = "versions" }
		{
			if (section == "preamble") print > (d "/preamble")
			else if (section == "unreleased") print > (d "/unreleased")
			else if (section == "versions") print > (d "/versions")
			else if (section == "links") print > (d "/links")
		}
	' "$CHANGELOG_FILE"

	if [[ ! -f "$tmp/versions" ]]; then
		die "CHANGELOG.md is missing a version section after [Unreleased]"
	fi

	{
		if [[ -f "$tmp/preamble" ]]; then
			cat "$tmp/preamble"
		fi
		cat <<'TEMPLATE'
## [Unreleased]

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

TEMPLATE
		echo "## [${new_version}] - ${today}"
		echo ""
		if [[ -n "$description" ]]; then
			echo "### Summary"
			echo ""
			echo "$description"
			echo ""
		fi
		if [[ -n "$changed_files" ]]; then
			echo "### Changed Files"
			echo ""
			echo "$changed_files"
			echo ""
		fi
		if [[ -f "$tmp/unreleased" ]]; then
			cat "$tmp/unreleased"
		fi
		cat "$tmp/versions"
		echo "[Unreleased]: https://github.com/${repo}/compare/v${new_version}...HEAD"
		if [[ -n "$old_version" ]]; then
			echo "[${new_version}]: https://github.com/${repo}/compare/v${old_version}...v${new_version}"
		else
			echo "[${new_version}]: https://github.com/${repo}/releases/tag/v${new_version}"
		fi
		if [[ -f "$tmp/links" ]]; then
			grep -v '^\[Unreleased\]:' "$tmp/links" || true
		fi
	} >"$CHANGELOG_FILE.tmp"
	mv "$CHANGELOG_FILE.tmp" "$CHANGELOG_FILE"
	rm -rf "$tmp"
}

update_constants_version() {
	local new_version="$1"
	sed -i.bak "s/^BERANODE_VERSION=.*/BERANODE_VERSION=\"$new_version\"  # Managed by scripts\/bump-version.sh - do not edit manually/" "$CONSTANTS_FILE"
	rm -f "$CONSTANTS_FILE.bak"
}

update_dispatcher_version_header() {
	local new_version="$1"
	if [[ -f "$DISPATCHER_FILE" ]] && grep -qE '^# VERSION: v[0-9]+\.[0-9]+\.[0-9]+' "$DISPATCHER_FILE"; then
		sed -i.bak -E "s/^# VERSION: v[0-9]+\.[0-9]+\.[0-9]+([^ ]*)? \(Current\)/# VERSION: v${new_version} (Current)/" "$DISPATCHER_FILE"
		rm -f "$DISPATCHER_FILE.bak"
	fi
}

rebuild_beranode() {
	if [[ -x "$BUILD_SCRIPT" ]]; then
		info "Rebuilding beranode..."
		"$BUILD_SCRIPT" >/dev/null
	else
		warn "build.sh not found or not executable; skipped rebuild"
	fi
}

is_release_path() {
	case "$1" in
	CHANGELOG.md | src/lib/constants.sh | src/core/dispatcher.sh | beranode) return 0 ;;
	*) return 1 ;;
	esac
}

default_branch() {
	local branch
	branch=$(git -C "$ROOT_DIR" symbolic-ref refs/remotes/"${REMOTE:-origin}"/HEAD 2>/dev/null | sed 's@^refs/remotes/[^/]*/@@' || true)
	if [[ -n "$branch" ]]; then
		echo "$branch"
		return
	fi
	echo "main"
}

current_branch() {
	git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD
}

require_git_repo() {
	git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not inside a git repository"
}

porcelain_paths() {
	git -C "$ROOT_DIR" status --porcelain | sed 's/^...//'
}

require_clean_worktree() {
	[[ "$ALLOW_DIRTY" == true ]] && return 0
	local path dirty=""
	while IFS= read -r path; do
		[[ -z "$path" ]] && continue
		if is_release_path "$path"; then
			continue
		fi
		dirty="${dirty}  - ${path}"$'\n'
	done <<<"$(porcelain_paths)"
	if [[ -n "$dirty" ]]; then
		echo -e "${RED}Uncommitted files would be left out of the release commit:${RESET}" >&2
		printf '%s' "$dirty" >&2
		die "Commit or stash unrelated changes, or pass --allow-dirty"
	fi
}

confirm() {
	local response
	if [[ "$YES" == true ]]; then
		return 0
	fi
	if [[ ! -t 0 ]]; then
		die "Non-interactive session requires --yes"
	fi
	echo -n "Proceed? [y/N] "
	read -r response
	[[ "$response" =~ ^[Yy]$ ]]
}

run_release_tests() {
	local test_file
	for test_file in "$ROOT_DIR/tests/test_validation.sh" "$ROOT_DIR/tests/test_bump_version.sh" "$ROOT_DIR/tests/test_download.sh"; do
		if [[ -x "$test_file" || -f "$test_file" ]]; then
			info "Running $(basename "$test_file")..."
			bash "$test_file"
		fi
	done
}

release_files() {
	echo "src/lib/constants.sh"
	echo "CHANGELOG.md"
	echo "beranode"
	if [[ -f "$DISPATCHER_FILE" ]]; then
		echo "src/core/dispatcher.sh"
	fi
}

commit_and_tag() {
	local new_version="$1"
	local description="$2"
	local commit_msg tag_msg file

	commit_msg="chore: release v${new_version}"
	tag_msg="Release v${new_version}"
	if [[ -n "$description" ]]; then
		commit_msg="chore: release v${new_version} - ${description}"
		tag_msg="Release v${new_version}

${description}"
	fi

	while IFS= read -r file; do
		git -C "$ROOT_DIR" add "$file"
	done <<<"$(release_files)"

	if git -C "$ROOT_DIR" diff --cached --quiet; then
		warn "No version-file changes to commit"
	else
		git -C "$ROOT_DIR" commit -m "$commit_msg"
		success "Created release commit"
	fi

	if git -C "$ROOT_DIR" rev-parse "v${new_version}" >/dev/null 2>&1; then
		warn "Tag v${new_version} already exists"
	else
		git -C "$ROOT_DIR" tag -a "v${new_version}" -m "$tag_msg"
		success "Created tag v${new_version}"
	fi
}

publish_github_release() {
	local new_version="$1"
	local notes_file="$2"
	local title="beranode v${new_version}"
	local args=()

	command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) is required for --publish. Install it from https://cli.github.com"
	gh auth status >/dev/null 2>&1 || die "GitHub CLI is not authenticated. Run: gh auth login"

	args=(release create "v${new_version}" --repo "$(github_repo)" --title "$title" --notes-file "$notes_file")
	if [[ "$DRAFT" == true ]]; then
		args+=(--draft)
	fi
	if [[ "$PRERELEASE" == true ]] || is_prerelease_version "$new_version"; then
		args+=(--prerelease)
	fi
	if [[ -f "$BERANODE_FILE" ]]; then
		args+=("$BERANODE_FILE")
	fi

	if gh release view "v${new_version}" --repo "$(github_repo)" >/dev/null 2>&1; then
		warn "GitHub Release v${new_version} already exists; uploading beranode if present"
		if [[ -f "$BERANODE_FILE" ]]; then
			gh release upload "v${new_version}" --repo "$(github_repo)" "$BERANODE_FILE" --clobber
		fi
		return 0
	fi

	gh "${args[@]}"
}

show_plan() {
	local current="$1"
	local new="$2"

	echo -e "${BOLD}Version bump:${RESET} $current -> ${GREEN}$new${RESET}"
	echo ""
	echo -e "${BOLD}Files to update:${RESET}"
	echo "  - src/lib/constants.sh (BERANODE_VERSION)"
	echo "  - src/core/dispatcher.sh (VERSION header)"
	echo "  - CHANGELOG.md (promote [Unreleased], add compare links)"
	echo "  - beranode (rebuilt from sources)"
	echo ""
	if [[ "$CREATE_TAG" == true ]]; then
		echo -e "${BOLD}Git:${RESET} commit version files and create annotated tag v${new}"
	fi
	if [[ "$PUBLISH" == true ]]; then
		echo -e "${BOLD}GitHub:${RESET} push $(current_branch) + tag to ${REMOTE}, then create release"
		echo "  repo:     $(github_repo)"
		echo "  release:  https://github.com/$(github_repo)/releases/tag/v${new}"
		if [[ "$DRAFT" == true ]]; then
			echo "  draft:    yes"
		fi
		if [[ "$PRERELEASE" == true ]] || is_prerelease_version "$new"; then
			echo "  prerelease: yes"
		fi
	fi
	if [[ -n "$DESCRIPTION" ]]; then
		echo ""
		echo -e "${BOLD}Summary:${RESET} $DESCRIPTION"
	fi
	echo ""
}

parse_args() {
	DRY_RUN=false
	YES=false
	CREATE_TAG=false
	PUBLISH=false
	DRAFT=false
	PRERELEASE=false
	ALLOW_BRANCH=false
	ALLOW_DIRTY=false
	SKIP_TESTS=false
	REMOTE="origin"
	BUMP_TYPE=""
	DESCRIPTION=""
	SHOW_CURRENT=false
	SHOW_NOTES=false
	NOTES_VERSION=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
		-h | --help)
			usage
			exit 0
			;;
		--current)
			SHOW_CURRENT=true
			shift
			;;
		--notes)
			SHOW_NOTES=true
			if [[ -n "${2:-}" && "$2" != -* ]]; then
				NOTES_VERSION="$2"
				shift 2
			else
				shift
			fi
			;;
		--dry-run)
			DRY_RUN=true
			shift
			;;
		-y | --yes)
			YES=true
			shift
			;;
		--tag)
			CREATE_TAG=true
			shift
			;;
		--publish)
			PUBLISH=true
			CREATE_TAG=true
			shift
			;;
		--draft)
			DRAFT=true
			shift
			;;
		--prerelease)
			PRERELEASE=true
			shift
			;;
		--allow-branch)
			ALLOW_BRANCH=true
			shift
			;;
		--allow-dirty)
			ALLOW_DIRTY=true
			shift
			;;
		--skip-tests)
			SKIP_TESTS=true
			shift
			;;
		--remote)
			[[ -n "${2:-}" ]] || die "--remote requires a remote name"
			REMOTE="$2"
			shift 2
			;;
		--repo)
			[[ -n "${2:-}" ]] || die "--repo requires OWNER/NAME"
			GITHUB_REPO="$2"
			shift 2
			;;
		-m | --message)
			[[ -n "${2:-}" ]] || die "--message requires a description"
			DESCRIPTION="$2"
			shift 2
			;;
		major | minor | patch)
			BUMP_TYPE="$1"
			shift
			;;
		*)
			if is_valid_semver "$1"; then
				BUMP_TYPE="$1"
				shift
			else
				die "Unknown argument: $1"
			fi
			;;
		esac
	done

	if [[ -n "$DESCRIPTION" ]]; then
		DESCRIPTION="${DESCRIPTION//$'\n'/ }"
		while [[ "$DESCRIPTION" == *"  "* ]]; do
			DESCRIPTION="${DESCRIPTION//  / }"
		done
		DESCRIPTION="${DESCRIPTION# }"
		DESCRIPTION="${DESCRIPTION% }"
	fi
}

main() {
	parse_args "$@"

	[[ -f "$CONSTANTS_FILE" ]] || die "constants.sh not found at $CONSTANTS_FILE"
	[[ -f "$CHANGELOG_FILE" ]] || die "CHANGELOG.md not found at $CHANGELOG_FILE"

	if [[ "$SHOW_CURRENT" == true ]]; then
		get_current_version
		exit 0
	fi

	if [[ "$SHOW_NOTES" == true ]]; then
		local notes_ver
		notes_ver="${NOTES_VERSION:-$(get_current_version)}"
		notes_ver="${notes_ver#v}"
		extract_changelog_notes "$notes_ver"
		exit 0
	fi

	local current_version new_version skip_bump=false
	current_version=$(get_current_version)
	is_valid_semver "$current_version" || die "Current version is not valid SemVer: $current_version"

	if [[ -z "$BUMP_TYPE" ]]; then
		if [[ "$CREATE_TAG" == true || "$PUBLISH" == true ]]; then
			BUMP_TYPE="$current_version"
		else
			die "No bump type specified. See --help"
		fi
	fi

	new_version=$(calculate_new_version "$current_version" "$BUMP_TYPE")
	is_valid_semver "$new_version" || die "Invalid SemVer: $new_version"

	if [[ "$current_version" == "$new_version" ]]; then
		if [[ "$CREATE_TAG" == true || "$PUBLISH" == true ]]; then
			skip_bump=true
			info "Version is already $new_version; tagging/publishing without bumping"
		else
			warn "Version unchanged: $current_version"
			exit 0
		fi
	elif ! version_gt "$new_version" "$current_version"; then
		die "New version $new_version is not greater than current $current_version"
	fi

	if [[ "$skip_bump" != true ]] && ! unreleased_has_entries && [[ -z "$DESCRIPTION" ]]; then
		warn "No entries in CHANGELOG [Unreleased] and no --message provided"
	fi

	show_plan "$current_version" "$new_version"

	if [[ "$DRY_RUN" == true ]]; then
		info "Dry run - no changes made"
		exit 0
	fi

	if [[ "$CREATE_TAG" == true || "$PUBLISH" == true ]]; then
		require_git_repo
		if [[ "$ALLOW_BRANCH" != true ]]; then
			local branch def_branch
			branch=$(current_branch)
			def_branch=$(default_branch)
			if [[ "$branch" != "$def_branch" && "$branch" != "main" && "$branch" != "master" ]]; then
				die "Refusing to tag/publish from branch '$branch' (expected $def_branch). Pass --allow-branch to override"
			fi
		fi
		require_clean_worktree
		if [[ "$skip_bump" != true ]] && git -C "$ROOT_DIR" rev-parse "v${new_version}" >/dev/null 2>&1; then
			die "Git tag v${new_version} already exists"
		fi
	fi

	if [[ "$PUBLISH" == true ]]; then
		command -v gh >/dev/null 2>&1 || die "GitHub CLI (gh) is required for --publish. Install it from https://cli.github.com"
		gh auth status >/dev/null 2>&1 || die "GitHub CLI is not authenticated. Run: gh auth login"
	fi

	confirm || {
		echo "Aborted."
		exit 0
	}

	if [[ "$PUBLISH" == true && "$SKIP_TESTS" != true ]]; then
		run_release_tests
	fi

	if [[ "$skip_bump" != true ]]; then
		echo ""
		info "Updating version..."

		local changed_files=""
		if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
			changed_files=$(changed_files_since_version "$current_version" || true)
		fi

		update_constants_version "$new_version"
		success "Updated src/lib/constants.sh"
		update_dispatcher_version_header "$new_version"
		success "Updated src/core/dispatcher.sh version header"
		if changelog_has_version "$new_version"; then
			warn "CHANGELOG.md already has a [$new_version] section; leaving it in place"
		else
			update_changelog "$new_version" "$current_version" "$DESCRIPTION" "$changed_files"
			success "Updated CHANGELOG.md"
		fi
		rebuild_beranode
		success "Rebuilt beranode"

		echo ""
		echo -e "${GREEN}Version bumped to $new_version${RESET}"
	fi

	if [[ "$CREATE_TAG" == true ]]; then
		commit_and_tag "$new_version" "$DESCRIPTION"
	fi

	if [[ "$PUBLISH" == true ]]; then
		local branch notes_file
		branch=$(current_branch)
		info "Pushing ${branch} and tag v${new_version} to ${REMOTE}..."
		git -C "$ROOT_DIR" push "$REMOTE" "$branch"
		git -C "$ROOT_DIR" push "$REMOTE" "v${new_version}"
		success "Pushed branch and tag"

		notes_file=$(mktemp)
		extract_changelog_notes "$new_version" >"$notes_file"
		if [[ ! -s "$notes_file" ]]; then
			echo "Release v${new_version}" >"$notes_file"
		fi
		info "Creating GitHub Release..."
		publish_github_release "$new_version" "$notes_file"
		rm -f "$notes_file"
		echo ""
		echo -e "${GREEN}Published https://github.com/$(github_repo)/releases/tag/v${new_version}${RESET}"
		return 0
	fi

	if [[ "$CREATE_TAG" != true ]]; then
		echo ""
		echo -e "${BOLD}Next steps:${RESET}"
		echo "  1. Review changes: git diff"
		echo "  2. Tag:     ./scripts/bump-version.sh --tag --yes"
		echo "  3. Publish: ./scripts/bump-version.sh --publish --yes"
		echo "     Pushing tag v${new_version} also lets GitHub Actions create the release."
	elif [[ "$PUBLISH" != true ]]; then
		echo ""
		echo -e "${BOLD}Next steps:${RESET}"
		echo "  ./scripts/bump-version.sh --publish --yes"
		echo "  # or:"
		echo "  git push ${REMOTE} $(current_branch) --tags"
	fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	main "$@"
fi
