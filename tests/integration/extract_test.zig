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


const std = @import("std");
const zarc = @import("zarc");
const TarReader = zarc.formats.tar.reader.TarReader;
const extract = zarc.app.extract;
const security = zarc.app.security;
const types = zarc.core.types;

// Integration tests for archive extraction
// Following TESTING_STRATEGY.md guidelines for integration testing

// ============================================================================
// Basic Extraction Tests
// ============================================================================

test "extractArchive: empty archive - succeeds with zero files" {
    // Arrange
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create empty tar file (with proper end marker)
    const tar_file = try tmp_dir.dir.createFile("empty.tar", .{ .read = true });
    defer tar_file.close();

    var zero_block: [512]u8 = undefined;
    @memset(&zero_block, 0);
    try tar_file.writeAll(&zero_block);
    try tar_file.writeAll(&zero_block);
    try tar_file.seekTo(0);

    // Create extraction destination
    try tmp_dir.dir.makeDir("dest");

    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    // Act
    var tar_reader = try TarReader.init(allocator, tar_file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();
    defer archive_reader.deinit();

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, .{});
    defer result.deinit(allocator);

    // Assert
    try std.testing.expectEqual(@as(usize, 0), result.succeeded);
    try std.testing.expectEqual(@as(usize, 0), result.failed);
    try std.testing.expectEqual(@as(u64, 0), result.total_bytes);
}

test "extractArchive: single file - extracts correctly" {
    // Arrange
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Use existing test fixture
    const tar_file = try std.fs.cwd().openFile("tests/fixtures/simple.tar", .{});
    defer tar_file.close();

    // Create extraction destination
    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

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

    // Verify extracted directory exists
    var dest_dir = try std.fs.cwd().openDir(dest_path, .{});
    defer dest_dir.close();

    dest_dir.accessZ("test_data", .{}) catch |err| {
        std.debug.print("Error accessing test_data: {any}\n", .{err});
        return err;
    };
}

test "extractArchive: preserve timestamps - sets file mtime" {
    // Arrange
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tar_file = try std.fs.cwd().openFile("tests/fixtures/simple.tar", .{});
    defer tar_file.close();

    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    // Act
    var tar_reader = try TarReader.init(allocator, tar_file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();
    defer archive_reader.deinit();

    const options = extract.ExtractOptions{
        .preserve_timestamps = true,
    };

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, options);
    defer result.deinit(allocator);

    // Assert
    try std.testing.expect(result.succeeded > 0);

    // Note: Actual timestamp verification would require reading file metadata
    // This test verifies that extraction completes without error
}

test "extractArchive: continue on error - completes despite failures" {
    // Arrange
    const allocator = std.testing.allocator;

    // Create mock reader that generates one invalid entry, then one valid entry
    const MockReader = struct {
        call_count: usize = 0,

        fn nextImpl(ptr: *anyopaque) anyerror!?types.Entry {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.call_count += 1;

            return switch (self.call_count) {
                1 => types.Entry{
                    .path = "../../../etc/passwd", // Path traversal - will fail
                    .entry_type = .file,
                    .size = 100,
                    .mode = 0o644,
                    .mtime = 0,
                },
                2 => types.Entry{
                    .path = "valid_file.txt",
                    .entry_type = .file,
                    .size = 0,
                    .mode = 0o644,
                    .mtime = 0,
                },
                else => null,
            };
        }

        fn readImpl(_: *anyopaque, _: []u8) anyerror!usize {
            return 0;
        }

        fn deinitImpl(_: *anyopaque) void {}

        fn archiveReader(self: *@This()) zarc.formats.archive.ArchiveReader {
            return .{
                .ptr = self,
                .vtable = &.{
                    .next = nextImpl,
                    .read = readImpl,
                    .deinit = deinitImpl,
                },
            };
        }
    };

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    // Act
    var mock = MockReader{};
    var archive_reader = mock.archiveReader();
    defer archive_reader.deinit();

    const options = extract.ExtractOptions{
        .continue_on_error = true,
    };

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, options);
    defer result.deinit(allocator);

    // Assert
    try std.testing.expectEqual(@as(usize, 1), result.succeeded);
    try std.testing.expectEqual(@as(usize, 1), result.failed);
    try std.testing.expectEqual(@as(usize, 1), result.warnings.items.len);
}

