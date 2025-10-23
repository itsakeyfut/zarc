# Testing Strategy and Coverage Goals

**Last Updated**: 2025-10-18

---

## Table of Contents

1. [Testing Strategy Overview](#testing-strategy-overview)
2. [Test Levels](#test-levels)
3. [Coverage Goals](#coverage-goals)
4. [Test Data Management](#test-data-management)
5. [CI/CD Integration](#cicd-integration)
6. [Test Execution](#test-execution)

---

## Testing Strategy Overview

### Core Principles

1. **Comprehensive Testing**: Test at all layers
2. **Automation**: Run automatically in CI/CD
3. **Fast Feedback**: Enable immediate local testing
4. **Real Data Focus**: Test with actual archive files
5. **Regression Prevention**: Detect breaking changes to existing functionality

### Testing Pyramid

```
        ┌─────────────┐
        │   E2E Tests │  10% - Actual CLI usage
        ├─────────────┤
        │  Integration│  20% - Multi-module integration
        ├─────────────┤
        │  Unit Tests │  70% - Individual functions/modules
        └─────────────┘
```

---

## Test Levels

### 1. Unit Tests

**Purpose**: Verify individual functions and structs

**Scope**:
- Compression algorithms
- Format parsers
- Utility functions

**Location**: `tests/unit/`

#### Example: tar Header Parsing

```zig
// tests/unit/tar_test.zig

const std = @import("std");
const tar = @import("../../src/formats/tar/header.zig");

test "TarHeader: parseOctal - normal case" {
    const input = "0000644 ";
    const result = try tar.parseOctal(input);
    try std.testing.expectEqual(@as(u64, 0o644), result);
}

test "TarHeader: parseOctal - boundary value" {
    const input = "7777777 ";
    const result = try tar.parseOctal(input);
    try std.testing.expectEqual(@as(u64, 0o7777777), result);
}

test "TarHeader: parseOctal - error case" {
    const input = "invalid ";
    try std.testing.expectError(error.InvalidOctal, tar.parseOctal(input));
}

test "TarHeader: calculateChecksum" {
    var header: [512]u8 = undefined;
    @memset(&header, 0);

    // Build header
    @memcpy(header[0..5], "file");
    @memcpy(header[100..108], "0000644 ");
    // ... other fields

    const checksum = tar.calculateChecksum(&header);
    try std.testing.expect(checksum > 0);
}

test "TarHeader: parseHeader - complete header" {
    const allocator = std.testing.allocator;

    // Prepare actual tar header
    var header_bytes: [512]u8 = undefined;
    // ... set header data

    const entry = try tar.parseHeader(allocator, &header_bytes);
    defer allocator.free(entry.name);

    try std.testing.expectEqualStrings("test.txt", entry.name);
    try std.testing.expectEqual(@as(u64, 1024), entry.size);
    try std.testing.expectEqual(@as(u32, 0o644), entry.mode);
}
```

#### Example: Deflate Decompression

```zig
// tests/unit/deflate_test.zig

const std = @import("std");
const deflate = @import("../../src/compression/deflate/decode.zig");

test "Deflate: decompress uncompressed block" {
    const allocator = std.testing.allocator;

    // Test data for uncompressed block
    const compressed = [_]u8{
        0x01,              // BFINAL=1, BTYPE=00 (uncompressed)
        0x05, 0x00,        // LEN=5
        0xFA, 0xFF,        // NLEN=~LEN
        'H', 'e', 'l', 'l', 'o',
    };

    var decoder = try deflate.DeflateDecoder.init(allocator);
    defer decoder.deinit();

    var output: [1024]u8 = undefined;
    const n = try decoder.decode(&compressed, &output);

    try std.testing.expectEqual(@as(usize, 5), n);
    try std.testing.expectEqualStrings("Hello", output[0..n]);
}

test "Deflate: decompress fixed Huffman block" {
    const allocator = std.testing.allocator;

    // Compressed data using fixed Huffman tree
    const compressed = [_]u8{ /* test data */ };

    var decoder = try deflate.DeflateDecoder.init(allocator);
    defer decoder.deinit();

    var output: [1024]u8 = undefined;
    const n = try decoder.decode(&compressed, &output);

    try std.testing.expectEqualStrings("expected output", output[0..n]);
}

test "Deflate: decompress dynamic Huffman block" {
    // More complex test case
}

test "Deflate: error detection - invalid block type" {
    const allocator = std.testing.allocator;

    const invalid = [_]u8{ 0x07 };  // BTYPE=11 (reserved)

    var decoder = try deflate.DeflateDecoder.init(allocator);
    defer decoder.deinit();

    var output: [1024]u8 = undefined;
    try std.testing.expectError(
        error.InvalidBlockType,
        decoder.decode(&invalid, &output)
    );
}
```

---

### 2. Integration Tests

**Purpose**: Verify multi-module interaction

**Scope**:
- Complete archive extraction workflow
- Complete compression workflow
- Format compatibility

**Location**: `tests/integration/`

#### Example: tar.gz Extraction

```zig
// tests/integration/extract_test.zig

const std = @import("std");
const zarc = @import("zarc");

test "extract: tar.gz extraction - normal case" {
    const allocator = std.testing.allocator;

    // Create temporary directory
    const temp_dir = try std.testing.tmpDir(.{});
    defer temp_dir.cleanup();

    // Extract test archive
    try zarc.extract(
        allocator,
        "tests/fixtures/sample.tar.gz",
        temp_dir.path
    );

    // Verify extracted files
    const file1 = try temp_dir.dir.openFile("file1.txt", .{});
    defer file1.close();

    const content = try file1.readToEndAlloc(allocator, 1024);
    defer allocator.free(content);

    try std.testing.expectEqualStrings("test content", content);
}

test "extract: GNU tar compatibility - long filename" {
    const allocator = std.testing.allocator;

    const temp_dir = try std.testing.tmpDir(.{});
    defer temp_dir.cleanup();

    // Archive with long filename created by GNU tar
    try zarc.extract(
        allocator,
        "tests/fixtures/gnu_tar/long_filename.tar",
        temp_dir.path
    );

    // Verify 255 character filename
    const long_name = "a" ** 255 ++ ".txt";
    const file = try temp_dir.dir.openFile(long_name, .{});
    file.close();
}

test "extract: security - path traversal detection" {
    const allocator = std.testing.allocator;

    const temp_dir = try std.testing.tmpDir(.{});
    defer temp_dir.cleanup();

    // Malicious archive (contains ../)
    try std.testing.expectError(
        error.PathTraversalAttempt,
        zarc.extract(
            allocator,
            "tests/fixtures/malicious/path_traversal.tar",
            temp_dir.path
        )
    );
}
```

#### Example: Compression/Extraction Roundtrip

```zig
// tests/integration/roundtrip_test.zig

test "roundtrip: tar.gz - compress→extract returns to original" {
    const allocator = std.testing.allocator;

    const temp_dir = try std.testing.tmpDir(.{});
    defer temp_dir.cleanup();

    // Create test data
    const test_dir = try temp_dir.dir.makeOpenPath("source", .{});
    defer test_dir.close();

    const file1 = try test_dir.createFile("file1.txt", .{});
    defer file1.close();
    try file1.writeAll("test content 1");

    const file2 = try test_dir.createFile("file2.txt", .{});
    defer file2.close();
    try file2.writeAll("test content 2");

    // Compress
    const archive_path = try std.fs.path.join(
        allocator,
        &[_][]const u8{temp_dir.path, "archive.tar.gz"}
    );
    defer allocator.free(archive_path);

    try zarc.compress(allocator, archive_path, test_dir.path);

    // Extract
    const extract_dir = try temp_dir.dir.makeOpenPath("extracted", .{});
    defer extract_dir.close();

    try zarc.extract(allocator, archive_path, extract_dir.path);

    // Verify
    const extracted1 = try extract_dir.openFile("file1.txt", .{});
    defer extracted1.close();

    const content1 = try extracted1.readToEndAlloc(allocator, 1024);
    defer allocator.free(content1);

    try std.testing.expectEqualStrings("test content 1", content1);
}
```

---

### 3. Compatibility Tests

**Purpose**: Verify compatibility with existing tools

**Scope**:
- Archives created by GNU tar
- Archives created by 7-Zip
- Archives created by Info-ZIP

**Location**: `tests/integration/compatibility_test.zig`

```zig
// tests/integration/compatibility_test.zig

test "compatibility: extract archive created by GNU tar 1.34" {
    const allocator = std.testing.allocator;

    const test_cases = [_]struct {
        name: []const u8,
        fixture: []const u8,
    }{
        .{ .name = "basic", .fixture = "tests/fixtures/gnu_tar/basic.tar" },
        .{ .name = "symlinks", .fixture = "tests/fixtures/gnu_tar/with_symlinks.tar" },
        .{ .name = "unicode", .fixture = "tests/fixtures/gnu_tar/unicode.tar" },
        .{ .name = "sparse", .fixture = "tests/fixtures/gnu_tar/sparse.tar" },
    };

    for (test_cases) |tc| {
        const temp_dir = try std.testing.tmpDir(.{});
        defer temp_dir.cleanup();

        try zarc.extract(allocator, tc.fixture, temp_dir.path);

        // Confirm successful extraction
        std.debug.print("✓ {s}\n", .{tc.name});
    }
}

test "compatibility: extract zarc-created archive with GNU tar" {
    const allocator = std.testing.allocator;

    const temp_dir = try std.testing.tmpDir(.{});
    defer temp_dir.cleanup();

    // Compress with zarc
    const archive_path = try std.fs.path.join(
        allocator,
        &[_][]const u8{temp_dir.path, "test.tar.gz"}
    );
    defer allocator.free(archive_path);

    try zarc.compress(allocator, archive_path, "tests/fixtures/sample_data");

    // Extract with GNU tar (external command)
    const result = try std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "tar",
            "xzf",
            archive_path,
            "-C",
            temp_dir.path,
        },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.term.Exited);
}
```

---

### 4. E2E Tests (End-to-End)

**Purpose**: Verify actual user scenarios

**Scope**: Overall CLI behavior

**Location**: `tests/e2e/`

```zig
// tests/e2e/cli_test.zig

test "E2E: zarc extract command" {
    const allocator = std.testing.allocator;

    const temp_dir = try std.testing.tmpDir(.{});
    defer temp_dir.cleanup();

    // Execute zarc extract
    const result = try std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "./zig-out/bin/zarc",
            "extract",
            "tests/fixtures/sample.tar.gz",
            temp_dir.path,
        },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    // Verify success
    try std.testing.expectEqual(@as(u8, 0), result.term.Exited);

    // Verify stdout
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Extracted") != null);
}

test "E2E: zarc --help" {
    const allocator = std.testing.allocator;

    const result = try std.ChildProcess.exec(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "./zig-out/bin/zarc",
            "--help",
        },
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    try std.testing.expectEqual(@as(u8, 0), result.term.Exited);
    try std.testing.expect(std.mem.indexOf(u8, result.stdout, "Usage:") != null);
}
```

---

## Coverage Goals

### Overall Targets

| Layer | Target Coverage | Notes |
|-------|----------------|-------|
| **Core** | 90%+ | Most critical |
| **Compression** | 85%+ | Algorithm verification |
| **Formats** | 85%+ | Parser verification |
| **I/O** | 80%+ | |
| **App** | 75%+ | Covered by integration tests |
| **CLI** | 70%+ | Covered by E2E tests |

### Phase-specific Targets

| Phase | Coverage | Notes |
|-------|----------|-------|
| Phase 0 | 70%+ | Basic features only |
| Phase 1 | 75%+ | Add compression |
| Phase 2 | 80%+ | Add zip support |
| Phase 3+ | 85%+ | Improve maturity |

### Coverage Measurement

```bash
# Zig coverage measurement (planned for future support)
zig build test -Dtest-coverage

# Current approach: manual verification
# - List functions covered by each test file
# - Identify untested functions
```

---

## Test Data Management

### Test Fixture Structure

```
tests/fixtures/
├── gnu_tar/
│   ├── basic.tar               # Basic tar
│   ├── with_symlinks.tar       # Contains symlinks
│   ├── unicode.tar             # Unicode filenames
│   ├── long_filename.tar       # Long filenames
│   └── sparse.tar              # Sparse files
│
├── bsd_tar/
│   └── macos_created.tar       # Created on macOS
│
├── 7zip/
│   ├── lzma.7z                 # LZMA compression
│   ├── lzma2.7z                # LZMA2 compression
│   └── encrypted.7z            # Encrypted (Phase 3+)
│
├── info_zip/
│   ├── basic.zip               # Basic zip
│   ├── zip64.zip               # Zip64 extension
│   └── windows_created.zip     # Created on Windows
│
├── malicious/                  # Security tests
│   ├── path_traversal.tar      # Contains ../
│   ├── symlink_escape.tar      # Symlink attack
│   └── zip_bomb.zip            # Zip bomb
│
└── sample_data/                # For creating test data
    ├── file1.txt
    ├── file2.txt
    └── subdir/
        └── file3.txt
```

### Test Data Generation

```bash
# scripts/generate_test_data.sh

#!/bin/bash

set -e

# Generate test data with GNU tar
tar cf tests/fixtures/gnu_tar/basic.tar tests/fixtures/sample_data/

# Generate test data with 7-Zip
7z a tests/fixtures/7zip/lzma.7z tests/fixtures/sample_data/

# Generate test data with Info-ZIP
zip -r tests/fixtures/info_zip/basic.zip tests/fixtures/sample_data/

echo "Test data generated successfully"
```

---

## CI/CD Integration

### GitHub Actions

```yaml
# .github/workflows/test.yml

name: Tests

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
        zig-version: ['0.13.0']

    runs-on: ${{ matrix.os }}

    steps:
      - uses: actions/checkout@v3

      - name: Setup Zig
        uses: goto-bus-stop/setup-zig@v2
        with:
          version: ${{ matrix.zig-version }}

      - name: Run unit tests
        run: zig build test

      - name: Build
        run: zig build

      - name: Run integration tests
        run: zig build test-integration

      - name: Run E2E tests
        run: zig build test-e2e

      - name: Generate test fixtures (Linux only)
        if: matrix.os == 'ubuntu-latest'
        run: |
          sudo apt-get update
          sudo apt-get install -y p7zip-full
          bash scripts/generate_test_data.sh
```

---

## Test Execution

### Local Execution

```bash
# All tests
zig build test

# Unit tests only
zig build test-unit

# Integration tests only
zig build test-integration

# Specific test file
zig test tests/unit/tar_test.zig

# Verbose output
zig build test --summary all

# Test in release mode
zig build test -Doptimize=ReleaseFast
```

### build.zig Configuration

```zig
// build.zig

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main executable
    const exe = b.addExecutable(.{
        .name = "zarc",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Integration tests
    const integration_tests = b.addTest(.{
        .root_source_file = .{ .path = "tests/integration/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_integration_tests = b.addRunArtifact(integration_tests);

    const integration_step = b.step("test-integration", "Run integration tests");
    integration_step.dependOn(&run_integration_tests.step);
}
```

---

## Testing Best Practices

### ✅ Do (Recommended)

1. **Use AAA Pattern**
   ```zig
   test "example" {
       // Arrange (setup)
       const allocator = std.testing.allocator;
       const input = "test";

       // Act (execute)
       const result = try process(input);

       // Assert (verify)
       try std.testing.expectEqual(expected, result);
   }
   ```

2. **Meaningful Test Names**
   ```zig
   test "TarHeader: parseOctal - correctly parses octal string"
   ```

3. **Test Error Cases**
   ```zig
   try std.testing.expectError(error.InvalidInput, parseData(""));
   ```

4. **Check for Memory Leaks**
   ```zig
   test "no memory leak" {
       var gpa = std.heap.GeneralPurposeAllocator(.{}){};
       defer std.testing.expect(gpa.deinit() == .ok) catch {};
       const allocator = gpa.allocator();

       // Test logic
   }
   ```

### ❌ Don't (Not Recommended)

1. **Side Effects in Tests**
   ```zig
   // ❌ Bad: Modifies global variables
   test "bad test" {
       global_state = 42;
   }
   ```

2. **Inter-test Dependencies**
   ```zig
   // ❌ Bad: Depends on test1 results
   test "test2 depends on test1" {
       // Assumes test1 has run
   }
   ```

3. **Vague Assertions**
   ```zig
   // ❌ Bad
   try std.testing.expect(result != null);

   // ✅ Good
   try std.testing.expectEqual(expected_value, result.?);
   ```

---

Following this strategy, zarc is developed as high-quality, reliable software.
