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

const std = @import("std");
const errors = @import("../core/errors.zig");
const types = @import("../core/types.zig");
const archive = @import("../formats/archive.zig");
const security = @import("security.zig");
const platform = @import("../platform/common.zig");

/// Options for archive extraction
pub const ExtractOptions = struct {
    /// Overwrite existing files
    /// Default: false (fail if file exists)
    overwrite: bool = false,

    /// Preserve file permissions from archive
    /// Default: false (use default permissions for security)
    preserve_permissions: bool = false,

    /// Preserve file timestamps from archive
    /// Default: true (maintain original timestamps)
    preserve_timestamps: bool = true,

    /// Continue extraction even if some entries fail
    /// Default: false (stop on first error)
    continue_on_error: bool = false,

    /// Security policy to apply during extraction
    /// Default: SecurityPolicy{} (secure defaults)
    security_policy: security.SecurityPolicy = .{},

    /// Verbose output
    /// Default: false
    verbose: bool = false,
};

/// Result of an extraction operation
pub const ExtractResult = struct {
    /// Number of successfully extracted entries
    succeeded: usize = 0,

    /// Number of failed entries
    failed: usize = 0,

    /// Warnings encountered during extraction
    warnings: std.ArrayListUnmanaged(Warning) = .{},

    /// Total bytes extracted
    total_bytes: u64 = 0,

    /// Warning information
    pub const Warning = struct {
        /// Path of the entry that generated the warning
        entry_path: []u8,

        /// Error that occurred
        err: anyerror,

        /// Human-readable message
        message: []const u8,
    };

    /// Initialize extraction result
    pub fn init(allocator: std.mem.Allocator) ExtractResult {
        _ = allocator;
        return .{};
    }

    /// Clean up resources
    pub fn deinit(self: *ExtractResult, allocator: std.mem.Allocator) void {
        for (self.warnings.items) |warning| {
            allocator.free(warning.message);
            allocator.free(warning.entry_path);
        }
        self.warnings.deinit(allocator);
    }

    /// Add a warning
    fn addWarning(
        self: *ExtractResult,
        allocator: std.mem.Allocator,
        entry_path: []const u8,
        err: anyerror,
    ) !void {
        // Format human-readable message
        // Try to format as ZarcError if possible, otherwise use generic format
        const message = switch (err) {
            // Core errors
            error.OutOfMemory,
            error.InvalidArgument,
            error.Overflow,
            error.BufferTooSmall,
            // I/O errors
            error.FileNotFound,
            error.PermissionDenied,
            error.DiskFull,
            error.ReadError,
            error.WriteError,
            error.SeekError,
            // Compression errors
            error.InvalidData,
            error.UnsupportedMethod,
            error.CorruptedStream,
            error.DecompressionFailed,
            error.CompressionFailed,
            // Format errors
            error.InvalidFormat,
            error.UnsupportedVersion,
            error.CorruptedHeader,
            error.IncompleteArchive,
            // Application errors
            error.PathTraversalAttempt,
            error.AbsolutePathNotAllowed,
            error.SymlinkEscapeAttempt,
            error.FileSizeExceedsLimit,
            error.SuspiciousCompressionRatio,
            error.TotalSizeExceedsLimit,
            error.EmptyPath,
            error.NullByteInPath,
            error.PathTooLong,
            error.InvalidCharacterInPath,
            error.SymlinkNotAllowed,
            error.AbsoluteSymlinkNotAllowed,
            error.NullByteInFilename,
            => errors.formatError(allocator, @errorCast(err), .{
                .path = entry_path,
            }) catch try std.fmt.allocPrint(allocator, "Error: {s}\nFile: {s}", .{ @errorName(err), entry_path }),
            else => try std.fmt.allocPrint(allocator, "Error: {s}\nFile: {s}", .{ @errorName(err), entry_path }),
        };
        errdefer allocator.free(message);

        // Persist entry_path
        const path_copy = try allocator.alloc(u8, entry_path.len);
        @memcpy(path_copy, entry_path);

        try self.warnings.append(allocator, .{
            .entry_path = path_copy,
            .err = err,
            .message = message,
        });
    }
};

