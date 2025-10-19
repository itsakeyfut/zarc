const std = @import("std");
const builtin = @import("builtin");
const platform_common = @import("../../src/platform/common.zig");

/// Platform abstraction integration tests
///
/// These tests verify that the platform abstraction layer
/// correctly implements the common interface across different platforms.

test "Platform: getPlatform returns valid implementation" {
    const platform = platform_common.getPlatform();

    // Verify all function pointers are non-null
    try std.testing.expect(platform.setFilePermissions != null);
    try std.testing.expect(platform.getFilePermissions != null);
    try std.testing.expect(platform.setFileTime != null);
    try std.testing.expect(platform.createSymlink != null);
    try std.testing.expect(platform.readSymlink != null);
    try std.testing.expect(platform.isSymlink != null);
    try std.testing.expect(platform.getPlatformName != null);
}

test "Platform: getPlatformName returns correct name" {
    const platform = platform_common.getPlatform();
    const name = platform.getPlatformName();

    // Verify name is not empty
    try std.testing.expect(name.len > 0);

    // Verify it matches the expected platform
    switch (builtin.os.tag) {
        .linux => try std.testing.expectEqualStrings("Linux", name),
        .windows => try std.testing.expectEqualStrings("Windows", name),
        .macos => try std.testing.expectEqualStrings("macOS", name),
        .freebsd => try std.testing.expectEqualStrings("FreeBSD", name),
        .openbsd => try std.testing.expectEqualStrings("OpenBSD", name),
        .netbsd => try std.testing.expectEqualStrings("NetBSD", name),
        else => {}, // Allow other platforms
    }
}

test "Platform: file permissions" {
    if (builtin.os.tag == .windows) {
        // Skip detailed permission tests on Windows
        // Windows approximates POSIX permissions
        return error.SkipZigTest;
    }

    const platform = platform_common.getPlatform();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var old_cwd = try std.fs.cwd().openDir(".", .{});
    defer old_cwd.close();
    try tmp_dir.dir.setAsCwd();
    defer old_cwd.setAsCwd() catch {};

    // Create test file
    var file = try std.fs.cwd().createFile("test.txt", .{});
    file.close();

    // Test various permission modes
    const test_modes = [_]u32{
        0o644, // rw-r--r--
        0o755, // rwxr-xr-x
        0o600, // rw-------
        0o444, // r--r--r--
    };

    for (test_modes) |mode| {
        try platform.setFilePermissions("test.txt", mode);
        const retrieved_mode = try platform.getFilePermissions("test.txt");
        try std.testing.expectEqual(mode, retrieved_mode);
    }
}

test "Platform: file modification time" {
    const platform = platform_common.getPlatform();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var old_cwd = try std.fs.cwd().openDir(".", .{});
    defer old_cwd.close();
    try tmp_dir.dir.setAsCwd();
    defer old_cwd.setAsCwd() catch {};

    // Create test file
    var file = try std.fs.cwd().createFile("test.txt", .{});
    file.close();

    // Test various timestamps
    const test_times = [_]i64{
        1234567890, // 2009-02-13 23:31:30 UTC
        1609459200, // 2021-01-01 00:00:00 UTC
        1672531200, // 2023-01-01 00:00:00 UTC
    };

    for (test_times) |test_time| {
        try platform.setFileTime("test.txt", test_time);

        // Verify the time was set correctly
        const stat = try std.fs.cwd().statFile("test.txt");
        const mtime_sec = @divTrunc(stat.mtime, std.time.ns_per_s);

        // Allow small differences due to precision
        const diff = if (mtime_sec > test_time)
            mtime_sec - test_time
        else
            test_time - mtime_sec;

        try std.testing.expect(diff <= 1);
    }
}

test "Platform: symbolic links" {
    if (builtin.os.tag == .windows) {
        // Skip on Windows - symlinks require special privileges
        return error.SkipZigTest;
    }

    const platform = platform_common.getPlatform();
    const allocator = std.testing.allocator;

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
    try platform.createSymlink("target.txt", "link.txt");

    // Verify it's recognized as a symlink
    try std.testing.expect(platform.isSymlink("link.txt"));

    // Verify target is not a symlink
    try std.testing.expect(!platform.isSymlink("target.txt"));

    // Read symlink target
    const target = try platform.readSymlink(allocator, "link.txt");
    defer allocator.free(target);

    try std.testing.expectEqualStrings("target.txt", target);
}

