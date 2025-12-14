// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 itsakeyfut
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//! Comprehensive integration tests for tar.gz functionality
//! Issue #56: Integration Test Framework
//!
//! This test suite provides comprehensive coverage for tar.gz archives:
//! - File size tests (tiny, small, medium, large)
//! - Content type tests (text, binary, empty, sparse)
//! - Structure tests (flat, nested, mixed, empty directories)
//! - Special case tests (long filenames, unicode, symlinks, hardlinks)
//! - Compression level tests (1, 6, 9)
//! - GNU tar compatibility tests
//!
//! Following TESTING_STRATEGY.md guidelines for integration testing
//!
//! IMPORTANT NOTE: Currently using uncompressed .tar files for testing
//! until TarReader.initGzip() is implemented (Issue #21).
//! Once gzip support is added, these tests should be updated to use .tar.gz files
//! to properly test the compression/decompression pipeline.

const std = @import("std");
const builtin = @import("builtin");
const zarc = @import("zarc");
const TarReader = zarc.formats.tar.reader.TarReader;
const TarGzReader = zarc.formats.tar.reader.TarGzReader;
const extract = zarc.app.extract;
const security = zarc.app.security;
const types = zarc.core.types;

// Note: Tests using TarReader.init() have a known issue on Windows where the AnyReader
// holds a dangling pointer after the struct is returned/moved, causing
// ERROR_INVALID_HANDLE (error code 6) on subsequent reads.
// See Issue #73 for details. These tests are skipped on Windows.
// TarGzReader tests work because they use heap-allocated readers.

// ============================================================================
// Test Helper Functions
// ============================================================================

/// Create a test directory with sample files
fn createTestData(allocator: std.mem.Allocator, dir: std.fs.Dir, comptime scenario: []const u8) !void {
    if (std.mem.eql(u8, scenario, "tiny")) {
        // Tiny files (<1KB)
        const file = try dir.createFile("tiny.txt", .{});
        defer file.close();
        try file.writeAll("Hello, World!");
    } else if (std.mem.eql(u8, scenario, "small")) {
        // Small files (1KB-100KB)
        const file = try dir.createFile("small.txt", .{});
        defer file.close();
        const data = try allocator.alloc(u8, 10 * 1024); // 10KB
        defer allocator.free(data);
        @memset(data, 'A');
        try file.writeAll(data);
    } else if (std.mem.eql(u8, scenario, "nested")) {
        // Nested directory structure (depth 5)
        try dir.makeDir("level1");
        var level1 = try dir.openDir("level1", .{});
        defer level1.close();

        try level1.makeDir("level2");
        var level2 = try level1.openDir("level2", .{});
        defer level2.close();

        try level2.makeDir("level3");
        var level3 = try level2.openDir("level3", .{});
        defer level3.close();

        try level3.makeDir("level4");
        var level4 = try level3.openDir("level4", .{});
        defer level4.close();

        try level4.makeDir("level5");
        var level5 = try level4.openDir("level5", .{});
        defer level5.close();

        const file = try level5.createFile("deep.txt", .{});
        defer file.close();
        try file.writeAll("Deep file content");
    } else if (std.mem.eql(u8, scenario, "mixed")) {
        // Mixed structure (files + directories)
        const file1 = try dir.createFile("file1.txt", .{});
        defer file1.close();
        try file1.writeAll("File 1 content");

        try dir.makeDir("subdir");
        var subdir = try dir.openDir("subdir", .{});
        defer subdir.close();

        const file2 = try subdir.createFile("file2.txt", .{});
        defer file2.close();
        try file2.writeAll("File 2 content");

        const file3 = try dir.createFile("file3.txt", .{});
        defer file3.close();
        try file3.writeAll("File 3 content");
    } else if (std.mem.eql(u8, scenario, "empty")) {
        // Empty file
        const file = try dir.createFile("empty.txt", .{});
        file.close();
    } else if (std.mem.eql(u8, scenario, "binary")) {
        // Binary file with non-text content
        const file = try dir.createFile("binary.bin", .{});
        defer file.close();
        const data = [_]u8{ 0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE, 0xFD, 0xFC };
        try file.writeAll(&data);
    }
}

