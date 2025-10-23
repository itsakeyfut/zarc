# zarc - Zig Archive Tool

[![Status](https://img.shields.io/badge/status-active--development-brightgreen?style=flat-square)]()
[![Zig Version](https://img.shields.io/badge/zig-0.15.2+-orange.svg)](https://ziglang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-red.svg)](https://opensource.org/licenses/MIT)

A modern, cross-platform archive tool written in Zig. zarc provides a unified interface for working with archive files across different platforms with consistent behavior and strong security guarantees.

## Features

- **Cross-platform**: Consistent behavior on Windows, Linux, and macOS
- **Secure by default**: Built-in protection against path traversal and zip bomb attacks
- **tar.gz support**: Extract and list tar archives with gzip compression
- **User-friendly CLI**: Progress display, colored output, and clear error messages
- **High performance**: Written in Zig for maximum speed and memory safety
- **Well-tested**: Comprehensive unit, integration, and compatibility test suites

## Installation

### Prerequisites

- Zig 0.15.2 or later

### Building from Source

```bash
git clone https://github.com/itsakeyfut/zarc.git
cd zarc
zig build
```

The compiled binary will be located at `zig-out/bin/zarc`.

### Installing

To install the binary to a location in your PATH:

```bash
# Install to default location (requires appropriate permissions)
zig build -Doptimize=ReleaseSafe
sudo cp zig-out/bin/zarc /usr/local/bin/

# Or install to user directory
mkdir -p ~/.local/bin
cp zig-out/bin/zarc ~/.local/bin/
```

## Usage

### Quick Start

```bash
# Extract an archive
zarc extract archive.tar.gz

# Extract to a specific directory
zarc extract archive.tar.gz /path/to/destination
zarc extract archive.tar.gz -C /path/to/destination

# List archive contents
zarc list archive.tar.gz

# List with detailed information
zarc list archive.tar.gz -l

# Test archive integrity
zarc test archive.tar.gz

# Show help
zarc help
zarc extract --help
```

### Common Operations

#### Extracting Archives

```bash
# Basic extraction
zarc extract archive.tar.gz

# Extract with verbose output
zarc extract archive.tar.gz -v

# Extract specific files
zarc extract archive.tar.gz --include "*.txt"

# Extract excluding certain files
zarc extract archive.tar.gz --exclude "*.log"

# Overwrite existing files
zarc extract archive.tar.gz -f
```

#### Listing Archive Contents

```bash
# Simple list
zarc list archive.tar.gz

# Detailed listing with permissions and timestamps
zarc list archive.tar.gz -l

# Human-readable file sizes
zarc list archive.tar.gz -lh
```

#### Testing Archives

```bash
# Verify archive integrity
zarc test archive.tar.gz

# Verbose output showing each entry
zarc test archive.tar.gz -v
```

### Available Commands

| Command | Aliases | Description |
|---------|---------|-------------|
| `extract` | `x` | Extract archive contents |
| `list` | `l`, `ls` | List archive contents |
| `test` | `t` | Test archive integrity |
| `help` | `h` | Show help information |
| `version` | `v` | Show version information |

### Supported Formats (v0.1.0)

- tar (uncompressed)
- tar.gz / tgz (gzip compressed)

*Note: Additional formats (zip, 7z, bzip2, xz) are planned for future releases.*

## Development

### Building

```bash
# Debug build (default)
zig build

# Release build with safety checks (recommended)
zig build -Doptimize=ReleaseSafe

# Release build with maximum performance
zig build -Doptimize=ReleaseFast

# Release build with minimum size
zig build -Doptimize=ReleaseSmall
```

### Running

```bash
# Run with arguments
zig build run -- extract archive.tar.gz

# Or run the binary directly
./zig-out/bin/zarc extract archive.tar.gz
```

### Testing

```bash
# Run all tests
zig build test-all

# Run unit tests only
zig build test-unit

# Run integration tests only
zig build test-integration

# Run embedded tests in source files
zig build test
```

### Cross-compilation

zarc supports cross-compilation for multiple platforms:

```bash
# Build for all supported platforms
zig build build-all

# Build for specific platforms
zig build build-linux-x86_64
zig build build-linux-aarch64
zig build build-windows-x86_64
zig build build-macos-x86_64
zig build build-macos-aarch64
```

Binaries will be placed in `zig-out/bin/` with platform-specific names (e.g., `zarc-linux-x86_64`).

### Documentation

```bash
# Generate API documentation
zig build docs

# Documentation will be available in zig-out/docs/
```

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](.github/CONTRIBUTING.md) for guidelines.

### Quick Start for Contributors

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests (`zig build test`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to your fork (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## Code of Conduct

This project adheres to a [Code of Conduct](.github/CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with [Zig](https://ziglang.org/)
- Thanks to all contributors who help improve this project

## Support

- **Bug Reports**: Please use the [bug_report.yaml](.github/ISSUE_TEMPLATE/bug_report.yaml)
- **Feature Requests**: Please use the [feature_request.yaml](.github/ISSUE_TEMPLATE/feature_request.yaml)
- **Questions**: create an issue

## Project Status

This project is currently in **Phase 0 - Foundation (v0.1.0)**, focusing on core tar.gz functionality and establishing a solid foundation for future development.

### Roadmap

- **v0.1.0** (Current): tar + gzip support (extract, list, test)
- **v0.2.0**: zip format support, archive creation (compress)
- **v0.3.0**: 7z format reading
- **v0.4.0**: 7z format writing
- **v1.0.0**: Stable release with C API

For detailed development plans, see the [design documentation](docs/DESIGN_PHILOSOPHY.md).