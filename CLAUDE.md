# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build (debug)
zig build

# Build with optimization
zig build -Doptimize=ReleaseSafe

# Run with arguments
zig build run -- extract archive.tar

# Run all tests
zig build test-all

# Run embedded tests in source files
zig build test

# Run unit tests only (tests/unit/)
zig build test-unit

# Run integration tests only (tests/integration/)
zig build test-integration

# Generate documentation
zig build docs

# Cross-compile for all platforms
zig build build-all

# Cross-compile for specific platform
zig build build-linux-x86_64
zig build build-windows-x86_64
zig build build-macos-aarch64
```

## Architecture Overview

zarc is a cross-platform archive tool written in Zig (0.14.0+). Currently in Phase 0-1, focusing on tar extraction with gzip support.

### Module Structure (src/)

- **main.zig** - Entry point and top-level module exports
- **core/** - Foundational types: `errors.zig` (layered error types), `types.zig`, `util.zig`
- **formats/** - Archive format implementations:
  - `archive.zig` - Archive abstraction
  - `detect.zig` - Format detection
  - `tar/` - Tar header parsing and reading
- **compress/** - Compression: `gzip.zig`, `zlib.zig`, `deflate/decode.zig`, `crc32.zig`
- **io/** - I/O abstractions: `reader.zig`, `writer.zig`, `filesystem.zig`, `streaming.zig`
- **cli/** - Command-line interface: `args.zig`, `commands.zig`, `output.zig`, `progress.zig`
- **app/** - Application logic: `extract.zig`, `security.zig` (path traversal, zip bomb detection)
- **platform/** - Platform-specific code: `windows.zig`, `linux.zig`, `macos.zig`, `bsd.zig`, `common.zig`
- **c_compat/** - Temporary C library wrappers (zlib) - will be replaced with pure Zig in Phase 3+

### Test Organization (tests/)

- **tests/unit/** - Unit tests importing `zarc` module
- **tests/integration/** - Integration tests for CLI and end-to-end workflows
- **tests/fixtures/** - Test archive files

### Key Design Decisions

1. **Error Handling**: Layered error types in `src/core/errors.zig` - `CoreError`, `IOError`, `CompressionError`, `FormatError`, `AppError`, unified as `ZarcError`

2. **C Dependencies**: Currently uses zlib via `src/c_compat/zlib.zig` (temporary, Phase 1-2). Build links libc and zlib. Migration to pure Zig planned for Phase 3+

3. **Security**: Built-in protection against path traversal and zip bomb attacks in `src/app/security.zig`. Safe by default - dangerous operations require explicit flags

4. **Cross-Platform**: Use `std.fs.path` for paths, store timestamps in UTC, POSIX permissions as base format

### Code Style

- SPDX license headers required on all source files
- Functions under 50 lines preferred
- Comments explain "why", code explains "what"
- Replace magic numbers with constants
- Use platform-independent path handling

### Current Roadmap

- v0.1.0 (current): tar support (extract, uncompressed)
- v0.2.0: gzip compression (tar.gz), archive creation
- v0.3.0: zip and bzip2 support
- v0.4.0: 7z and xz support
- v1.0.0: Stable release with C API
