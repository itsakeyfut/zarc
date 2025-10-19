# GitHub Actions Workflows

This directory contains the CI/CD workflows for the zarc project.

## Workflows

### 1. CI (`ci.yml`)

**Trigger:** Push to main/develop, Pull Requests

Main continuous integration workflow that runs on every push and PR.

**Jobs:**
- **test**: Runs tests on Linux, Windows, and macOS
  - Code formatting check
  - Debug build
  - Unit tests
  - Integration tests
  - Release build
  - Upload artifacts

- **lint**: Code quality checks
  - Format validation
  - Build warnings analysis

- **cross-compile-check**: Verifies cross-compilation
  - Builds for all target platforms
  - Ensures build system works correctly

- **build-status**: Summary of all checks
  - Reports overall status

### 2. Coverage (`coverage.yml`)

**Trigger:** Push to main, Pull Requests to main

Test coverage tracking and reporting.

**Note:** Zig doesn't have native coverage tooling yet (as of 0.15.2).
This workflow provides a framework for future coverage integration and
currently generates manual coverage reports.

**Phase 0 Coverage Goals:**
- Overall: 70%+
- Core modules: 90%+
- Compression: 85%+
- Formats: 85%+

### 3. Release (`release.yml`)

**Trigger:** Git tags matching `v*`, Manual dispatch

Builds release binaries for all platforms and creates GitHub releases.

**Platforms:**
- Linux x86_64 (musl static)
- Linux aarch64 (musl static)
- Windows x86_64
- macOS x86_64 (Intel)
- macOS aarch64 (Apple Silicon)

**Artifacts:**
- Compressed binaries (.tar.gz for Unix, .zip for Windows)
- SHA256 checksums

## Local Development Workflow

### Running tests locally

```bash
# Quick tests
zig build test

# All tests
zig build test-all

# Integration tests only
zig build test-integration

# Tests with summary
zig build test --summary all
```

### Code formatting

```bash
# Check formatting
zig fmt --check src/

# Auto-format
zig fmt src/
```

### Cross-compilation verification

```bash
# Build for specific platform
zig build build-linux-x86_64
zig build build-windows-x86_64
zig build build-macos-aarch64

# Build for all platforms
zig build build-all
```

### Release build

```bash
# Optimized build
zig build -Doptimize=ReleaseFast

# Small binary
zig build -Doptimize=ReleaseSmall

# Safe optimizations
zig build -Doptimize=ReleaseSafe
```

## CI/CD Requirements

### Zig Version

The project uses Zig `0.15.2` (specified in `.zigversion`).
All workflows use this version automatically.

### Secrets

No secrets are required for basic CI/CD operations.

For GitHub releases:
- `GITHUB_TOKEN` (automatically provided by GitHub Actions)

### Branch Protection

Recommended settings for `main` branch:
- ✅ Require pull request reviews
- ✅ Require status checks to pass before merging
  - `Test on ubuntu-latest`
  - `Test on windows-latest`
  - `Test on macos-latest`
  - `Lint`
  - `Cross-compilation verification`
- ✅ Require branches to be up to date before merging

## Troubleshooting

### Build fails on Windows

Ensure line endings are correct:
```bash
git config core.autocrlf input
```

### Cross-compilation fails

Verify Zig version matches `.zigversion`:
```bash
zig version
```

### Tests timeout

Default timeout is 1 hour. For slow tests, adjust in workflow:
```yaml
timeout-minutes: 120
```

## Adding New Workflows

1. Create `.yml` file in this directory
2. Use existing workflows as templates
3. Test locally with `act` (https://github.com/nektos/act)
4. Document in this README

## References

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Zig Build System](https://ziglang.org/documentation/master/#Zig-Build-System)
- [zarc Testing Strategy](../../docs/implementation/TESTING_STRATEGY.md)
- [zarc Build System](../../docs/implementation/BUILD_SYSTEM.md)