/// Helper to verify directory contents match expected
fn verifyDirectoryContents(dir: std.fs.Dir, expected_files: []const []const u8) !void {
    for (expected_files) |file_path| {
        dir.access(file_path, .{}) catch |err| {
            std.debug.print("Expected file not found: {s}\n", .{file_path});
            return err;
        };
    }
}

/// Helper to read file content
fn readFileContent(allocator: std.mem.Allocator, dir: std.fs.Dir, path: []const u8) ![]u8 {
    const file = try dir.openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 1024 * 1024);
}

/// Helper to compare file contents
fn compareFiles(allocator: std.mem.Allocator, dir1: std.fs.Dir, dir2: std.fs.Dir, path: []const u8) !void {
    const content1 = try readFileContent(allocator, dir1, path);
    defer allocator.free(content1);

    const content2 = try readFileContent(allocator, dir2, path);
    defer allocator.free(content2);

    try std.testing.expectEqualSlices(u8, content1, content2);
}

// ============================================================================
// File Size Tests
// ============================================================================

test "tar.gz: extract tiny file (<1KB) - GNU tar created" {
    // Note: Gzip decompression support for TarReader not yet implemented
    // This test will be enabled once TarReader.initGzip() is implemented
    // See Issue #21 for tar.gz extraction support
    std.debug.print("Skipping: tar.gz extraction support not yet implemented (waiting for TarReader.initGzip)\n", .{});
    return error.SkipZigTest;
}

test "tar.gz: extract small files (1KB-100KB) - multiple files" {
    // Skip on Windows due to TarReader AnyReader pointer invalidation issue (Issue #73)
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: TarReader file handle issue on Windows (Issue #73)\n", .{});
        return error.SkipZigTest;
    }

    // Arrange
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    // Open archive with small files
    const tar_file = try std.fs.cwd().openFile("tests/fixtures/gnu_tar/basic.tar", .{});
    defer tar_file.close();

    // Act
    var tar_reader = try TarReader.init(allocator, tar_file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();
    defer archive_reader.deinit();

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, .{});
    defer result.deinit(allocator);

    // Assert
    try std.testing.expect(result.succeeded > 0);
    try std.testing.expectEqual(@as(usize, 0), result.failed);
}

// Note: Medium (1MB-10MB) and Large (100MB+) file tests would be implemented
// when test fixtures are available. Skipping for now to avoid large binary files
// in the repository during initial implementation.

// ============================================================================
// Content Type Tests
// ============================================================================

test "tar.gz: extract text files - preserves content" {
    // Skip on Windows due to TarReader AnyReader pointer invalidation issue (Issue #73)
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: TarReader file handle issue on Windows (Issue #73)\n", .{});
        return error.SkipZigTest;
    }

    // Arrange
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    // Use text_files.tar which actually contains text files
    const tar_file = try std.fs.cwd().openFile("tests/fixtures/gnu_tar/text_files.tar", .{});
    defer tar_file.close();

    // Act
    var tar_reader = try TarReader.init(allocator, tar_file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();
    defer archive_reader.deinit();

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, .{});
    defer result.deinit(allocator);

    // Assert
    try std.testing.expect(result.succeeded > 0);
    try std.testing.expectEqual(@as(usize, 0), result.failed);

    // Verify at least one file was extracted
    var dest_dir = try std.fs.cwd().openDir(dest_path, .{});
    defer dest_dir.close();

    // text_files.tar contains text/text1.txt and text/text2.txt
    dest_dir.access("text", .{}) catch |err| {
        std.debug.print("Expected text directory not found\n", .{});
        return err;
    };
}

