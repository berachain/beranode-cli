# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.7.1] - 2026-02-02

### Summary

Refactored for better readibility, fixed pruned-node issues, added initial support for docker

### Changed Files

- README.md
- beranode
- build.sh
- scripts/bump-version.sh
- src/commands/common.sh
- src/commands/init.sh
- src/commands/start.sh
- src/commands/stop.sh
- src/commands/validate.sh
- src/core/dispatcher.sh
- src/lib/constants.sh
- src/lib/download.sh
- src/lib/genesis.sh
- src/lib/logging.sh
- src/lib/utils.sh
- src/lib/validation.sh
- CHANGELOG.md.tmp
- src/lib/argparse.sh
- src/lib/config.sh
- src/lib/errors.sh
- src/lib/json.sh
- tests/

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.6.0] - 2026-01-31

### Summary

Fix bug for one node setup, allow automatic download of binaries and setup

### Changed Files

- `src/lib/constants.sh` - Updated BERANODE_VERSION to 0.6.0
- `beranode` - Rebuilt from sources
- `CHANGELOG.md` - Updated with release 0.6.0

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.5.0] - 2026-01-31

### Summary

Support for multiple nodes, refactored beranodes.config.json, and made sure ports aren't conflicting

### Changed Files

- `src/lib/constants.sh` - Updated BERANODE_VERSION to 0.5.0
- `beranode` - Rebuilt from sources
- `CHANGELOG.md` - Updated with release 0.5.0

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.4.1] - 2026-01-29

### Summary

Ability to update versioning in files and show all files modified

### Changed Files

- `src/lib/constants.sh` - Updated BERANODE_VERSION to 0.4.1
- `beranode` - Rebuilt from sources
- `CHANGELOG.md` - Updated with release 0.4.1

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.4.0] - 2026-01-29

### Summary

New stop command, and ability to start 1 full val node

### Changed Files

- `src/lib/constants.sh` - Updated BERANODE_VERSION to 0.4.0
- `beranode` - Rebuilt from sources
- `CHANGELOG.md` - Updated with release 0.4.0

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.3.0] - 2026-01-27

### Summary

Added validation functionlality for beranodes.config.json

### Changed Files

- `src/lib/constants.sh` - Updated BERANODE_VERSION to 0.3.0
- `beranode` - Rebuilt from sources
- `CHANGELOG.md` - Updated with release 0.3.0

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.2.1] - 2026-01-27

### Summary

Added additional help commands for init and start

### Changed Files

- `src/lib/constants.sh` - Updated BERANODE_VERSION to 0.2.1
- `beranode` - Rebuilt from sources
- `CHANGELOG.md` - Updated with release 0.2.1

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.2.0] - 2026-01-27

### Summary

Support for config.toml,client.toml, and app.toml configurations to beranodes.config.json

### Changed Files

- `src/lib/constants.sh` - Updated BERANODE_VERSION to 0.2.0
- `beranode` - Rebuilt from sources
- `CHANGELOG.md` - Updated with release 0.2.0

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.1.2] - 2026-01-27

### Changed Files

- `src/lib/constants.sh` - Updated BERANODE_VERSION to 0.1.2
- `beranode` - Rebuilt from sources
- `CHANGELOG.md` - Updated with release 0.1.2

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.1.1] - 2026-01-27

### Summary

Add version management with description support and changelog automation

### Changed Files

- `src/lib/constants.sh` - Updated BERANODE_VERSION to 0.1.1
- `beranode` - Rebuilt from sources
- `CHANGELOG.md` - Updated with release 0.1.1

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

## [0.1.0] - 2026-01-26

### Added

- Initial release of beranode CLI
- Node management commands
- Network configuration support

[Unreleased]: https://github.com/berachain/beranode-cli/compare/v0.7.1...HEAD
[0.7.1]: https://github.com/berachain/beranode-cli/compare/v0.8.0...v0.7.1
[0.6.0]: https://github.com/berachain/beranode-cli/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/berachain/beranode-cli/compare/v0.4.1...v0.5.0
[0.4.1]: https://github.com/berachain/beranode-cli/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/berachain/beranode-cli/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/berachain/beranode-cli/compare/v0.2.1...v0.3.0
[0.2.1]: https://github.com/berachain/beranode-cli/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/berachain/beranode-cli/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/berachain/beranode-cli/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/berachain/beranode-cli/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/berachain/beranode-cli/releases/tag/v0.1.0
