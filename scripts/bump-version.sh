#!/usr/bin/env bash
#
# bump-version.sh - Bump version following SemVer conventions
#
# Usage:
#   ./scripts/bump-version.sh patch   # 0.1.0 -> 0.1.1
#   ./scripts/bump-version.sh minor   # 0.1.0 -> 0.2.0
#   ./scripts/bump-version.sh major   # 0.1.0 -> 1.0.0
#   ./scripts/bump-version.sh 1.2.3   # Set explicit version
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
CONSTANTS_FILE="$ROOT_DIR/src/lib/constants.sh"
BERANODE_FILE="$ROOT_DIR/beranode"
BUILD_SCRIPT="$ROOT_DIR/build.sh"
CHANGELOG_FILE="$ROOT_DIR/CHANGELOG.md"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

usage() {
    cat << EOF
${BOLD}bump-version.sh${RESET} - Bump version following SemVer conventions

${BOLD}USAGE${RESET}
    ./scripts/bump-version.sh <bump-type|version>

${BOLD}BUMP TYPES${RESET}
    patch       Increment patch version (0.1.0 -> 0.1.1)
    minor       Increment minor version (0.1.0 -> 0.2.0)
    major       Increment major version (0.1.0 -> 1.0.0)

${BOLD}EXPLICIT VERSION${RESET}
    X.Y.Z       Set to specific version (e.g., 1.2.3)

${BOLD}OPTIONS${RESET}
    -h, --help          Show this help message
    --dry-run           Show what would change without modifying files
    --tag               Create a git tag after bumping
    -m, --message TEXT  Description of changes for commit/tag message

${BOLD}EXAMPLES${RESET}
    ./scripts/bump-version.sh patch
    ./scripts/bump-version.sh minor --tag
    ./scripts/bump-version.sh 2.0.0 --dry-run
    ./scripts/bump-version.sh patch --tag -m "Fix authentication bug"
EOF
}

get_current_version() {
    grep -E '^BERANODE_VERSION=' "$CONSTANTS_FILE" | sed 's/BERANODE_VERSION="//' | sed 's/".*//'
}

validate_semver() {
    local version="$1"
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${RED}Error: Invalid SemVer format: $version${RESET}"
        echo "Version must be in format X.Y.Z (e.g., 1.2.3)"
        exit 1
    fi
}

calculate_new_version() {
    local current="$1"
    local bump_type="$2"

    IFS='.' read -r major minor patch <<< "$current"

    case "$bump_type" in
        major)
            echo "$((major + 1)).0.0"
            ;;
        minor)
            echo "$major.$((minor + 1)).0"
            ;;
        patch)
            echo "$major.$minor.$((patch + 1))"
            ;;
        *)
            # Explicit version provided
            echo "$bump_type"
            ;;
    esac
}

update_beranode_version() {
    local new_version="$1"

    # Update the source file (replace entire line including any existing comments)
    sed -i.bak "s/^BERANODE_VERSION=.*/BERANODE_VERSION=\"$new_version\"  # Managed by scripts\/bump-version.sh - do not edit manually/" "$CONSTANTS_FILE"
    rm -f "$CONSTANTS_FILE.bak"

    # Rebuild the beranode file
    if [[ -x "$BUILD_SCRIPT" ]]; then
        echo -e "${BLUE}Rebuilding beranode...${RESET}"
        "$BUILD_SCRIPT" > /dev/null 2>&1
    else
        echo -e "${YELLOW}Warning: build.sh not found or not executable${RESET}"
    fi
}