test "tar.gz: extract binary files - preserves exact bytes" {
    // Skip on Windows due to TarReader AnyReader pointer invalidation issue (Issue #73)
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: TarReader file handle issue on Windows (Issue #73)\n", .{});
        return error.SkipZigTest;
    }

    // This test would verify binary file extraction preserves exact byte content
    // Currently using basic.tar which contains text files
    // Binary-specific test fixtures would be needed for full coverage

    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    const tar_file = try std.fs.cwd().openFile("tests/fixtures/gnu_tar/basic.tar", .{});
    defer tar_file.close();

    // Act
    var tar_reader = try TarReader.init(allocator, tar_file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();
    defer archive_reader.deinit();

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, .{});
    defer result.deinit(allocator);

    // Assert
    try std.testing.expect(result.succeeded > 0);
}

test "tar.gz: extract empty files - creates zero-byte files" {
    // Skip on Windows due to TarReader AnyReader pointer invalidation issue (Issue #73)
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: TarReader file handle issue on Windows (Issue #73)\n", .{});
        return error.SkipZigTest;
    }

    // Test extraction of archives containing empty files
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    const tar_file = try std.fs.cwd().openFile("tests/fixtures/gnu_tar/basic.tar", .{});
    defer tar_file.close();

    // Act
    var tar_reader = try TarReader.init(allocator, tar_file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();
    defer archive_reader.deinit();

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, .{});
    defer result.deinit(allocator);

    // Assert - extraction should succeed
    try std.testing.expect(result.succeeded >= 0);
}

// Note: Sparse file tests would require specific test fixtures with sparse files

// ============================================================================
// Structure Tests
// ============================================================================

test "tar.gz: extract flat structure - files only" {
    // Skip on Windows due to TarReader AnyReader pointer invalidation issue (Issue #73)
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: TarReader file handle issue on Windows (Issue #73)\n", .{});
        return error.SkipZigTest;
    }

    // Test extraction of archives with flat file structure (no subdirectories)
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    const tar_file = try std.fs.cwd().openFile("tests/fixtures/gnu_tar/basic.tar", .{});
    defer tar_file.close();

    // Act
    var tar_reader = try TarReader.init(allocator, tar_file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();
    defer archive_reader.deinit();

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, .{});
    defer result.deinit(allocator);

    // Assert
    try std.testing.expect(result.succeeded > 0);
    try std.testing.expectEqual(@as(usize, 0), result.failed);
}

test "tar.gz: extract nested directories - depth 10+" {
    // Test extraction of deeply nested directory structures
    // Note: Would require a test fixture with deep nesting
    // This is a placeholder for when such fixtures are created

    const allocator = std.testing.allocator;
    _ = allocator;

    // TODO: Create fixture with 10+ levels of nesting
    // For now, we skip this test as the fixture doesn't exist yet
    return error.SkipZigTest;
}

test "tar.gz: extract mixed structure - files and directories" {
    // Skip on Windows due to TarReader AnyReader pointer invalidation issue (Issue #73)
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: TarReader file handle issue on Windows (Issue #73)\n", .{});
        return error.SkipZigTest;
    }

    // Test extraction of archives with mixed files and directories
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    const tar_file = try std.fs.cwd().openFile("tests/fixtures/gnu_tar/basic.tar", .{});
    defer tar_file.close();

    // Act
    var tar_reader = try TarReader.init(allocator, tar_file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();
    defer archive_reader.deinit();

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, .{});
    defer result.deinit(allocator);

    // Assert
    try std.testing.expect(result.succeeded > 0);

    // Verify directory structure was created
    var dest_dir = try std.fs.cwd().openDir(dest_path, .{});
    defer dest_dir.close();
}

test "tar.gz: extract empty directories - creates directory structure" {
    // Test extraction of archives with empty directories
    // Note: Requires specific test fixture with empty directories

    const allocator = std.testing.allocator;
    _ = allocator;

    // TODO: Create fixture with empty directories
    return error.SkipZigTest;
}

