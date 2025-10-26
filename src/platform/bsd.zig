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

/// BSD-specific platform implementation
///
/// This module implements platform-specific operations for BSD systems
/// (FreeBSD, OpenBSD, NetBSD) using POSIX system calls.
///
/// BSD systems support:
/// - Full POSIX permissions
/// - Extended attributes (FreeBSD)
/// - Symbolic links and hard links
/// - Case-sensitive filesystems
/// Platform implementation for BSD
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
    try std.fs.cwd().chmod(path, mode);
}

/// Get file permissions using POSIX stat
fn getFilePermissions(path: []const u8) !u32 {
    const stat = try std.fs.cwd().statFile(path);
    return @as(u32, @intCast(stat.mode & 0o7777));
}

/// Set file modification time using utimensat
fn setFileTime(path: []const u8, mtime: i64) !void {
    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_write });
    defer file.close();

    // Convert Unix timestamp to nanoseconds
    const atime_nsec: i128 = @as(i128, mtime) * std.time.ns_per_s;
    const mtime_nsec: i128 = @as(i128, mtime) * std.time.ns_per_s;

    try file.updateTimes(atime_nsec, mtime_nsec);
}

/// Create symbolic link using POSIX symlink
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
    const st = std.fs.cwd().lstat(path) catch return false;
    return st.kind == .sym_link;
}

/// Create hard link using POSIX link()
fn createHardLink(target: []const u8, link_path: []const u8) !void {
    var target_buf: [std.fs.max_path_bytes:0]u8 = undefined;
    const target_z = try std.fmt.bufPrintZ(&target_buf, "{s}", .{target});

    var link_buf: [std.fs.max_path_bytes:0]u8 = undefined;
    const link_z = try std.fmt.bufPrintZ(&link_buf, "{s}", .{link_path});

    try std.posix.link(target_z, link_z);
}

/// Get platform name (returns the specific BSD variant)
fn getPlatformName() []const u8 {
    return switch (@import("builtin").os.tag) {
        .freebsd => "FreeBSD",
        .openbsd => "OpenBSD",
        .netbsd => "NetBSD",
        else => "BSD",
    };
}

// Tests
test "BSD platform: set and get permissions" {
    const builtin = @import("builtin");
    if (builtin.os.tag != .freebsd and
        builtin.os.tag != .openbsd and
        builtin.os.tag != .netbsd)
    {
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
}

test "BSD platform: set and get file time" {
    const builtin = @import("builtin");
    if (builtin.os.tag != .freebsd and
        builtin.os.tag != .openbsd and
        builtin.os.tag != .netbsd)
    {
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

test "BSD platform: symlink operations" {
    const builtin = @import("builtin");
    if (builtin.os.tag != .freebsd and
        builtin.os.tag != .openbsd and
        builtin.os.tag != .netbsd)
    {
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
}

test "BSD platform: getPlatformName" {
    const name = getPlatformName();
    try std.testing.expect(name.len > 0);
}