/// Extract an archive to a destination directory
///
/// This is the main extraction function that handles all archive formats
/// through the ArchiveReader trait. It applies security checks, creates
/// directories, extracts files, and handles errors according to the options.
///
/// Security Features:
///   - Path validation (prevent traversal attacks)
///   - Zip bomb detection
///   - Symlink validation
///   - Size limits enforcement
///
/// Parameters:
///   - allocator: Memory allocator
///   - reader: Archive reader (implements ArchiveReader trait)
///   - dest_path: Destination directory path
///   - options: Extraction options
///
/// Returns:
///   - ExtractResult containing success/failure counts and warnings
///
/// Errors:
///   - error.FileNotFound: Destination directory doesn't exist
///   - error.PermissionDenied: Insufficient permissions
///   - (All security errors from security.zig)
///   - (All archive reading errors)
///
/// Example:
/// ```zig
/// const file = try std.fs.cwd().openFile("archive.tar", .{});
/// defer file.close();
///
/// var tar_reader = try TarReader.init(allocator, file);
/// defer tar_reader.deinit();
///
/// var arch = tar_reader.archiveReader();
/// defer arch.deinit();
///
/// var result = try extractArchive(allocator, &arch, "/dest", .{});
/// defer result.deinit(allocator);
///
/// std.debug.print("Extracted {d} files\n", .{result.succeeded});
/// ```
pub fn extractArchive(
    allocator: std.mem.Allocator,
    reader: *archive.ArchiveReader,
    dest_path: []const u8,
    options: ExtractOptions,
) !ExtractResult {
    var result = ExtractResult.init(allocator);
    errdefer result.deinit(allocator);

    // Open destination directory
    var dest_dir = try std.fs.cwd().openDir(dest_path, .{});
    defer dest_dir.close();

    // Initialize extraction tracker for cumulative size checks
    var tracker = security.ExtractionTracker.init(options.security_policy);

    // Extract each entry
    while (try reader.next()) |entry| {
        if (options.verbose) {
            std.debug.print("Extracting: {s}\n", .{entry.path});
        }

        // Extract this entry
        extractEntry(
            allocator,
            reader,
            entry,
            dest_dir,
            &tracker,
            options,
        ) catch |err| {
            result.failed += 1;

            if (options.continue_on_error) {
                // Log warning and continue
                try result.addWarning(allocator, entry.path, err);

                if (options.verbose) {
                    std.debug.print("  Warning: {s}\n", .{@errorName(err)});
                }
                continue;
            } else {
                // Stop on error
                return err;
            }
        };

        result.succeeded += 1;
        result.total_bytes += entry.size;
    }

    return result;
}

/// Extract a single entry from an archive
///
/// Internal function that handles extraction of one entry (file, directory,
/// symlink, etc.) with all security checks applied.
///
/// Parameters:
///   - allocator: Memory allocator
///   - reader: Archive reader
///   - entry: Entry metadata to extract
///   - dest_dir: Destination directory handle
///   - tracker: Extraction tracker for cumulative checks
///   - options: Extraction options
///
/// Errors:
///   - (All security errors)
///   - (All I/O errors)
fn extractEntry(
    allocator: std.mem.Allocator,
    reader: *archive.ArchiveReader,
    entry: types.Entry,
    dest_dir: std.fs.Dir,
    tracker: *security.ExtractionTracker,
    options: ExtractOptions,
) !void {
    // Validate path for security
    const validated_path = try security.sanitizePath(
        entry.path,
        options.security_policy,
    );

    // Check for zip bomb (individual file)
    try security.checkZipBomb(
        0, // We don't track compressed size per entry for tar
        entry.size,
        options.security_policy,
    );

    // Track cumulative extraction size
    try tracker.addFile(entry.size);

    // Extract based on entry type
    switch (entry.entry_type) {
        .directory => {
            try extractDirectory(validated_path, entry, dest_dir, options);
        },
        .file => {
            try extractFile(
                allocator,
                reader,
                entry,
                validated_path,
                dest_dir,
                options,
            );
        },
        .symlink => {
            try extractSymlink(
                allocator,
                entry,
                validated_path,
                dest_dir,
                options,
            );
        },
        .hardlink => {
            try extractHardlink(entry, validated_path, dest_dir, options);
        },
        else => {
            // Skip unsupported entry types (devices, fifos, etc.)
            std.log.warn("Skipping unsupported entry type: {s} ({s})", .{
                entry.path,
                @tagName(entry.entry_type),
            });
        },
    }
}

