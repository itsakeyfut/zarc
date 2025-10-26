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
const common = @import("common.zig");

/// macOS-specific platform implementation
///
/// This module implements platform-specific operations for macOS
/// using POSIX system calls and macOS-specific APIs.
///
/// macOS supports:
/// - Full POSIX permissions
/// - Extended attributes (xattr)
/// - Symbolic links and hard links
/// - Case-insensitive (default) or case-sensitive filesystems
/// Platform implementation for macOS
pub const platform = common.Platform{
    .setFilePermissions = setFilePermissions,
    .getFilePermissions = getFilePermissions,
    .setFileTime = setFileTime,
    .createSymlink = createSymlink,
    .readSymlink = readSymlink,
    .isSymlink = isSymlink,
    .createHardLink = createHardLink,
    .getPlatformName = getPlatformName,
};

/// Set file permissions using POSIX chmod
fn setFilePermissions(path: []const u8, mode: u32) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    try file.chmod(@as(u16, @intCast(mode & 0o7777)));
}

/// Get file permissions using POSIX stat
fn getFilePermissions(path: []const u8) !u32 {
    const stat = try std.fs.cwd().statFile(path);
    return @as(u32, @intCast(stat.mode & 0o7777));
}

/// Set file modification time
///
/// macOS supports nanosecond precision for file times
fn setFileTime(path: []const u8, mtime: i64) !void {
    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_write });
    defer file.close();

    // Convert Unix timestamp to nanoseconds
    const atime_nsec: i128 = @as(i128, mtime) * std.time.ns_per_s;
    const mtime_nsec: i128 = @as(i128, mtime) * std.time.ns_per_s;

    try file.updateTimes(atime_nsec, mtime_nsec);
}

/// Create symbolic link using POSIX symlink
///
/// macOS supports symbolic links without special privileges
fn createSymlink(target: []const u8, link_path: []const u8) !void {
    try std.fs.cwd().symLink(target, link_path, .{});
}

/// Read symbolic link target using POSIX readlink
fn readSymlink(allocator: std.mem.Allocator, link_path: []const u8) ![]u8 {
    var buffer = try allocator.alloc(u8, std.fs.max_path_bytes);
    errdefer allocator.free(buffer);

    const result = try std.fs.cwd().readLink(link_path, buffer);

    // Resize buffer to actual length
    if (result.len < buffer.len) {
        buffer = try allocator.realloc(buffer, result.len);
    }

    return buffer;
}

/// Check if path is a symbolic link using lstat
fn isSymlink(path: []const u8) bool {
    const stat = std.posix.fstatat(
        std.posix.AT.FDCWD,
        path,
        std.posix.AT.SYMLINK_NOFOLLOW,
    ) catch return false;
    return std.posix.S.ISLNK(stat.mode);
}

/// Create hard link using POSIX link()
fn createHardLink(target: []const u8, link_path: []const u8) !void {
    var target_buf: [std.fs.max_path_bytes:0]u8 = undefined;
    const target_z = try std.fmt.bufPrintZ(&target_buf, "{s}", .{target});

    var link_buf: [std.fs.max_path_bytes:0]u8 = undefined;
    const link_z = try std.fmt.bufPrintZ(&link_buf, "{s}", .{link_path});

    try std.posix.link(target_z, link_z);
}

/// Get platform name
fn getPlatformName() []const u8 {
    return "macOS";
}