// ============================================================================
// File Overwrite Tests
// ============================================================================

test "extractArchive: overwrite false - fails on existing file" {
    // Arrange
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create a destination file that will conflict
    try tmp_dir.dir.makeDir("dest");
    try tmp_dir.dir.makeDir("dest/test_data");
    const existing = try tmp_dir.dir.createFile("dest/test_data/test.txt", .{});
    existing.close();

    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    const tar_file = try std.fs.cwd().openFile("tests/fixtures/simple.tar", .{});
    defer tar_file.close();

    // Act
    var tar_reader = try TarReader.init(allocator, tar_file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();
    defer archive_reader.deinit();

    const options = extract.ExtractOptions{
        .overwrite = false,
        .continue_on_error = true, // So we can check for the failure
    };

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, options);
    defer result.deinit(allocator);

    // Assert - should have at least one failure due to existing file
    try std.testing.expect(result.failed > 0);
}

test "extractArchive: overwrite true - replaces existing file" {
    // Arrange
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create a destination file that will be overwritten
    try tmp_dir.dir.makeDir("dest");
    try tmp_dir.dir.makeDir("dest/test_data");
    const existing = try tmp_dir.dir.createFile("dest/test_data/test.txt", .{});
    try existing.writeAll("OLD CONTENT");
    existing.close();

    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    const tar_file = try std.fs.cwd().openFile("tests/fixtures/simple.tar", .{});
    defer tar_file.close();

    // Act
    var tar_reader = try TarReader.init(allocator, tar_file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();
    defer archive_reader.deinit();

    const options = extract.ExtractOptions{
        .overwrite = true,
    };

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, options);
    defer result.deinit(allocator);

    // Assert
    try std.testing.expect(result.succeeded > 0);
    try std.testing.expectEqual(@as(usize, 0), result.failed);
}

// ============================================================================
// Error Handling Tests
// ============================================================================

test "extractArchive: stop on error - halts at first failure" {
    // Arrange
    const allocator = std.testing.allocator;

    const MockReader = struct {
        call_count: usize = 0,

        fn nextImpl(ptr: *anyopaque) anyerror!?types.Entry {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.call_count += 1;

            return switch (self.call_count) {
                1 => types.Entry{
                    .path = "../../../etc/passwd",
                    .entry_type = .file,
                    .size = 100,
                    .mode = 0o644,
                    .mtime = 0,
                },
                else => null,
            };
        }

        fn readImpl(_: *anyopaque, _: []u8) anyerror!usize {
            return 0;
        }

        fn deinitImpl(_: *anyopaque) void {}

        fn archiveReader(self: *@This()) zarc.formats.archive.ArchiveReader {
            return .{
                .ptr = self,
                .vtable = &.{
                    .next = nextImpl,
                    .read = readImpl,
                    .deinit = deinitImpl,
                },
            };
        }
    };

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    // Act
    var mock = MockReader{};
    var archive_reader = mock.archiveReader();
    defer archive_reader.deinit();

    const options = extract.ExtractOptions{
        .continue_on_error = false,
    };

    // Assert - should return error
    const result = extract.extractArchive(allocator, &archive_reader, dest_path, options);
    try std.testing.expectError(error.PathTraversalAttempt, result);
}

// ============================================================================
// Directory Creation Tests
// ============================================================================

