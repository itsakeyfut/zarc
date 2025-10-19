# Zarc

[![Status](https://img.shields.io/badge/status-active--development-brightgreen?style=flat-square)]()
[![Rust Version](https://img.shields.io/badge/zig-1.15.2+-orange.svg)](https://ziglang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-red.svg)](https://opensource.org/licenses/MIT)

A modern, high-performance tool written in Zig.

## Features

- Fast and efficient
- Cross-platform support
- Written in Zig for maximum performance and safety

## Installation

### Prerequisites

- Zig 0.13.0 or later

### Building from Source

```bash
git clone https://github.com/itsakeyfut/zarc.git
cd zarc
zig build
```

The compiled binary will be located at `zig-out/bin/zurl`.

## Usage

```bash
./zig-out/bin/zurl [options]
```

## Development

### Building

```bash
zig build
```

### Running

```bash
zig build run
```

### Testing

```bash
zig build test
```

### Build Options

- `-Doptimize=ReleaseSafe` - Build with optimizations and safety checks
- `-Doptimize=ReleaseFast` - Build with maximum optimizations
- `-Doptimize=ReleaseSmall` - Build for minimum binary size

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

This project is in early development. APIs and features may change.