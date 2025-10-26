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
const builtin = @import("builtin");

/// Platform-specific operations interface
///
/// This module provides a unified interface for platform-specific operations
/// such as file permissions, timestamps, and symbolic links.
///
/// Each platform (Linux, Windows, macOS) implements this interface
/// with platform-specific system calls.
pub const Platform = struct {
    /// Set file permissions
    ///
    /// Parameters:
    ///   - path: File path
    ///   - mode: POSIX permissions (e.g., 0o644)
    ///
    /// Note: On Windows, this is approximated to read-only attribute
    setFilePermissions: *const fn (path: []const u8, mode: u32) anyerror!void,

    /// Get file permissions
    ///
    /// Parameters:
    ///   - path: File path
    ///
    /// Returns:
    ///   - POSIX permissions (e.g., 0o644)
    ///
    /// Note: On Windows, this is approximated from file attributes
    getFilePermissions: *const fn (path: []const u8) anyerror!u32,

    /// Set file modification time
    ///
    /// Parameters:
    ///   - path: File path
    ///   - mtime: Modification time (Unix timestamp in seconds)
    setFileTime: *const fn (path: []const u8, mtime: i64) anyerror!void,

    /// Create a symbolic link
    ///
    /// Parameters:
    ///   - target: Target path the link points to
    ///   - link_path: Path where the symlink will be created
    ///
    /// Note: On Windows, may require administrator privileges
    createSymlink: *const fn (target: []const u8, link_path: []const u8) anyerror!void,

    /// Read symbolic link target
    ///
    /// Parameters:
    ///   - allocator: Memory allocator
    ///   - link_path: Path to the symlink
    ///
    /// Returns:
    ///   - Target path (caller must free)
    readSymlink: *const fn (allocator: std.mem.Allocator, link_path: []const u8) anyerror![]u8,

    /// Check if path is a symbolic link
    ///
    /// Parameters:
    ///   - path: Path to check
    ///
    /// Returns:
    ///   - true if path is a symlink, false otherwise
    isSymlink: *const fn (path: []const u8) bool,

    /// Create a hard link
    ///
    /// Parameters:
    ///   - target: Existing file path
    ///   - link_path: Path where the hard link will be created
    ///
    /// Note: Both paths must be on the same filesystem
    createHardLink: *const fn (target: []const u8, link_path: []const u8) anyerror!void,

    /// Get platform name
    ///
    /// Returns:
    ///   - Platform name string (e.g., "Linux", "Windows", "macOS")
    getPlatformName: *const fn () []const u8,
};

/// Get the platform-specific implementation for the current OS
///
/// This function returns the appropriate Platform implementation
/// based on compile-time OS detection.
///
/// Returns:
///   - Platform implementation for the current OS
///
/// Note:
///   - Compile error if platform is not supported
pub fn getPlatform() Platform {
    return switch (builtin.os.tag) {
        .linux => @import("linux.zig").platform,
        .windows => @import("windows.zig").platform,
        .macos => @import("macos.zig").platform,
        .freebsd, .openbsd, .netbsd => @import("bsd.zig").platform,
        else => @compileError("Unsupported platform: " ++ @tagName(builtin.os.tag)),
    };
}

/// Check if current platform is Unix-like
///
/// Returns:
///   - true if running on Unix-like OS (Linux, macOS, BSD), false otherwise
pub fn isUnix() bool {
    return switch (builtin.os.tag) {
        .linux, .macos, .freebsd, .openbsd, .netbsd => true,
        else => false,
    };
}

/// Check if current platform is Windows
///
/// Returns:
///   - true if running on Windows, false otherwise
pub fn isWindows() bool {
    return builtin.os.tag == .windows;
}

/// Get platform name string
///
/// Returns:
///   - Platform name (e.g., "Linux", "Windows", "macOS")
pub fn getPlatformName() []const u8 {
    return switch (builtin.os.tag) {
        .linux => "Linux",
        .windows => "Windows",
        .macos => "macOS",
        .freebsd => "FreeBSD",
        .openbsd => "OpenBSD",
        .netbsd => "NetBSD",
        else => "Unknown",
    };
}

/// Platform capability flags
pub const Capabilities = struct {
    /// Supports POSIX file permissions
    supports_permissions: bool,
    /// Supports symbolic links (may require privileges)
    supports_symlinks: bool,
    /// Supports hard links
    supports_hardlinks: bool,
    /// Supports extended attributes
    supports_xattr: bool,
    /// Case-sensitive filesystem
    case_sensitive: bool,
};

/// Get platform capabilities
///
/// Returns:
///   - Capabilities structure for the current platform
pub fn getCapabilities() Capabilities {
    return switch (builtin.os.tag) {
        .linux => .{
            .supports_permissions = true,
            .supports_symlinks = true,
            .supports_hardlinks = true,
            .supports_xattr = true,
            .case_sensitive = true,
        },
        .windows => .{
            .supports_permissions = false,
            .supports_symlinks = true, // Requires privileges
            .supports_hardlinks = true,
            .supports_xattr = false,
            .case_sensitive = false,
        },
        .macos => .{
            .supports_permissions = true,
            .supports_symlinks = true,
            .supports_hardlinks = true,
            .supports_xattr = true,
            .case_sensitive = false, // APFS can be case-sensitive
        },
        .freebsd, .openbsd, .netbsd => .{
            .supports_permissions = true,
            .supports_symlinks = true,
            .supports_hardlinks = true,
            .supports_xattr = true,
            .case_sensitive = true,
        },
        else => .{
            .supports_permissions = false,
            .supports_symlinks = false,
            .supports_hardlinks = false,
            .supports_xattr = false,
            .case_sensitive = true,
        },
    };
}

// Tests
test "getPlatformName: returns valid name" {
    const name = getPlatformName();
    try std.testing.expect(name.len > 0);
}

test "isUnix and isWindows: mutually exclusive" {
    const is_unix = isUnix();
    const is_windows = isWindows();

    // Cannot be both Unix and Windows
    if (is_unix) {
        try std.testing.expect(!is_windows);
    }
    if (is_windows) {
        try std.testing.expect(!is_unix);
    }
}

test "getCapabilities: returns valid capabilities" {
    const caps = getCapabilities();

    // On Unix platforms, should support permissions
    if (isUnix()) {
        try std.testing.expect(caps.supports_permissions);
        try std.testing.expect(caps.supports_symlinks);
    }

    // On Windows, permissions are not fully supported
    if (isWindows()) {
        try std.testing.expect(!caps.supports_permissions);
    }
}
