# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2025-10-23

### Added

#### Core Features
- Initial release of zarc - Zig Archive Tool
- TAR format support (POSIX ustar format)
- GZIP compression/decompression support
- `extract` command for extracting tar.gz archives
- `list` command for viewing archive contents
- `test` command for verifying archive integrity
- `help` command with detailed usage information
- `version` command for displaying version information

#### CLI Features
- Cross-platform command-line interface with intuitive subcommands
- Progress display with visual feedback during extraction
- Colored output for better readability (with `--no-color` option)
- Verbose mode (`-v`) for detailed operation logs
- Quiet mode (`-q`) for minimal output
- Short aliases for common commands (`x`, `l`, `t`)

#### Archive Operations
- Extract archives with customizable destination paths
- List archive contents with detailed information (permissions, sizes, timestamps)
- Test archive integrity with checksum verification
- Support for file/directory filtering with `--include` and `--exclude` patterns
- Preserve file permissions and timestamps
- Strip leading path components with `--strip-components`
- Overwrite existing files with `--overwrite` flag

#### Security Features
- Path traversal attack prevention
- Symlink escape detection and prevention
- Zip bomb detection with configurable thresholds
- Secure file extraction with permission validation

#### Cross-platform Support
- Linux support with native system calls
- macOS support with BSD-style APIs
- Windows support with platform-specific file handling
- Unified file system abstraction across platforms
- Platform-specific timestamp handling (utimensat, futimens)
- Hard link support across platforms

#### Build System
- Zig build system with multiple optimization levels
- Cross-compilation support for:
  - Linux (x86_64, aarch64)
  - Windows (x86_64)
  - macOS (x86_64, aarch64)
- Build targets for all supported platforms
- Automated documentation generation

#### Testing Infrastructure
- Comprehensive unit test suite
- Integration tests for end-to-end functionality
- Compatibility tests for GNU tar and BSD tar
- Security-focused test cases
- Test fixture generation scripts
- Platform-specific test coverage

#### Documentation
- Complete README with installation and usage instructions
- Design philosophy documentation
- Architecture documentation
- Coding standards and guidelines
- CLI specification with detailed command reference
- API design documentation
- Error handling guidelines
- Security policy
- Contributing guidelines
- Code of Conduct

### Technical Details

#### Implementation
- Written in Zig 0.15.2+
- Zero external dependencies for core functionality
- Memory-safe implementation with allocator-based resource management
- Buffered I/O for optimal performance
- Streaming decompression for memory efficiency

#### Error Handling
- Structured error types with descriptive messages
- Proper error propagation throughout the codebase
- User-friendly error messages with suggestions
- Exit codes following Unix conventions:
  - `0`: Success
  - `1`: General error
  - `2`: Command-line argument error
  - `3`: File not found
  - `4`: Permission error
  - `5`: Corrupted archive
  - `6`: Unsupported format

### Known Limitations

- Archive creation (compress) not yet implemented
- Only tar and tar.gz formats supported (zip, 7z planned for future releases)
- No support for encrypted archives
- No support for multi-volume archives
- No incremental extraction support

## Project Links

- **Repository**: https://github.com/itsakeyfut/zarc
- **Issue Tracker**: https://github.com/itsakeyfut/zarc/issues
- **Documentation**: docs/ directory in the repository

## Contributors

Special thanks to all contributors who helped make this release possible!

---

[Unreleased]: https://github.com/itsakeyfut/zarc/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/itsakeyfut/zarc/releases/tag/v0.1.0