test "Platform: symlink to directory" {
    if (builtin.os.tag == .windows) {
        return error.SkipZigTest;
    }

    const platform = platform_common.getPlatform();
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var old_cwd = try std.fs.cwd().openDir(".", .{});
    defer old_cwd.close();
    try tmp_dir.dir.setAsCwd();
    defer old_cwd.setAsCwd() catch {};

    // Create target directory
    try std.fs.cwd().makeDir("target_dir");

    // Create symlink to directory
    try platform.createSymlink("target_dir", "link_dir");

    // Verify it's a symlink
    try std.testing.expect(platform.isSymlink("link_dir"));

    // Read symlink target
    const target = try platform.readSymlink(allocator, "link_dir");
    defer allocator.free(target);

    try std.testing.expectEqualStrings("target_dir", target);
}

test "Platform: relative symlink paths" {
    if (builtin.os.tag == .windows) {
        return error.SkipZigTest;
    }

    const platform = platform_common.getPlatform();
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var old_cwd = try std.fs.cwd().openDir(".", .{});
    defer old_cwd.close();
    try tmp_dir.dir.setAsCwd();
    defer old_cwd.setAsCwd() catch {};

    // Create nested directory structure
    try std.fs.cwd().makePath("dir1/subdir");
    var file = try std.fs.cwd().createFile("dir1/target.txt", .{});
    file.close();

    // Change to subdirectory
    var dir1 = try std.fs.cwd().openDir("dir1/subdir", .{});
    defer dir1.close();
    try dir1.setAsCwd();

    // Create relative symlink
    try platform.createSymlink("../target.txt", "link.txt");

    // Verify symlink
    try std.testing.expect(platform.isSymlink("link.txt"));

    const target = try platform.readSymlink(allocator, "link.txt");
    defer allocator.free(target);

    try std.testing.expectEqualStrings("../target.txt", target);
}

test "Platform: capabilities check" {
    const caps = platform_common.getCapabilities();

    // On Unix platforms, should support permissions
    if (platform_common.isUnix()) {
        try std.testing.expect(caps.supports_permissions);
        try std.testing.expect(caps.supports_symlinks);
        try std.testing.expect(caps.supports_hardlinks);
        try std.testing.expect(caps.case_sensitive or !caps.case_sensitive); // Allow either
    }

    // On Windows, permissions are limited
    if (platform_common.isWindows()) {
        try std.testing.expect(!caps.supports_permissions);
        try std.testing.expect(!caps.case_sensitive);
    }
}

test "Platform: error handling - nonexistent file" {
    const platform = platform_common.getPlatform();

    // Attempt to get permissions of nonexistent file
    const result = platform.getFilePermissions("nonexistent_file_xyz.txt");
    try std.testing.expectError(error.FileNotFound, result);
}

test "Platform: error handling - symlink to nonexistent target" {
    if (builtin.os.tag == .windows) {
        return error.SkipZigTest;
    }

    const platform = platform_common.getPlatform();
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var old_cwd = try std.fs.cwd().openDir(".", .{});
    defer old_cwd.close();
    try tmp_dir.dir.setAsCwd();
    defer old_cwd.setAsCwd() catch {};

    // Create symlink to nonexistent target (this is valid)
    try platform.createSymlink("nonexistent_target.txt", "broken_link.txt");

    // Verify it's still recognized as a symlink
    try std.testing.expect(platform.isSymlink("broken_link.txt"));

    // Can still read the target path
    const target = try platform.readSymlink(allocator, "broken_link.txt");
    defer allocator.free(target);

    try std.testing.expectEqualStrings("nonexistent_target.txt", target);
}

test "Platform: helper functions" {
    // Test isUnix
    const is_unix = platform_common.isUnix();
    switch (builtin.os.tag) {
        .linux, .macos, .freebsd, .openbsd, .netbsd => {
            try std.testing.expect(is_unix);
        },
        .windows => {
            try std.testing.expect(!is_unix);
        },
        else => {},
    }

    // Test isWindows
    const is_windows = platform_common.isWindows();
    switch (builtin.os.tag) {
        .windows => try std.testing.expect(is_windows),
        else => try std.testing.expect(!is_windows),
    }

    // Verify they are mutually exclusive
    if (is_unix) {
        try std.testing.expect(!is_windows);
    }
    if (is_windows) {
        try std.testing.expect(!is_unix);
    }
}
