const std = @import("std");
const common = @import("common.zig");
const windows = std.os.windows;

/// Windows-specific platform implementation
///
/// This module implements platform-specific operations for Windows.
///
/// Note:
/// - POSIX permissions are approximated to Windows file attributes
/// - Read-only attribute is used to approximate write permissions
/// - Symbolic links may require administrator privileges on older Windows versions
/// Platform implementation for Windows
pub const platform = common.Platform{
    .setFilePermissions = setFilePermissions,
    .getFilePermissions = getFilePermissions,
    .setFileTime = setFileTime,
    .createSymlink = createSymlink,
    .readSymlink = readSymlink,
    .isSymlink = isSymlink,
    .getPlatformName = getPlatformName,
};

/// Set file permissions (approximated on Windows)
///
/// Windows doesn't have POSIX permissions, so we approximate:
/// - If mode allows write (0o200 bit), clear read-only attribute
/// - If mode doesn't allow write, set read-only attribute
fn setFilePermissions(path: []const u8, mode: u32) !void {
    const path_w = try std.unicode.utf8ToUtf16LeWithNull(
        std.heap.page_allocator,
        path,
    );
    defer std.heap.page_allocator.free(path_w);

    const attrs = try windows.GetFileAttributesW(path_w.ptr);

    // Check if write permission is set (owner write bit)
    const new_attrs = if ((mode & 0o200) != 0)
        // Write allowed - clear read-only
        attrs & ~@as(u32, windows.FILE_ATTRIBUTE_READONLY)
    else
        // Write not allowed - set read-only
        attrs | windows.FILE_ATTRIBUTE_READONLY;

    try windows.SetFileAttributesW(path_w.ptr, new_attrs);
}

/// Get file permissions (approximated from Windows attributes)
///
/// Returns:
/// - 0o444 (read-only) if FILE_ATTRIBUTE_READONLY is set
/// - 0o666 (read-write) otherwise
fn getFilePermissions(path: []const u8) !u32 {
    const path_w = try std.unicode.utf8ToUtf16LeWithNull(
        std.heap.page_allocator,
        path,
    );
    defer std.heap.page_allocator.free(path_w);

    const attrs = try windows.GetFileAttributesW(path_w.ptr);

    // Check if read-only attribute is set
    if ((attrs & windows.FILE_ATTRIBUTE_READONLY) != 0) {
        return 0o444; // Read-only for all
    } else {
        return 0o666; // Read-write for all
    }
}

/// Set file modification time using SetFileTime
fn setFileTime(path: []const u8, mtime: i64) !void {
    const path_w = try std.unicode.utf8ToUtf16LeWithNull(
        std.heap.page_allocator,
        path,
    );
    defer std.heap.page_allocator.free(path_w);

    const handle = try windows.CreateFileW(
        path_w.ptr,
        windows.FILE_WRITE_ATTRIBUTES,
        windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE,
        null,
        windows.OPEN_EXISTING,
        windows.FILE_ATTRIBUTE_NORMAL,
        null,
    );
    defer windows.CloseHandle(handle);

    // Convert Unix timestamp to Windows FILETIME
    // Windows FILETIME is 100-nanosecond intervals since 1601-01-01
    // Unix timestamp is seconds since 1970-01-01
    // Difference: 11644473600 seconds
    const windows_epoch_offset = 11644473600;
    const windows_time = (@as(i64, mtime) + windows_epoch_offset) * 10000000;

    var filetime: windows.FILETIME = undefined;
    filetime.dwLowDateTime = @as(u32, @truncate(@as(u64, @bitCast(windows_time))));
    filetime.dwHighDateTime = @as(u32, @truncate(@as(u64, @bitCast(windows_time)) >> 32));

    try windows.SetFileTime(handle, null, null, &filetime);
}

/// Create symbolic link using CreateSymbolicLinkW
///
/// Note: On Windows 10 and later with Developer Mode enabled,
/// symlinks can be created without administrator privileges
fn createSymlink(target: []const u8, link_path: []const u8) !void {
    const target_w = try std.unicode.utf8ToUtf16LeWithNull(
        std.heap.page_allocator,
        target,
    );
    defer std.heap.page_allocator.free(target_w);

    const link_w = try std.unicode.utf8ToUtf16LeWithNull(
        std.heap.page_allocator,
        link_path,
    );
    defer std.heap.page_allocator.free(link_w);

    try std.fs.cwd().symLink(target, link_path, .{});
}

/// Read symbolic link target
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

/// Check if path is a symbolic link
fn isSymlink(path: []const u8) bool {
    const path_w = std.unicode.utf8ToUtf16LeWithNull(
        std.heap.page_allocator,
        path,
    ) catch return false;
    defer std.heap.page_allocator.free(path_w);

    const attrs = windows.GetFileAttributesW(path_w.ptr) catch return false;

    // Check if FILE_ATTRIBUTE_REPARSE_POINT is set
    if ((attrs & windows.FILE_ATTRIBUTE_REPARSE_POINT) == 0) {
        return false;
    }

    // Open file to get reparse tag
    const handle = windows.CreateFileW(
        path_w.ptr,
        windows.FILE_READ_ATTRIBUTES,
        windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE | windows.FILE_SHARE_DELETE,
        null,
        windows.OPEN_EXISTING,
        windows.FILE_FLAG_BACKUP_SEMANTICS | windows.FILE_FLAG_OPEN_REPARSE_POINT,
        null,
    ) catch return false;
    defer windows.CloseHandle(handle);

    // Check reparse tag to distinguish symlink from other reparse points
    // This is a simplified check - a full implementation would query the reparse data
    return true;
}

/// Get platform name
fn getPlatformName() []const u8 {
    return "Windows";
}

// Tests
test "Windows platform: set and get permissions" {
    if (@import("builtin").os.tag != .windows) {
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

    // Set read-write permissions
    try setFilePermissions("test.txt", 0o666);
    var mode = try getFilePermissions("test.txt");
    try std.testing.expectEqual(@as(u32, 0o666), mode);

    // Set read-only permissions
    try setFilePermissions("test.txt", 0o444);
    mode = try getFilePermissions("test.txt");
    try std.testing.expectEqual(@as(u32, 0o444), mode);
}

test "Windows platform: set and get file time" {
    if (@import("builtin").os.tag != .windows) {
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

    // Allow 1 second difference due to precision
    const diff = if (mtime_sec > target_time)
        mtime_sec - target_time
    else
        target_time - mtime_sec;
    try std.testing.expect(diff <= 1);
}

test "Windows platform: getPlatformName" {
    const name = getPlatformName();
    try std.testing.expectEqualStrings("Windows", name);
}
