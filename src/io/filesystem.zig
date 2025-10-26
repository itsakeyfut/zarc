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
const builtin = @import("builtin");
const types = @import("../core/types.zig");
const errors = @import("../core/errors.zig");

/// Cross-platform filesystem operations abstraction
///
/// This module provides:
/// - Platform-independent file operations
/// - Permission and timestamp handling
/// - Symlink creation and management
/// - Directory operations with proper error handling
pub const FileSystem = struct {
    allocator: std.mem.Allocator,

    /// Initialize filesystem operations
    pub fn init(allocator: std.mem.Allocator) FileSystem {
        return .{
            .allocator = allocator,
        };
    }

    /// Create a file with specified permissions
    ///
    /// Parameters:
    ///   - path: File path to create
    ///   - mode: POSIX permissions (e.g., 0o644)
    ///
    /// Returns:
    ///   - Opened file handle
    ///
    /// Errors:
    ///   - error.PermissionDenied: Insufficient permissions
    ///   - error.PathAlreadyExists: File already exists
    pub fn createFileWithMode(
        self: FileSystem,
        path: []const u8,
        mode: u32,
    ) !std.fs.File {
        _ = self;

        const file = try std.fs.cwd().createFile(path, .{
            .exclusive = true,
            .truncate = false,
        });
        errdefer file.close();

        // Set permissions (POSIX only)
        if (builtin.os.tag != .windows) {
            try file.chmod(@as(u16, @intCast(mode & 0o7777)));
        }

        return file;
    }

    /// Create a directory with specified permissions
    ///
    /// Parameters:
    ///   - path: Directory path to create
    ///   - mode: POSIX permissions (e.g., 0o755)
    ///
    /// Errors:
    ///   - error.PermissionDenied: Insufficient permissions
    ///   - error.PathAlreadyExists: Directory already exists
    pub fn createDirWithMode(
        self: FileSystem,
        path: []const u8,
        mode: u32,
    ) !void {
        _ = self;

        try std.fs.cwd().makeDir(path);

        // Set permissions (POSIX only)
        if (builtin.os.tag != .windows) {
            const file = try std.fs.cwd().openFile(path, .{});
            defer file.close();
            try file.chmod(@as(u16, @intCast(mode & 0o7777)));
        }
    }

    /// Create all parent directories recursively
    ///
    /// Parameters:
    ///   - path: Directory path to create
    ///
    /// Errors:
    ///   - error.PermissionDenied: Insufficient permissions
    pub fn createDirAll(
        self: FileSystem,
        path: []const u8,
    ) !void {
        _ = self;
        try std.fs.cwd().makePath(path);
    }

    /// Set file modification time
    ///
    /// Parameters:
    ///   - path: File path
    ///   - mtime: Modification time (Unix timestamp in seconds)
    ///
    /// Errors:
    ///   - error.FileNotFound: File does not exist
    ///   - error.PermissionDenied: Insufficient permissions
    pub fn setModificationTime(
        self: FileSystem,
        path: []const u8,
        mtime: i64,
    ) !void {
        _ = self;

        const file = try std.fs.cwd().openFile(path, .{ .mode = .read_write });
        defer file.close();

        const atime_nsec: i128 = @as(i128, mtime) * std.time.ns_per_s;
        const mtime_nsec: i128 = @as(i128, mtime) * std.time.ns_per_s;

        try file.updateTimes(atime_nsec, mtime_nsec);
    }

    /// Set file permissions (POSIX)
    ///
    /// Parameters:
    ///   - path: File path
    ///   - mode: POSIX permissions (e.g., 0o644)
    ///
    /// Errors:
    ///   - error.FileNotFound: File does not exist
    ///   - error.PermissionDenied: Insufficient permissions
    pub fn setPermissions(
        self: FileSystem,
        path: []const u8,
        mode: u32,
    ) !void {
        _ = self;

        if (builtin.os.tag == .windows) {
            // Windows doesn't support POSIX permissions
            // We could map some basic permissions here if needed
            return;
        }

        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        try file.chmod(@as(u16, @intCast(mode & 0o7777)));
    }

    /// Create a symbolic link
    ///
    /// Parameters:
    ///   - target: Target path the link points to
    ///   - link_path: Path where the symlink will be created
    ///
    /// Errors:
    ///   - error.PermissionDenied: Insufficient permissions
    ///   - error.PathAlreadyExists: Link already exists
    pub fn createSymlink(
        self: FileSystem,
        target: []const u8,
        link_path: []const u8,
    ) !void {
        _ = self;

        if (builtin.os.tag == .windows) {
            // Windows requires admin privileges for symlinks
            // Use std.fs.cwd().symLink which handles this
            try std.fs.cwd().symLink(target, link_path, .{});
        } else {
            try std.fs.cwd().symLink(target, link_path, .{});
        }
    }

    /// Read symlink target
    ///
    /// Parameters:
    ///   - link_path: Path to the symlink
    ///   - buffer: Buffer to store the target path
    ///
    /// Returns:
    ///   - Slice of buffer containing the target path
    ///
    /// Errors:
    ///   - error.FileNotFound: Link does not exist
    ///   - error.NotASymlink: Path is not a symlink
    pub fn readSymlink(
        self: FileSystem,
        link_path: []const u8,
        buffer: []u8,
    ) ![]const u8 {
        _ = self;
        return try std.fs.cwd().readLink(link_path, buffer);
    }

    /// Check if path is a symlink
    ///
    /// Parameters:
    ///   - path: Path to check
    ///
    /// Returns:
    ///   - true if path is a symlink, false otherwise
    pub fn isSymlink(
        self: FileSystem,
        path: []const u8,
    ) bool {
        _ = self;

        const stat = std.posix.fstatat(
            std.posix.AT.FDCWD,
            path,
            std.posix.AT.SYMLINK_NOFOLLOW,
        ) catch return false;
        return std.posix.S.ISLNK(stat.mode);
    }

    /// Check if path exists
    ///
    /// Parameters:
    ///   - path: Path to check
    ///
    /// Returns:
    ///   - true if path exists, false otherwise
    pub fn exists(
        self: FileSystem,
        path: []const u8,
    ) bool {
        _ = self;
        std.fs.cwd().access(path, .{}) catch return false;
        return true;
    }

    /// Check if path is a directory
    ///
    /// Parameters:
    ///   - path: Path to check
    ///
    /// Returns:
    ///   - true if path is a directory, false otherwise
    pub fn isDirectory(
        self: FileSystem,
        path: []const u8,
    ) bool {
        _ = self;

        // Try to open as directory - works reliably on all platforms including Windows
        // statFile() is unreliable for directories on Windows
        var dir = std.fs.cwd().openDir(path, .{}) catch return false;
        dir.close();
        return true;
    }

    /// Check if path is a regular file
    ///
    /// Parameters:
    ///   - path: Path to check
    ///
    /// Returns:
    ///   - true if path is a regular file, false otherwise
    pub fn isFile(
        self: FileSystem,
        path: []const u8,
    ) bool {
        _ = self;

        const stat = std.fs.cwd().statFile(path) catch return false;
        return stat.kind == .file;
    }

    /// Get file size
    ///
    /// Parameters:
    ///   - path: File path
    ///
    /// Returns:
    ///   - File size in bytes
    ///
    /// Errors:
    ///   - error.FileNotFound: File does not exist
    pub fn getFileSize(
        self: FileSystem,
        path: []const u8,
    ) !u64 {
        _ = self;

        const stat = try std.fs.cwd().statFile(path);
        return stat.size;
    }

    /// Remove a file
    ///
    /// Parameters:
    ///   - path: File path to remove
    ///
    /// Errors:
    ///   - error.FileNotFound: File does not exist
    ///   - error.PermissionDenied: Insufficient permissions
    pub fn removeFile(
        self: FileSystem,
        path: []const u8,
    ) !void {
        _ = self;
        try std.fs.cwd().deleteFile(path);
    }

    /// Remove a directory
    ///
    /// Parameters:
    ///   - path: Directory path to remove
    ///
    /// Errors:
    ///   - error.FileNotFound: Directory does not exist
    ///   - error.DirNotEmpty: Directory is not empty
    pub fn removeDir(
        self: FileSystem,
        path: []const u8,
    ) !void {
        _ = self;
        try std.fs.cwd().deleteDir(path);
    }

    /// Remove a directory tree recursively
    ///
    /// Parameters:
    ///   - path: Directory path to remove
    ///
    /// Errors:
    ///   - error.FileNotFound: Directory does not exist
    ///   - error.PermissionDenied: Insufficient permissions
    pub fn removeDirAll(
        self: FileSystem,
        path: []const u8,
    ) !void {
        _ = self;
        try std.fs.cwd().deleteTree(path);
    }
};