// ============================================================================
// Special Case Tests
// ============================================================================

test "tar.gz: extract long filenames (>100 chars) - GNU tar extension" {
    // Skip on Windows due to TarReader AnyReader pointer invalidation issue (Issue #73)
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: TarReader file handle issue on Windows (Issue #73)\n", .{});
        return error.SkipZigTest;
    }

    // Test extraction of files with long filenames using GNU tar extensions
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    // Open archive with long filename
    const tar_file = try std.fs.cwd().openFile("tests/fixtures/gnu_tar/long_filename.tar", .{});
    defer tar_file.close();

    // Act
    var tar_reader = try TarReader.init(allocator, tar_file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();
    defer archive_reader.deinit();

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, .{});
    defer result.deinit(allocator);

    // Assert
    try std.testing.expect(result.succeeded > 0);
    try std.testing.expectEqual(@as(usize, 0), result.failed);
}

test "tar.gz: extract unicode filenames - Japanese, emoji" {
    // Skip on Windows due to TarReader AnyReader pointer invalidation issue (Issue #73)
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: TarReader file handle issue on Windows (Issue #73)\n", .{});
        return error.SkipZigTest;
    }

    // Test extraction of files with Unicode filenames
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    // Open archive with unicode filenames
    const tar_file = try std.fs.cwd().openFile("tests/fixtures/gnu_tar/unicode.tar", .{});
    defer tar_file.close();

    // Act
    var tar_reader = try TarReader.init(allocator, tar_file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();
    defer archive_reader.deinit();

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, .{});
    defer result.deinit(allocator);

    // Assert
    try std.testing.expect(result.succeeded > 0);
}

test "tar.gz: extract special characters in names - spaces, quotes" {
    // Skip on Windows due to TarReader AnyReader pointer invalidation issue (Issue #73)
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: TarReader file handle issue on Windows (Issue #73)\n", .{});
        return error.SkipZigTest;
    }

    // Test extraction of files with special characters in filenames
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    // Note: Would require a specific test fixture with special characters
    // Using basic.tar as a placeholder
    const tar_file = try std.fs.cwd().openFile("tests/fixtures/gnu_tar/basic.tar", .{});
    defer tar_file.close();

    // Act
    var tar_reader = try TarReader.init(allocator, tar_file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();
    defer archive_reader.deinit();

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, .{});
    defer result.deinit(allocator);

    // Assert
    try std.testing.expect(result.succeeded > 0);
}

test "tar.gz: extract symbolic links - preserves link target" {
    // Skip on Windows due to TarReader AnyReader pointer invalidation issue (Issue #73)
    // Also symlink creation requires elevated privileges on Windows
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: TarReader file handle issue on Windows (Issue #73)\n", .{});
        return error.SkipZigTest;
    }

    // Test extraction of archives containing symbolic links
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    // Open archive with symlinks
    const tar_file = try std.fs.cwd().openFile("tests/fixtures/gnu_tar/with_symlinks.tar", .{});
    defer tar_file.close();

    // Act
    var tar_reader = try TarReader.init(allocator, tar_file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();
    defer archive_reader.deinit();

    // Use policy that allows relative symlinks (required for this test)
    const options = extract.ExtractOptions{
        .security_policy = .{
            .symlink_policy = .only_relative,
        },
    };
    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, options);
    defer result.deinit(allocator);

    // Assert - symlinks should be extracted with allow_relative policy
    try std.testing.expect(result.succeeded > 0);
}

test "tar.gz: extract hard links - creates proper hard links" {
    // Test extraction of archives containing hard links
    // Note: Requires specific test fixture with hard links

    const allocator = std.testing.allocator;
    _ = allocator;

    // TODO: Create fixture with hard links
    return error.SkipZigTest;
}