/// Extract a directory entry
fn extractDirectory(
    validated_path: []const u8,
    entry: types.Entry,
    dest_dir: std.fs.Dir,
    options: ExtractOptions,
) !void {
    // Create directory (makePath creates parent directories as needed)
    try dest_dir.makePath(validated_path);

    // Set permissions if requested
    if (options.preserve_permissions and options.security_policy.preserve_permissions) {
        // Get absolute path for platform-specific operations
        const abs_path = try dest_dir.realpathAlloc(
            std.heap.page_allocator,
            validated_path,
        );
        defer std.heap.page_allocator.free(abs_path);

        const plat = platform.getPlatform();
        try plat.setFilePermissions(abs_path, entry.mode);
    }

    // Set timestamp if requested
    if (options.preserve_timestamps) {
        const abs_path = try dest_dir.realpathAlloc(
            std.heap.page_allocator,
            validated_path,
        );
        defer std.heap.page_allocator.free(abs_path);

        const plat = platform.getPlatform();
        try plat.setFileTime(abs_path, entry.mtime);
    }
}

/// Extract a regular file entry
fn extractFile(
    allocator: std.mem.Allocator,
    reader: *archive.ArchiveReader,
    entry: types.Entry,
    validated_path: []const u8,
    dest_dir: std.fs.Dir,
    options: ExtractOptions,
) !void {
    // Ensure parent directories exist
    if (std.fs.path.dirname(validated_path)) |parent| {
        if (parent.len > 0) {
            try dest_dir.makePath(parent);
        }
    }

    // Determine file creation flags
    const create_flags: std.fs.File.CreateFlags = .{
        .exclusive = !options.overwrite, // Fail if exists unless overwrite=true
        .truncate = options.overwrite,
    };

    // Create file
    const file = dest_dir.createFile(validated_path, create_flags) catch |err| {
        // Provide better error message for common case
        if (err == error.PathAlreadyExists) {
            std.log.err("File already exists: {s} (use --overwrite to replace)", .{
                validated_path,
            });
        }
        return err;
    };
    defer file.close();

    // Read and write data in chunks
    var bytes_written: u64 = 0;
    var buffer: [types.BufferSize.default]u8 = undefined;

    while (bytes_written < entry.size) {
        const remaining: u64 = entry.size - bytes_written;
        const to_read_u64: u64 = if (remaining > buffer.len) buffer.len else remaining;
        const to_read: usize = @intCast(to_read_u64);
        const n: usize = try reader.read(buffer[0..to_read]);

        if (n == 0) {
            // Unexpected EOF
            std.log.err("Unexpected end of data for: {s} (expected {d} bytes, got {d})", .{
                validated_path,
                entry.size,
                bytes_written,
            });
            return error.IncompleteArchive;
        }

        try file.writeAll(buffer[0..n]);
        bytes_written += @as(u64, n);
    }

    // Verify we read exactly the right amount
    if (bytes_written != entry.size) {
        std.log.err("Size mismatch for {s}: expected {d}, got {d}", .{
            validated_path,
            entry.size,
            bytes_written,
        });
        return error.IncompleteArchive;
    }

    // Set permissions if requested
    if (options.preserve_permissions and options.security_policy.preserve_permissions) {
        const abs_path = try dest_dir.realpathAlloc(allocator, validated_path);
        defer allocator.free(abs_path);

        const plat = platform.getPlatform();
        try plat.setFilePermissions(abs_path, entry.mode);
    }

    // Set timestamp if requested
    if (options.preserve_timestamps) {
        const abs_path = try dest_dir.realpathAlloc(allocator, validated_path);
        defer allocator.free(abs_path);

        const plat = platform.getPlatform();
        try plat.setFileTime(abs_path, entry.mtime);
    }
}

/// Extract a symbolic link entry
fn extractSymlink(
    allocator: std.mem.Allocator,
    entry: types.Entry,
    validated_path: []const u8,
    dest_dir: std.fs.Dir,
    options: ExtractOptions,
) !void {
    // Validate symlink target
    const dest_path_abs = try dest_dir.realpathAlloc(allocator, ".");
    defer allocator.free(dest_path_abs);

    try security.validateSymlink(
        allocator,
        validated_path,
        entry.link_target,
        dest_path_abs,
        options.security_policy,
    );

    // Ensure parent directories exist
    if (std.fs.path.dirname(validated_path)) |parent| {
        if (parent.len > 0) {
            try dest_dir.makePath(parent);
        }
    }

    // Create symlink (optionally overwrite)
    if (options.overwrite) {
        dest_dir.deleteFile(validated_path) catch |e| {
            if (e != error.FileNotFound) return e;
        };
    }
    try dest_dir.symLink(entry.link_target, validated_path, .{});

    // Note: We don't set permissions on symlinks as they're typically
    // not meaningful (the target's permissions are what matter)

    // Note: Setting timestamps on symlinks is platform-specific and
    // often requires special system calls (lutimes). We skip this for now.
}