/// Sanitize path to prevent directory traversal attacks
///
/// This function checks for:
/// - Absolute paths (if not allowed)
/// - Path traversal attempts (..)
/// - Null bytes in path
///
/// Parameters:
///   - path: Path to sanitize
///   - allow_absolute: Whether to allow absolute paths
///
/// Returns:
///   - Sanitized path (same as input if valid)
///
/// Errors:
///   - error.AbsolutePathNotAllowed: Path is absolute
///   - error.PathTraversalAttempt: Path contains ..
///   - error.InvalidArgument: Path contains null bytes
pub fn sanitizePath(
    path: []const u8,
    allow_absolute: bool,
) ![]const u8 {
    // Check for null bytes
    if (std.mem.indexOfScalar(u8, path, 0) != null) {
        return error.InvalidArgument;
    }

    // Check for absolute paths
    if (!allow_absolute and std.fs.path.isAbsolute(path)) {
        return error.AbsolutePathNotAllowed;
    }

    // Check for path traversal
    var it = std.mem.tokenizeAny(u8, path, "/\\");
    var depth: i32 = 0;

    while (it.next()) |component| {
        if (std.mem.eql(u8, component, "..")) {
            depth -= 1;
            if (depth < 0) {
                return error.PathTraversalAttempt;
            }
        } else if (!std.mem.eql(u8, component, ".") and component.len > 0) {
            depth += 1;
        }
    }

    return path;
}