update_changelog() {
    local new_version="$1"
    local old_version="$2"
    local description="$3"
    local today
    today=$(date +%Y-%m-%d)

    # Check if there are unreleased changes
    local unreleased_content
    unreleased_content=$(sed -n '/^## \[Unreleased\]/,/^## \[/p' "$CHANGELOG_FILE" | sed '$d')

    # Check if unreleased section has any content beyond headers
    local has_changes
    has_changes=$(echo "$unreleased_content" | grep -v '^## \[Unreleased\]' | grep -v '^$' | grep -v '^### ' | head -1)

    if [[ -z "$has_changes" && -z "$description" ]]; then
        echo -e "${YELLOW}Warning: No changes documented in [Unreleased] section${RESET}"
        echo "Consider adding changelog entries before releasing."
        echo ""
    fi

    # Update the file using awk for more reliable multi-line replacement
    awk -v new_ver="$new_version" -v today="$today" -v old_ver="$old_version" -v desc="$description" '
    /^## \[Unreleased\]/ {
        print "## [Unreleased]"
        print ""
        print "### Added"
        print ""
        print "### Changed"
        print ""
        print "### Deprecated"
        print ""
        print "### Removed"
        print ""
        print "### Fixed"
        print ""
        print "### Security"
        print ""
        in_unreleased = 1
        next
    }
    # Skip all content of the old [Unreleased] section until we hit the next version header
    in_unreleased && /^## \[/ {
        print "## [" new_ver "] - " today
        print ""

        # Add Summary section if description is provided
        if (desc != "") {
            print "### Summary"
            print ""
            print desc
            print ""
        }

        # Add Changed Files section
        print "### Changed Files"
        print ""
        print "- `src/lib/constants.sh` - Updated BERANODE_VERSION to " new_ver
        print "- `beranode` - Rebuilt from sources"
        print "- `CHANGELOG.md` - Updated with release " new_ver
        print ""

        # Add standard changelog sections
        print "### Added"
        print ""
        print "### Changed"
        print ""
        print "### Deprecated"
        print ""
        print "### Removed"
        print ""
        print "### Fixed"
        print ""
        print "### Security"
        print ""

        in_unreleased = 0
        # Print the old version header that we just encountered
        print
        next
    }
    # Skip lines while we are still in the unreleased section
    in_unreleased {
        next
    }
    # Update the comparison links at the bottom
    /^\[Unreleased\]:/ {
        print "[Unreleased]: https://github.com/berachain/beranode-cli/compare/v" new_ver "...HEAD"
        print "[" new_ver "]: https://github.com/berachain/beranode-cli/compare/v" old_ver "...v" new_ver
        next
    }
    # Print all other lines
    { print }
    ' "$CHANGELOG_FILE" > "$CHANGELOG_FILE.tmp" && mv "$CHANGELOG_FILE.tmp" "$CHANGELOG_FILE"
}

show_diff() {
    local current="$1"
    local new="$2"

    echo -e "${BOLD}Version bump:${RESET} $current -> ${GREEN}$new${RESET}"
    echo ""
    echo -e "${BOLD}Files to be modified:${RESET}"
    echo "  - src/lib/constants.sh (BERANODE_VERSION)"
    echo "  - beranode (rebuilt from sources)"
    echo "  - CHANGELOG.md ([Unreleased] -> [$new])"
    echo ""
}

# Parse arguments
DRY_RUN=false
CREATE_TAG=false
BUMP_TYPE=""
DESCRIPTION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --tag)
            CREATE_TAG=true
            shift
            ;;
        -m|--message)
            if [[ -n "$2" ]]; then
                DESCRIPTION="$2"
                shift 2
            else
                echo -e "${RED}Error: --message requires a description${RESET}"
                exit 1
            fi
            ;;
        major|minor|patch)
            BUMP_TYPE="$1"
            shift
            ;;
        *)
            if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                BUMP_TYPE="$1"
            else
                echo -e "${RED}Error: Unknown argument: $1${RESET}"
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$BUMP_TYPE" ]]; then
    echo -e "${RED}Error: No bump type specified${RESET}"
    echo ""
    usage
    exit 1
fi

# Sanitize description: replace newlines and multiple spaces with single space
if [[ -n "$DESCRIPTION" ]]; then
    DESCRIPTION="${DESCRIPTION//$'\n'/ }"  # Replace newlines with spaces
    DESCRIPTION="${DESCRIPTION//  / }"     # Replace double spaces with single
    DESCRIPTION="${DESCRIPTION# }"         # Trim leading space
    DESCRIPTION="${DESCRIPTION% }"         # Trim trailing space