/// Extract a hard link entry
fn extractHardlink(
    entry: types.Entry,
    validated_path: []const u8,
    dest_dir: std.fs.Dir,
    options: ExtractOptions,
) !void {
    // Validate link target path with configured policy
    const validated_target = try security.sanitizePath(entry.link_target, options.security_policy);

    // Ensure parent directories exist
    if (std.fs.path.dirname(validated_path)) |parent| {
        if (parent.len > 0) {
            try dest_dir.makePath(parent);
        }
    }

    // Honor overwrite
    if (options.overwrite) {
        dest_dir.deleteFile(validated_path) catch |e| {
            if (e != error.FileNotFound) return e;
        };
    }

    // Create hard link
    // Note: This requires the target to already exist
    // Get absolute paths for linking
    const abs_target = try dest_dir.realpathAlloc(std.heap.page_allocator, validated_target);
    defer std.heap.page_allocator.free(abs_target);

    const dest_base = try dest_dir.realpathAlloc(std.heap.page_allocator, ".");
    defer std.heap.page_allocator.free(dest_base);

    const abs_link = try std.fs.path.join(std.heap.page_allocator, &.{
        dest_base,
        validated_path,
    });
    defer std.heap.page_allocator.free(abs_link);

    // Create hardlink using platform abstraction
    const plat = platform.getPlatform();
    try plat.createHardLink(abs_target, abs_link);
}

// Tests
test "ExtractOptions: default values are secure" {
    const options = ExtractOptions{};

    try std.testing.expectEqual(false, options.overwrite);
    try std.testing.expectEqual(false, options.preserve_permissions);
    try std.testing.expectEqual(true, options.preserve_timestamps);
    try std.testing.expectEqual(false, options.continue_on_error);
    try std.testing.expectEqual(false, options.verbose);
}

test "ExtractResult: init and deinit" {
    const allocator = std.testing.allocator;

    var result = ExtractResult.init(allocator);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.succeeded);
    try std.testing.expectEqual(@as(usize, 0), result.failed);
    try std.testing.expectEqual(@as(u64, 0), result.total_bytes);
    try std.testing.expectEqual(@as(usize, 0), result.warnings.items.len);
}

test "ExtractResult: add warning" {
    const allocator = std.testing.allocator;

    var result = ExtractResult.init(allocator);
    defer result.deinit(allocator);

    try result.addWarning(allocator, "test.txt", error.FileNotFound);

    try std.testing.expectEqual(@as(usize, 1), result.warnings.items.len);
    try std.testing.expectEqualStrings("test.txt", result.warnings.items[0].entry_path);
    try std.testing.expectEqual(error.FileNotFound, result.warnings.items[0].err);
}

test "extractArchive: empty archive" {
    const allocator = std.testing.allocator;

    // Create mock empty reader
    const MockReader = struct {
        fn nextImpl(_: *anyopaque) anyerror!?types.Entry {
            return null;
        }

        fn readImpl(_: *anyopaque, _: []u8) anyerror!usize {
            return 0;
        }

        fn deinitImpl(_: *anyopaque) void {}

        fn archiveReader(self: *@This()) archive.ArchiveReader {
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

    var mock = MockReader{};
    var reader = mock.archiveReader();
    defer reader.deinit();

    // Create temporary directory
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dest_path);

    // Extract
    var result = try extractArchive(allocator, &reader, dest_path, .{});
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.succeeded);
    try std.testing.expectEqual(@as(usize, 0), result.failed);
}

test "extractArchive: continue on error" {
    const allocator = std.testing.allocator;

    // Create mock reader that fails on first entry, succeeds on second
    const MockReader = struct {
        call_count: usize = 0,

        fn nextImpl(ptr: *anyopaque) anyerror!?types.Entry {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.call_count += 1;

            return switch (self.call_count) {
                1 => types.Entry{
                    .path = "../../../etc/passwd", // This will fail security check
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

        fn archiveReader(self: *@This()) archive.ArchiveReader {
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

    var mock = MockReader{};
    var reader = mock.archiveReader();
    defer reader.deinit();

    // Create temporary directory
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const dest_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(dest_path);

    // Extract with continue_on_error
    const options = ExtractOptions{
        .continue_on_error = true,
    };

    var result = try extractArchive(allocator, &reader, dest_path, options);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), result.succeeded);
    try std.testing.expectEqual(@as(usize, 1), result.failed);
    try std.testing.expectEqual(@as(usize, 1), result.warnings.items.len);
}