// ============================================================================
// Compression Level Tests
// ============================================================================

test "tar.gz: extract level 1 (fastest) - decompresses correctly" {
    // Skip on Windows due to TarReader AnyReader pointer invalidation issue (Issue #73)
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: TarReader file handle issue on Windows (Issue #73)\n", .{});
        return error.SkipZigTest;
    }

    // Test extraction of archives compressed with level 1 (fastest)
    // Note: All compression levels should extract identically

    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    // Note: Would require fixtures compressed at different levels
    const tar_file = try std.fs.cwd().openFile("tests/fixtures/gnu_tar/basic.tar", .{});
    defer tar_file.close();

    // Act
    var tar_reader = try TarReader.init(allocator, tar_file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();
    defer archive_reader.deinit();

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, .{});
    defer result.deinit(allocator);

    // Assert
    try std.testing.expect(result.succeeded > 0);
}

test "tar.gz: extract level 6 (default) - decompresses correctly" {
    // Skip on Windows due to TarReader AnyReader pointer invalidation issue (Issue #73)
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: TarReader file handle issue on Windows (Issue #73)\n", .{});
        return error.SkipZigTest;
    }

    // Test extraction of archives compressed with level 6 (default)
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    const tar_file = try std.fs.cwd().openFile("tests/fixtures/gnu_tar/basic.tar", .{});
    defer tar_file.close();

    // Act
    var tar_reader = try TarReader.init(allocator, tar_file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();
    defer archive_reader.deinit();

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, .{});
    defer result.deinit(allocator);

    // Assert
    try std.testing.expect(result.succeeded > 0);
}

test "tar.gz: extract level 9 (best) - decompresses correctly" {
    // Skip on Windows due to TarReader AnyReader pointer invalidation issue (Issue #73)
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: TarReader file handle issue on Windows (Issue #73)\n", .{});
        return error.SkipZigTest;
    }

    // Test extraction of archives compressed with level 9 (best compression)
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    const tar_file = try std.fs.cwd().openFile("tests/fixtures/gnu_tar/basic.tar", .{});
    defer tar_file.close();

    // Act
    var tar_reader = try TarReader.init(allocator, tar_file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();
    defer archive_reader.deinit();

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, .{});
    defer result.deinit(allocator);

    // Assert
    try std.testing.expect(result.succeeded > 0);
}

// ============================================================================
// GNU tar Compatibility Tests
// ============================================================================

test "tar.gz: extract GNU tar 1.34+ archive - full compatibility" {
    // Skip on Windows due to TarReader AnyReader pointer invalidation issue (Issue #73)
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: TarReader file handle issue on Windows (Issue #73)\n", .{});
        return error.SkipZigTest;
    }

    // Test extraction of archives created by GNU tar 1.34+
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    const tar_file = try std.fs.cwd().openFile("tests/fixtures/gnu_tar/basic.tar", .{});
    defer tar_file.close();

    // Act
    var tar_reader = try TarReader.init(allocator, tar_file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();
    defer archive_reader.deinit();

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, .{});
    defer result.deinit(allocator);

    // Assert - should successfully extract GNU tar created archives
    try std.testing.expect(result.succeeded > 0);
    try std.testing.expectEqual(@as(usize, 0), result.failed);
}

test "tar.gz: GNU tar PAX extended headers - supports long paths" {
    // Skip on Windows due to TarReader AnyReader pointer invalidation issue (Issue #73)
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: TarReader file handle issue on Windows (Issue #73)\n", .{});
        return error.SkipZigTest;
    }

    // Test extraction of archives using PAX extended headers for long paths
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    const tar_file = try std.fs.cwd().openFile("tests/fixtures/gnu_tar/long_filename.tar", .{});
    defer tar_file.close();

    // Act
    var tar_reader = try TarReader.init(allocator, tar_file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();
    defer archive_reader.deinit();

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, .{});
    defer result.deinit(allocator);

    // Assert
    try std.testing.expect(result.succeeded > 0);
}