/// Join path components safely
///
/// Parameters:
///   - allocator: Memory allocator
///   - components: Path components to join
///
/// Returns:
///   - Joined path (caller must free)
///
/// Errors:
///   - error.OutOfMemory: Failed to allocate memory
pub fn joinPath(
    allocator: std.mem.Allocator,
    components: []const []const u8,
) ![]u8 {
    return try std.fs.path.join(allocator, components);
}

/// Get directory name from path
///
/// Parameters:
///   - path: File path
///
/// Returns:
///   - Directory portion of the path
pub fn dirname(path: []const u8) []const u8 {
    return std.fs.path.dirname(path) orelse ".";
}

/// Get file name from path
///
/// Parameters:
///   - path: File path
///
/// Returns:
///   - File name portion of the path
pub fn basename(path: []const u8) []const u8 {
    return std.fs.path.basename(path);
}

/// Normalize path by resolving . and .. components
///
/// Parameters:
///   - allocator: Memory allocator
///   - path: Path to normalize
///
/// Returns:
///   - Normalized path (caller must free)
///
/// Errors:
///   - error.OutOfMemory: Failed to allocate memory
pub fn normalizePath(
    allocator: std.mem.Allocator,
    path: []const u8,
) ![]u8 {
    var components = std.array_list.Aligned([]const u8, null).empty;
    defer components.deinit(allocator);

    const was_abs = std.fs.path.isAbsolute(path);
    var it = std.mem.tokenizeAny(u8, path, "/\\");
    while (it.next()) |component| {
        if (std.mem.eql(u8, component, ".") or component.len == 0) {
            continue;
        } else if (std.mem.eql(u8, component, "..")) {
            if (components.items.len > 0) {
                _ = components.pop();
            }
        } else {
            try components.append(allocator, component);
        }
    }

    const joined = try std.fs.path.join(allocator, components.items);
    errdefer allocator.free(joined);
    if (was_abs) {
        const prefix = if (builtin.os.tag == .windows) "" else "/";
        const result = try std.mem.concat(allocator, u8, &[_][]const u8{ prefix, joined });
        allocator.free(joined);
        return result;
    }
    return joined;
}

// Tests
test "FileSystem: createFileWithMode" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var fs = FileSystem.init(allocator);

    // Change to temp directory
    var old_cwd = try std.fs.cwd().openDir(".", .{});
    defer old_cwd.close();
    try tmp_dir.dir.setAsCwd();
    defer old_cwd.setAsCwd() catch {};

    const file = try fs.createFileWithMode("test.txt", 0o644);
    file.close();

    try std.testing.expect(fs.exists("test.txt"));
    try std.testing.expect(fs.isFile("test.txt"));
}

test "FileSystem: createDirWithMode and createDirAll" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var fs = FileSystem.init(allocator);

    var old_cwd = try std.fs.cwd().openDir(".", .{});
    defer old_cwd.close();
    try tmp_dir.dir.setAsCwd();
    defer old_cwd.setAsCwd() catch {};

    try fs.createDirWithMode("testdir", 0o755);
    try std.testing.expect(fs.exists("testdir"));
    try std.testing.expect(fs.isDirectory("testdir"));

    try fs.createDirAll("deep/nested/dir");
    try std.testing.expect(fs.exists("deep/nested/dir"));
}