/// Extended attributes support (macOS-specific)
///
/// macOS supports extended attributes (xattr) for storing additional metadata.
/// This is commonly used for:
/// - Quarantine attributes (downloaded files)
/// - Resource forks
/// - Finder information
pub const ExtendedAttributes = struct {
    /// Set extended attribute
    ///
    /// Parameters:
    ///   - path: File path
    ///   - name: Attribute name (e.g., "com.apple.quarantine")
    ///   - value: Attribute value
    pub fn set(path: []const u8, name: []const u8, value: []const u8) !void {
        _ = path;
        _ = name;
        _ = value;
        // Implementation would use setxattr system call
        // For now, this is a placeholder
        return error.NotImplemented;
    }

    /// Get extended attribute
    ///
    /// Parameters:
    ///   - allocator: Memory allocator
    ///   - path: File path
    ///   - name: Attribute name
    ///
    /// Returns:
    ///   - Attribute value (caller must free)
    pub fn get(allocator: std.mem.Allocator, path: []const u8, name: []const u8) ![]u8 {
        _ = allocator;
        _ = path;
        _ = name;
        // Implementation would use getxattr system call
        // For now, this is a placeholder
        return error.NotImplemented;
    }

    /// List all extended attribute names
    ///
    /// Parameters:
    ///   - allocator: Memory allocator
    ///   - path: File path
    ///
    /// Returns:
    ///   - Array of attribute names (caller must free)
    pub fn list(allocator: std.mem.Allocator, path: []const u8) ![][]const u8 {
        _ = allocator;
        _ = path;
        // Implementation would use listxattr system call
        // For now, this is a placeholder
        return error.NotImplemented;
    }

    /// Remove extended attribute
    ///
    /// Parameters:
    ///   - path: File path
    ///   - name: Attribute name
    pub fn remove(path: []const u8, name: []const u8) !void {
        _ = path;
        _ = name;
        // Implementation would use removexattr system call
        // For now, this is a placeholder
        return error.NotImplemented;
    }
};

// Tests
test "macOS platform: set and get permissions" {
    if (@import("builtin").os.tag != .macos) {
        return error.SkipZigTest;
    }

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var old_cwd = try std.fs.cwd().openDir(".", .{});
    defer old_cwd.close();
    try tmp_dir.dir.setAsCwd();
    defer old_cwd.setAsCwd() catch {};

    // Create test file
    var file = try std.fs.cwd().createFile("test.txt", .{});
    file.close();

    // Set permissions
    try setFilePermissions("test.txt", 0o644);

    // Get permissions
    const mode = try getFilePermissions("test.txt");
    try std.testing.expectEqual(@as(u32, 0o644), mode);

    // Test different permissions
    try setFilePermissions("test.txt", 0o755);
    const mode2 = try getFilePermissions("test.txt");
    try std.testing.expectEqual(@as(u32, 0o755), mode2);
}

test "macOS platform: set and get file time" {
    if (@import("builtin").os.tag != .macos) {
        return error.SkipZigTest;
    }

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var old_cwd = try std.fs.cwd().openDir(".", .{});
    defer old_cwd.close();
    try tmp_dir.dir.setAsCwd();
    defer old_cwd.setAsCwd() catch {};

    // Create test file
    var file = try std.fs.cwd().createFile("test.txt", .{});
    file.close();

    // Set modification time
    const target_time: i64 = 1234567890;
    try setFileTime("test.txt", target_time);

    // Verify modification time
    const stat = try std.fs.cwd().statFile("test.txt");
    const mtime_sec = @divTrunc(stat.mtime, std.time.ns_per_s);
    try std.testing.expectEqual(target_time, mtime_sec);
}

test "macOS platform: symlink operations" {
    if (@import("builtin").os.tag != .macos) {
        return error.SkipZigTest;
    }

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var old_cwd = try std.fs.cwd().openDir(".", .{});
    defer old_cwd.close();
    try tmp_dir.dir.setAsCwd();
    defer old_cwd.setAsCwd() catch {};

    // Create target file
    var file = try std.fs.cwd().createFile("target.txt", .{});
    file.close();

    // Create symlink
    try createSymlink("target.txt", "link.txt");

    // Check if it's a symlink
    try std.testing.expect(isSymlink("link.txt"));

    // Read symlink target
    const allocator = std.testing.allocator;
    const target = try readSymlink(allocator, "link.txt");
    defer allocator.free(target);

    try std.testing.expectEqualStrings("target.txt", target);

    // Check that target file is not a symlink
    try std.testing.expect(!isSymlink("target.txt"));
}

test "macOS platform: getPlatformName" {
    const name = getPlatformName();
    try std.testing.expectEqualStrings("macOS", name);
}