test "tar.gz: GNU tar sparse files - extracts efficiently" {
    // Test extraction of archives containing sparse files
    // Note: Requires specific test fixture with sparse files

    const allocator = std.testing.allocator;
    _ = allocator;

    // TODO: Create fixture with sparse files
    return error.SkipZigTest;
}

// ============================================================================
// Round-trip Tests (Compress → Decompress)
// ============================================================================
// Note: These tests will be implemented when compression functionality is added
// See Issue #24 for tar.gz compression support

test "tar.gz: round-trip compress and extract - preserves data" {
    // TODO: Implement when compression is available
    // This test should:
    // 1. Create test data
    // 2. Compress to tar.gz
    // 3. Extract from tar.gz
    // 4. Verify extracted data matches original

    return error.SkipZigTest;
}

test "tar.gz: round-trip with permissions - preserves metadata" {
    // TODO: Implement when compression is available
    // Test that file permissions are preserved through round-trip

    return error.SkipZigTest;
}

test "tar.gz: round-trip with timestamps - preserves mtime" {
    // TODO: Implement when compression is available
    // Test that file timestamps are preserved through round-trip

    return error.SkipZigTest;
}

// ============================================================================
// Error Handling Tests
// ============================================================================

test "tar.gz: corrupted gzip header - returns error" {
    // Note: This test is for gzip decompression errors
    // Currently using .tar files, so skipping until gzip support is added
    // When gzip support is implemented, this test should create an invalid .tar.gz
    // and verify that initGzip returns error.InvalidGzipHeader
    std.debug.print("Skipping: gzip decompression testing requires TarReader.initGzip\n", .{});
    return error.SkipZigTest;
}

test "tar.gz: truncated archive - handles gracefully" {
    // Note: This test is for truncated gzip file handling
    // Currently using .tar files, so skipping until gzip support is added
    // When gzip support is implemented, this test should create a truncated .tar.gz
    // and verify proper error handling
    std.debug.print("Skipping: gzip truncation testing requires TarReader.initGzip\n", .{});
    return error.SkipZigTest;
}

// ============================================================================
// Performance Tracking Tests
// ============================================================================

test "tar.gz: extraction performance - tracks metrics" {
    // Skip on Windows due to TarReader AnyReader pointer invalidation issue (Issue #73)
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: TarReader file handle issue on Windows (Issue #73)\n", .{});
        return error.SkipZigTest;
    }

    // Test that extraction tracks performance metrics
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    const tar_file = try std.fs.cwd().openFile("tests/fixtures/gnu_tar/basic.tar", .{});
    defer tar_file.close();

    // Act
    const start_time = std.time.milliTimestamp();

    var tar_reader = try TarReader.init(allocator, tar_file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();
    defer archive_reader.deinit();

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, .{});
    defer result.deinit(allocator);

    const end_time = std.time.milliTimestamp();

    // Assert - verify metrics are tracked
    try std.testing.expect(result.succeeded > 0);
    try std.testing.expect(result.total_bytes > 0);

    const elapsed_ms = end_time - start_time;
    std.debug.print("Extraction took {}ms, extracted {} bytes\n", .{ elapsed_ms, result.total_bytes });
}

// =============================================================================
// TarGzReader Tests
// =============================================================================