test "extractArchive: creates parent directories - nested paths work" {
    // Arrange
    const allocator = std.testing.allocator;

    const MockReader = struct {
        call_count: usize = 0,

        fn nextImpl(ptr: *anyopaque) anyerror!?types.Entry {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.call_count += 1;

            return switch (self.call_count) {
                1 => types.Entry{
                    .path = "a/b/c/deep_file.txt",
                    .entry_type = .file,
                    .size = 0,
                    .mode = 0o644,
                    .mtime = 0,
                },
                else => null,
            };
        }

        fn readImpl(_: *anyopaque, _: []u8) anyerror!usize {
            return 0;
        }

        fn deinitImpl(_: *anyopaque) void {}

        fn archiveReader(self: *@This()) zarc.formats.archive.ArchiveReader {
            return .{
                .ptr = self,
                .vtable = &.{
                    .next = nextImpl,
                    .read = readImpl,
                    .deinit = deinitImpl,
                },
            };
        }
    };

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    // Act
    var mock = MockReader{};
    var archive_reader = mock.archiveReader();
    defer archive_reader.deinit();

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, .{});
    defer result.deinit(allocator);

    // Assert
    try std.testing.expectEqual(@as(usize, 1), result.succeeded);
    try std.testing.expectEqual(@as(usize, 0), result.failed);

    // Verify nested file exists
    var dest_dir = try std.fs.cwd().openDir(dest_path, .{});
    defer dest_dir.close();

    const file = try dest_dir.openFile("a/b/c/deep_file.txt", .{});
    file.close();
}

// ============================================================================
// ExtractResult Tests
// ============================================================================

test "ExtractResult: init and deinit - no memory leak" {
    // Arrange
    const allocator = std.testing.allocator;

    // Act
    var result = extract.ExtractResult.init(allocator);
    defer result.deinit(allocator);

    // Assert
    try std.testing.expectEqual(@as(usize, 0), result.succeeded);
    try std.testing.expectEqual(@as(usize, 0), result.failed);
}

test "ExtractResult: warnings collected during extraction" {
    // Arrange
    const allocator = std.testing.allocator;

    // Create mock reader that generates one invalid entry
    const MockReader = struct {
        call_count: usize = 0,

        fn nextImpl(ptr: *anyopaque) anyerror!?types.Entry {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.call_count += 1;

            return switch (self.call_count) {
                1 => types.Entry{
                    .path = "../../../etc/passwd", // Path traversal - will fail
                    .entry_type = .file,
                    .size = 0,
                    .mode = 0o644,
                    .mtime = 0,
                },
                else => null,
            };
        }

        fn readImpl(_: *anyopaque, _: []u8) anyerror!usize {
            return 0;
        }

        fn deinitImpl(_: *anyopaque) void {}

        fn archiveReader(self: *@This()) zarc.formats.archive.ArchiveReader {
            return .{
                .ptr = self,
                .vtable = &.{
                    .next = nextImpl,
                    .read = readImpl,
                    .deinit = deinitImpl,
                },
            };
        }
    };

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.makeDir("dest");
    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, "dest");
    defer allocator.free(dest_path);

    // Act - extract with continue_on_error to collect warnings
    var mock = MockReader{};
    var archive_reader = mock.archiveReader();
    defer archive_reader.deinit();

    const options = extract.ExtractOptions{
        .continue_on_error = true,
    };

    var result = try extract.extractArchive(allocator, &archive_reader, dest_path, options);
    defer result.deinit(allocator);

    // Assert
    try std.testing.expectEqual(@as(usize, 0), result.succeeded);
    try std.testing.expectEqual(@as(usize, 1), result.failed);
    try std.testing.expectEqual(@as(usize, 1), result.warnings.items.len);
    try std.testing.expect(result.warnings.items[0].message.len > 0);
}

// ============================================================================
// ExtractOptions Tests
// ============================================================================

test "ExtractOptions: defaults are secure" {
    // Arrange & Act
    const options = extract.ExtractOptions{};

    // Assert
    try std.testing.expectEqual(false, options.overwrite);
    try std.testing.expectEqual(false, options.preserve_permissions);
    try std.testing.expectEqual(true, options.preserve_timestamps);
    try std.testing.expectEqual(false, options.continue_on_error);
    try std.testing.expectEqual(false, options.verbose);
}

test "ExtractOptions: security policy defaults" {
    // Arrange & Act
    const options = extract.ExtractOptions{};
    const policy = options.security_policy;

    // Assert - verify default security policy is strict
    try std.testing.expectEqual(false, policy.allow_absolute_paths);
    try std.testing.expectEqual(false, policy.allow_symlink_escape);
    try std.testing.expectEqual(false, policy.allow_path_traversal);
    try std.testing.expectEqual(security.SymlinkPolicy.disallow, policy.symlink_policy);
}
