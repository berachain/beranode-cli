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
BERANODE_FILE="$ROOT_DIR/beranode"
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
    -h, --help  Show this help message
    --dry-run   Show what would change without modifying files
    --tag       Create a git tag after bumping

${BOLD}EXAMPLES${RESET}
    ./scripts/bump-version.sh patch
    ./scripts/bump-version.sh minor --tag
    ./scripts/bump-version.sh 2.0.0 --dry-run
EOF
}

get_current_version() {
    grep -E '^BERANODE_VERSION=' "$BERANODE_FILE" | sed 's/BERANODE_VERSION="//' | sed 's/"//'
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
    sed -i.bak "s/^BERANODE_VERSION=\".*\"/BERANODE_VERSION=\"$new_version\"/" "$BERANODE_FILE"
    rm -f "$BERANODE_FILE.bak"
}

update_changelog() {
    local new_version="$1"
    local today
    today=$(date +%Y-%m-%d)

    # Check if there are unreleased changes
    local unreleased_content
    unreleased_content=$(sed -n '/^## \[Unreleased\]/,/^## \[/p' "$CHANGELOG_FILE" | head -n -1)

    # Check if unreleased section has any content beyond headers
    local has_changes
    has_changes=$(echo "$unreleased_content" | grep -v '^## \[Unreleased\]' | grep -v '^$' | grep -v '^### ' | head -1)

    if [[ -z "$has_changes" ]]; then
        echo -e "${YELLOW}Warning: No changes documented in [Unreleased] section${RESET}"
        echo "Consider adding changelog entries before releasing."
        echo ""
    fi

    # Create the new version section
    local current_version
    current_version=$(get_current_version)

    # Update the file using awk for more reliable multi-line replacement
    awk -v new_ver="$new_version" -v today="$today" -v curr_ver="$current_version" '
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
    /^## \[/ && in_unreleased {
        print "## [" new_ver "] - " today
        in_unreleased = 0
    }
    /^\[Unreleased\]:/ {
        print "[Unreleased]: https://github.com/berachain/beranode-cli/compare/v" new_ver "...HEAD"
        print "[" new_ver "]: https://github.com/berachain/beranode-cli/compare/v" curr_ver "...v" new_ver
        next
    }
    { print }
    ' "$CHANGELOG_FILE" > "$CHANGELOG_FILE.tmp" && mv "$CHANGELOG_FILE.tmp" "$CHANGELOG_FILE"
}

show_diff() {
    local current="$1"
    local new="$2"

    echo -e "${BOLD}Version bump:${RESET} $current -> ${GREEN}$new${RESET}"
    echo ""
    echo -e "${BOLD}Files to be modified:${RESET}"
    echo "  - beranode (BERANODE_VERSION)"
    echo "  - CHANGELOG.md ([Unreleased] -> [$new])"
    echo ""
}

# Parse arguments
DRY_RUN=false
CREATE_TAG=false
BUMP_TYPE=""

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

# Validate files exist
if [[ ! -f "$BERANODE_FILE" ]]; then
    echo -e "${RED}Error: beranode file not found at $BERANODE_FILE${RESET}"
    exit 1
fi

if [[ ! -f "$CHANGELOG_FILE" ]]; then
    echo -e "${RED}Error: CHANGELOG.md not found at $CHANGELOG_FILE${RESET}"
    exit 1
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

update_beranode_version "$NEW_VERSION"
echo -e "  ${GREEN}✓${RESET} Updated beranode"

update_changelog "$NEW_VERSION"
echo -e "  ${GREEN}✓${RESET} Updated CHANGELOG.md"

echo ""
echo -e "${GREEN}Version bumped to $NEW_VERSION${RESET}"

# Create git tag if requested
if $CREATE_TAG; then
    if command -v git &> /dev/null && git rev-parse --is-inside-work-tree &> /dev/null 2>&1; then
        echo ""
        echo -e "${BLUE}Creating git tag...${RESET}"
        git add beranode CHANGELOG.md
        git commit -m "chore: release v$NEW_VERSION"
        git tag -a "v$NEW_VERSION" -m "Release v$NEW_VERSION"
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
echo "  2. Commit: git add -A && git commit -m 'chore: release v$NEW_VERSION'"
echo "  3. Tag: git tag -a v$NEW_VERSION -m 'Release v$NEW_VERSION'"
echo "  4. Push: git push origin main --tags"
