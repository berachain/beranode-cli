#!/usr/bin/env bash
#
# =============================================================================
# build.sh - Beranode CLI Build Script
# =============================================================================
#
# VERSION: Compatible with Beranode v0.2.1
#
# PURPOSE:
#   Combines all modular source files from src/ into a single executable
#   beranode file for distribution. This build system supports the modular
#   architecture introduced in v0.2.0+ while maintaining a single-file
#   distribution model for ease of deployment.
#
# USAGE:
#   ./build.sh [output_file]
#
# ARGUMENTS:
#   output_file - Optional custom output path (default: ./beranode)
#
# EXAMPLES:
#   ./build.sh                    # Build to ./beranode
#   ./build.sh /usr/local/bin/beranode  # Build to custom location
#
# =============================================================================
# BUILD PROCESS LEGEND
# =============================================================================
#
# The build process follows these numbered steps:
#
#   [1] INITIALIZATION
#       - Set error handling (exit on error)
#       - Determine script and source directories
#       - Set output file path
#       - Configure terminal colors for output
#
#   [2] VALIDATION
#       - Verify src/ directory exists
#       - Check for required source modules
#
#   [3] TEMP FILE CREATION
#       - Create temporary build file
#       - Add shebang and header to output
#
#   [4] MODULE PROCESSING
#       - Process each module in dependency order
#       - Strip shebangs and headers from modules
#       - Add section separators
#       - Combine into single file
#
#   [5] FINALIZATION
#       - Add entry point
#       - Move temp file to final output
#       - Set executable permissions
#       - Display build statistics
#
# =============================================================================

# =============================================================================
# [1] INITIALIZATION
# =============================================================================

# Exit immediately if any command fails
set -e

# Determine script directory (where this build.sh is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source directory containing modular components
SRC_DIR="${SCRIPT_DIR}/src"

# Output file path (use first argument or default to ./beranode)
OUTPUT_FILE="${1:-${SCRIPT_DIR}/beranode}"

# Terminal color codes for formatted output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RESET='\033[0m'

echo -e "${BLUE}Building beranode CLI v0.2.1...${RESET}"

# =============================================================================
# [2] VALIDATION
# =============================================================================

# Verify that the source directory exists
if [[ ! -d "$SRC_DIR" ]]; then
	echo -e "${YELLOW}Error: src directory not found at $SRC_DIR${RESET}"
	exit 1
fi

# =============================================================================
# [3] TEMP FILE CREATION
# =============================================================================

# Create a temporary file for building (cleaned up automatically)
TEMP_FILE=$(mktemp)

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Function: strip_module_header
# Purpose: Removes shebang and header comments from module files to avoid
#          duplicate shebangs and comments in the final built file
# Arguments:
#   $1 - Path to the module file
# Output: Module content without shebang and header comments
strip_module_header() {
	local file="$1"
	# AWK script that:
	# - Skips shebang line (#!/usr/bin/env bash)
	# - Skips initial comment block (lines starting with #)
	# - Skips empty lines in header
	# - Outputs remaining content
	awk '
        BEGIN { in_header = 1; first_line = 1 }
        /^#!/ && first_line { first_line = 0; next }
        /^#/ && in_header { next }
        /^$/ && in_header { next }
        { in_header = 0; print }
    ' "$file"
}

# Function: add_section
# Purpose: Adds a visual section separator to the output file for better
#          readability and debugging of the built file
# Arguments:
#   $1 - Section name (typically the module name)
#   $2 - File path (source file path for reference)
add_section() {
	local section_name="$1"
	local file_path="$2"

	cat >>"$TEMP_FILE" <<EOF

# =============================================================================
# ${section_name}
# Source: ${file_path}
# =============================================================================

EOF
}

# =============================================================================
# [4] MODULE PROCESSING
# =============================================================================

# Write the main shebang and header to the output file
cat >"$TEMP_FILE" <<'EOF'
#!/usr/bin/env bash
#
# beranode - CLI for managing Berachain nodes
#
# VERSION: 0.2.1
#
# This file is auto-generated by build.sh from modular sources in src/
# Do not edit this file directly. Instead, edit the source files and rebuild.
#
# Usage: beranode <command> [options]
#
# Generated: [BUILD_TIMESTAMP]
#

set -e

EOF

# Module dependency order
# IMPORTANT: Modules must be listed in dependency order:
#   - lib/constants.sh must come first (defines all constants)
#   - lib/logging.sh must come before utils (utils uses logging)
#   - lib/utils.sh must come before genesis (genesis uses utils)
#   - lib/validation.sh depends on logging but is independent of other libs
#   - lib/genesis.sh must come before node (node uses genesis)
#   - commands/* depend on all lib modules
#   - core/dispatcher.sh must come last (orchestrates all commands)
modules=(
	"lib/constants.sh"     # [4.1] Core constants and configuration
	"lib/logging.sh"       # [4.2] Logging utilities
	"lib/utils.sh"         # [4.3] General utility functions
	"lib/validation.sh"    # [4.4] Configuration validation utilities
	"lib/genesis.sh"       # [4.5] Genesis file generation
	"lib/node.sh"          # [4.6] Node management functions
	"commands/common.sh"   # [4.7] Common command utilities
	"commands/init.sh"     # [4.8] Init command implementation
	"commands/start.sh"    # [4.9] Start command implementation
	"commands/stop.sh"     # [4.10] Stop command implementation
	"commands/validate.sh" # [4.11] Validate command implementation
	"core/dispatcher.sh"   # [4.12] Main dispatcher and entry point
)

# Process each module
for module in "${modules[@]}"; do
	module_path="${SRC_DIR}/${module}"

	if [[ -f "$module_path" ]]; then
		echo -e "${BLUE}  Adding: ${module}${RESET}"

		# Add section separator
		add_section "$(basename "$module" .sh)" "$module" >>"$TEMP_FILE"

		# Strip header and append module content
		strip_module_header "$module_path" >>"$TEMP_FILE"

		# Add blank line for readability
		echo "" >>"$TEMP_FILE"
	else
		echo -e "${YELLOW}  Warning: Module not found: ${module}${RESET}"
	fi
done

# =============================================================================
# [5] FINALIZATION
# =============================================================================

# Add the main entry point call
cat >>"$TEMP_FILE" <<'EOF'

# =============================================================================
# Entry Point - Main script execution
# =============================================================================

main "$@"
EOF

# Move temp file to final output location
mv "$TEMP_FILE" "$OUTPUT_FILE"

# Make the output file executable
chmod +x "$OUTPUT_FILE"

# Display build success message with statistics
echo -e "${GREEN}✓ Build complete: ${OUTPUT_FILE}${RESET}"
echo -e "${BLUE}  Version: 0.2.1${RESET}"
echo -e "${BLUE}  Lines: $(wc -l <"$OUTPUT_FILE")${RESET}"
echo -e "${BLUE}  Size: $(du -h "$OUTPUT_FILE" | cut -f1)${RESET}"

# =============================================================================
# VERSION CONTEXT FOR v0.2.1
# =============================================================================
#
# This build script was designed for beranode v0.2.1, which includes:
#
# - Modular architecture with separated concerns (lib/, commands/, core/)
# - Support for init and start commands with --help options
# - Enhanced version management via BERANODE_VERSION constant
# - Configuration file generation (app.toml, config.toml, client.toml)
# - Genesis contract deployments for Prague upgrade phases
# - Platform detection (macOS, Linux, Windows)
# - Comprehensive logging and error handling
#
# The build process combines 9 source modules into a single executable while
# preserving functionality and maintaining code organization for developers.
#
# =============================================================================