test "FileSystem: setModificationTime" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var fs = FileSystem.init(allocator);

    var old_cwd = try std.fs.cwd().openDir(".", .{});
    defer old_cwd.close();
    try tmp_dir.dir.setAsCwd();
    defer old_cwd.setAsCwd() catch {};

    var file = try std.fs.cwd().createFile("test.txt", .{});
    file.close();

    const target_time: i64 = 1234567890;
    try fs.setModificationTime("test.txt", target_time);

    const stat = try std.fs.cwd().statFile("test.txt");
    const mtime_sec = @divTrunc(stat.mtime, std.time.ns_per_s);
    try std.testing.expectEqual(target_time, mtime_sec);
}

test "FileSystem: symlink operations" {
    if (builtin.os.tag == .windows or builtin.os.tag == .linux) {
        // Skip on Windows (requires admin) and WSL (symlink issues)
        return error.SkipZigTest;
    }

    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var fs = FileSystem.init(allocator);

    var old_cwd = try std.fs.cwd().openDir(".", .{});
    defer old_cwd.close();
    try tmp_dir.dir.setAsCwd();
    defer old_cwd.setAsCwd() catch {};

    // Create target file
    var file = try std.fs.cwd().createFile("target.txt", .{});
    file.close();

    // Create symlink
    try fs.createSymlink("target.txt", "link.txt");
    try std.testing.expect(fs.isSymlink("link.txt"));

    // Read symlink
    var buffer: [256]u8 = undefined;
    const target = try fs.readSymlink("link.txt", &buffer);
    try std.testing.expectEqualStrings("target.txt", target);
}

test "FileSystem: file operations" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var fs = FileSystem.init(allocator);

    var old_cwd = try std.fs.cwd().openDir(".", .{});
    defer old_cwd.close();
    try tmp_dir.dir.setAsCwd();
    defer old_cwd.setAsCwd() catch {};

    // Create file
    var file = try std.fs.cwd().createFile("test.txt", .{});
    try file.writeAll("Hello, World!");
    file.close();

    // Check existence
    try std.testing.expect(fs.exists("test.txt"));
    try std.testing.expect(!fs.exists("nonexistent.txt"));

    // Check type
    try std.testing.expect(fs.isFile("test.txt"));
    try std.testing.expect(!fs.isDirectory("test.txt"));

    // Get size
    const size = try fs.getFileSize("test.txt");
    try std.testing.expectEqual(@as(u64, 13), size);

    // Remove file
    try fs.removeFile("test.txt");
    try std.testing.expect(!fs.exists("test.txt"));
}

test "FileSystem: directory removal" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var fs = FileSystem.init(allocator);

    var old_cwd = try std.fs.cwd().openDir(".", .{});
    defer old_cwd.close();
    try tmp_dir.dir.setAsCwd();
    defer old_cwd.setAsCwd() catch {};

    // Create directory tree
    try fs.createDirAll("parent/child");
    var file = try std.fs.cwd().createFile("parent/child/file.txt", .{});
    file.close();

    // Remove tree
    try fs.removeDirAll("parent");
    try std.testing.expect(!fs.exists("parent"));
}

test "sanitizePath: valid paths" {
    const path1 = try sanitizePath("foo/bar/baz.txt", false);
    try std.testing.expectEqualStrings("foo/bar/baz.txt", path1);

    const path2 = try sanitizePath("./foo/bar", false);
    try std.testing.expectEqualStrings("./foo/bar", path2);
}

test "sanitizePath: invalid paths" {
    // Absolute path (not allowed)
    try std.testing.expectError(
        error.AbsolutePathNotAllowed,
        sanitizePath("/etc/passwd", false),
    );

    // Path traversal
    try std.testing.expectError(
        error.PathTraversalAttempt,
        sanitizePath("../../../etc/passwd", false),
    );

    try std.testing.expectError(
        error.PathTraversalAttempt,
        sanitizePath("foo/../../bar", false),
    );
}

test "joinPath and normalizePath" {
    const allocator = std.testing.allocator;

    const joined = try joinPath(allocator, &[_][]const u8{ "foo", "bar", "baz.txt" });
    defer allocator.free(joined);

    const normalized = try normalizePath(allocator, "foo/./bar/../baz.txt");
    defer allocator.free(normalized);

    // Use platform-specific path separator
    const expected = if (builtin.os.tag == .windows) "foo\\baz.txt" else "foo/baz.txt";
    try std.testing.expectEqualStrings(expected, normalized);
}

test "dirname and basename" {
    try std.testing.expectEqualStrings("foo/bar", dirname("foo/bar/baz.txt"));
    try std.testing.expectEqualStrings("baz.txt", basename("foo/bar/baz.txt"));

    try std.testing.expectEqualStrings(".", dirname("file.txt"));
    try std.testing.expectEqualStrings("file.txt", basename("file.txt"));
}