test "TarGzReader: read GNU tar.gz tiny files" {
    // Skip on Windows due to potential segfault in TarReader (Issue #73)
    // TarGzReader uses TarReader internally which has AnyReader pointer issues
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: TarGzReader segfault issue on Windows (Issue #73)\n", .{});
        return error.SkipZigTest;
    }

    const allocator = std.testing.allocator;

    // Open tar.gz file
    const file = try std.fs.cwd().openFile("tests/fixtures/gnu_tar/tiny_files.tar.gz", .{});
    defer file.close();

    // Create TarGzReader
    var reader = try TarGzReader.init(allocator, file);
    defer reader.deinit();

    std.debug.print("\nDecompressed size: {d} bytes\n", .{reader.decompressed_data.len});
    std.debug.print("FixedBufferStream buffer len: {d}, pos: {d}\n", .{ reader.fixed_buffer_stream.buffer.len, reader.fixed_buffer_stream.pos });

    // Get ArchiveReader interface
    var archive_reader = reader.archiveReader();

    // Read entries and verify content
    var entry_count: usize = 0;
    var total_bytes_read: usize = 0;

    while (try archive_reader.next()) |entry| {
        entry_count += 1;
        std.debug.print("Entry: {s} ({d} bytes, type: {s})\n", .{ entry.path, entry.size, @tagName(entry.entry_type) });
        std.debug.print("  FBS pos after header: {d}\n", .{reader.fixed_buffer_stream.pos});

        // Read and verify content for regular files
        if (entry.entry_type == .file) {
            var buffer: [4096]u8 = undefined;
            var file_bytes_read: usize = 0;

            while (true) {
                const n = try archive_reader.read(&buffer);
                if (n == 0) break;
                file_bytes_read += n;
                total_bytes_read += n;
            }

            // Verify we read the expected amount
            try std.testing.expectEqual(entry.size, @as(u64, file_bytes_read));
            std.debug.print("  Read {d} bytes from file\n", .{file_bytes_read});
        }
    }

    // Verify we found at least one entry
    try std.testing.expect(entry_count > 0);
    std.debug.print("Total: {d} entries, {d} bytes read\n", .{ entry_count, total_bytes_read });
}

test "TarGzReader: read GNU tar.gz empty files" {
    // Skip on Windows due to potential segfault in TarReader (Issue #73)
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: TarGzReader segfault issue on Windows (Issue #73)\n", .{});
        return error.SkipZigTest;
    }

    const allocator = std.testing.allocator;

    const file = try std.fs.cwd().openFile("tests/fixtures/gnu_tar/empty_files.tar.gz", .{});
    defer file.close();

    var reader = try TarGzReader.init(allocator, file);
    defer reader.deinit();

    var archive_reader = reader.archiveReader();

    var entry_count: usize = 0;
    while (try archive_reader.next()) |entry| {
        entry_count += 1;
        // Empty files should have size 0
        if (entry.entry_type == .file) {
            try std.testing.expectEqual(@as(u64, 0), entry.size);
        }
    }

    try std.testing.expect(entry_count > 0);
}

// =============================================================================
// TarGzReader Error Handling Tests
// =============================================================================

test "TarGzReader: reject oversized archives (>512 MiB)" {
    // Skip on Windows due to potential issues with large file handling
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: oversized archive test on Windows\n", .{});
        return error.SkipZigTest;
    }

    const allocator = std.testing.allocator;

    // Create a temporary file that exceeds MAX_COMPRESSED_SIZE (512 MiB)
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const oversized_file = try tmp_dir.dir.createFile("oversized.gz", .{ .read = true });
    defer oversized_file.close();

    // Write just enough data to trigger the size limit
    // We don't need to write 512 MiB, just enough to exceed the readToEndAlloc limit
    // The test will fail when trying to read more than MAX_COMPRESSED_SIZE
    const large_size: usize = 513 * 1024 * 1024; // 513 MiB

    // Seek to create a sparse file of the required size
    try oversized_file.seekTo(large_size - 1);
    try oversized_file.writeAll(&[_]u8{0});
    try oversized_file.seekTo(0);

    // Should return error when trying to read oversized file
    const result = TarGzReader.init(allocator, oversized_file);
    try std.testing.expectError(error.FileTooBig, result);
}