fi

# Validate files exist
if [[ ! -f "$CONSTANTS_FILE" ]]; then
    echo -e "${RED}Error: constants.sh file not found at $CONSTANTS_FILE${RESET}"
    exit 1
fi

if [[ ! -f "$BERANODE_FILE" ]]; then
    echo -e "${RED}Error: beranode file not found at $BERANODE_FILE${RESET}"
    exit 1
fi

if [[ ! -f "$CHANGELOG_FILE" ]]; then
    echo -e "${RED}Error: CHANGELOG.md not found at $CHANGELOG_FILE${RESET}"
    exit 1
fi

if [[ ! -x "$BUILD_SCRIPT" ]]; then
    echo -e "${YELLOW}Warning: build.sh not found or not executable at $BUILD_SCRIPT${RESET}"
fi

# Get current and calculate new version
CURRENT_VERSION=$(get_current_version)
NEW_VERSION=$(calculate_new_version "$CURRENT_VERSION" "$BUMP_TYPE")

# Validate new version
validate_semver "$NEW_VERSION"

# Check version is actually increasing
if [[ "$CURRENT_VERSION" == "$NEW_VERSION" ]]; then
    echo -e "${YELLOW}Version unchanged: $CURRENT_VERSION${RESET}"
    exit 0
fi

# Show what will change
show_diff "$CURRENT_VERSION" "$NEW_VERSION"

if $DRY_RUN; then
    echo -e "${BLUE}Dry run - no changes made${RESET}"
    exit 0
fi

# Confirm
echo -n "Proceed with version bump? [y/N] "
read -r response
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Perform updates
echo ""
echo -e "${BLUE}Updating version...${RESET}"

# Save the old version before updating
OLD_VERSION="$CURRENT_VERSION"

update_beranode_version "$NEW_VERSION"
echo -e "  ${GREEN}✓${RESET} Updated src/lib/constants.sh and rebuilt beranode"

update_changelog "$NEW_VERSION" "$OLD_VERSION" "$DESCRIPTION"
echo -e "  ${GREEN}✓${RESET} Updated CHANGELOG.md"

echo ""
echo -e "${GREEN}Version bumped to $NEW_VERSION${RESET}"

# Create git tag if requested
if $CREATE_TAG; then
    if command -v git &> /dev/null && git rev-parse --is-inside-work-tree &> /dev/null 2>&1; then
        echo ""
        echo -e "${BLUE}Creating git tag...${RESET}"

        # Build commit and tag messages
        commit_msg="chore: release v$NEW_VERSION"
        tag_msg="Release v$NEW_VERSION"

        if [[ -n "$DESCRIPTION" ]]; then
            commit_msg="chore: release v$NEW_VERSION - $DESCRIPTION"
            tag_msg="Release v$NEW_VERSION

$DESCRIPTION"
        fi

        git add src/lib/constants.sh beranode CHANGELOG.md
        git commit -m "$commit_msg"
        git tag -a "v$NEW_VERSION" -m "$tag_msg"
        echo -e "  ${GREEN}✓${RESET} Created tag v$NEW_VERSION"
        echo ""
        echo "To push the release:"
        echo "  git push origin main --tags"
    else
        echo -e "${YELLOW}Warning: Not in a git repository, skipping tag creation${RESET}"
    fi
fi

echo ""
echo -e "${BOLD}Next steps:${RESET}"
echo "  1. Review changes: git diff"
if [[ -n "$DESCRIPTION" ]]; then
    echo "  2. Commit: git add -A && git commit -m 'chore: release v$NEW_VERSION - $DESCRIPTION'"
    echo "  3. Tag: git tag -a v$NEW_VERSION -m 'Release v$NEW_VERSION"
    echo ""
    echo "$DESCRIPTION'"
else
    echo "  2. Commit: git add -A && git commit -m 'chore: release v$NEW_VERSION'"
    echo "  3. Tag: git tag -a v$NEW_VERSION -m 'Release v$NEW_VERSION'"
fi
echo "  4. Push: git push origin main --tags"