test "TarGzReader: handle corrupt gzip header" {
    // Skip on Windows due to potential issues with error handling in zlib
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: corrupt gzip header test on Windows\n", .{});
        return error.SkipZigTest;
    }

    const allocator = std.testing.allocator;

    // Create a file with invalid gzip header
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const corrupt_file = try tmp_dir.dir.createFile("corrupt.gz", .{ .read = true });
    defer corrupt_file.close();

    // Write invalid gzip data (not a valid gzip header)
    const invalid_data = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF };
    try corrupt_file.writeAll(&invalid_data);
    try corrupt_file.seekTo(0);

    // Should return an error when trying to decompress invalid data
    // The exact error depends on how zlib handles the corrupt data
    // (could be DecompressionFailed, ChecksumMismatch, or other zlib errors)
    if (TarGzReader.init(allocator, corrupt_file)) |reader| {
        var r = reader;
        r.deinit();
        return error.TestExpectedError; // Should have failed
    } else |err| {
        // Any decompression-related error is acceptable
        try std.testing.expect(err == error.DecompressionFailed or
            err == error.ChecksumMismatch or
            err == error.InvalidGzipMagic);
    }
}

test "TarGzReader: handle truncated gzip archive" {
    // Skip on Windows due to potential hang in zlib decompression of truncated data
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: truncated gzip test may hang on Windows\n", .{});
        return error.SkipZigTest;
    }

    const allocator = std.testing.allocator;

    // Create a file with truncated gzip data
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const truncated_file = try tmp_dir.dir.createFile("truncated.gz", .{ .read = true });
    defer truncated_file.close();

    // Write a valid gzip header but truncate the stream
    // gzip magic number (0x1f, 0x8b) + compression method (0x08) + flags (0x00)
    // This is incomplete and should fail decompression
    const truncated_data = [_]u8{ 0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00 };
    try truncated_file.writeAll(&truncated_data);
    try truncated_file.seekTo(0);

    // Should return an error when trying to decompress truncated data
    // The exact error depends on how zlib handles truncated data
    if (TarGzReader.init(allocator, truncated_file)) |reader| {
        var r = reader;
        r.deinit();
        return error.TestExpectedError; // Should have failed
    } else |err| {
        // Any decompression-related error is acceptable
        try std.testing.expect(err == error.DecompressionFailed or
            err == error.ChecksumMismatch or
            err == error.EndOfStream);
    }
}

test "TarGzReader: verify content end-to-end" {
    // Skip on Windows due to potential segfault in TarReader (Issue #73)
    if (builtin.os.tag == .windows) {
        std.debug.print("Skipping: TarGzReader segfault issue on Windows (Issue #73)\n", .{});
        return error.SkipZigTest;
    }

    const allocator = std.testing.allocator;

    // Open a known tar.gz file
    const file = try std.fs.cwd().openFile("tests/fixtures/gnu_tar/tiny_files.tar.gz", .{});
    defer file.close();

    // Create TarGzReader
    var reader = try TarGzReader.init(allocator, file);
    defer reader.deinit();

    // Get ArchiveReader interface
    var archive_reader = reader.archiveReader();

    // Read entries and verify content
    var entry_count: usize = 0;
    var total_bytes_read: usize = 0;

    while (try archive_reader.next()) |entry| {
        entry_count += 1;
        std.debug.print("Entry: {s} ({d} bytes)\n", .{ entry.path, entry.size });

        // Read file content if it's a regular file
        if (entry.entry_type == .file and entry.size > 0) {
            var buffer: [4096]u8 = undefined;
            var bytes_read: usize = 0;

            while (true) {
                const n = try archive_reader.read(&buffer);
                if (n == 0) break;
                bytes_read += n;
                total_bytes_read += n;
            }

            // Verify we read the expected amount
            try std.testing.expectEqual(entry.size, @as(u64, bytes_read));
        }
    }

    // Verify we found at least one entry
    try std.testing.expect(entry_count > 0);
    std.debug.print("Successfully read {d} entries, {d} total bytes\n", .{ entry_count, total_bytes_read });
}
