const std = @import("std");
const errors = @import("../core/errors.zig");
const types = @import("../core/types.zig");

/// Security policy for archive extraction
///
/// Controls various security aspects of archive extraction to prevent
/// common attacks like path traversal, zip bombs, and symlink attacks.
///
/// Default values are chosen to be secure by default - users must
/// explicitly opt-in to potentially dangerous operations.
pub const SecurityPolicy = struct {
    /// Allow extraction of entries with absolute paths
    /// Default: false (reject absolute paths for security)
    allow_absolute_paths: bool = false,

    /// Allow symlinks that point outside the extraction directory
    /// Default: false (prevent symlink escape attacks)
    allow_symlink_escape: bool = false,

    /// Allow paths with ".." components that could escape extraction directory
    /// Default: false (prevent path traversal attacks)
    allow_path_traversal: bool = false,

    /// Maximum size for a single file in bytes
    /// Default: 10GB
    max_file_size: u64 = 10 * 1024 * 1024 * 1024,

    /// Maximum total uncompressed size for entire archive
    /// Default: 100GB
    max_total_size: u64 = 100 * 1024 * 1024 * 1024,

    /// Maximum compression ratio (uncompressed:compressed)
    /// Default: 1000:1 (helps detect zip bombs)
    max_compression_ratio: f64 = 1000.0,

    /// Verify checksums when available
    /// Default: true (ensure data integrity)
    verify_checksums: bool = true,

    /// Preserve file permissions from archive
    /// Default: false (safer to use default permissions)
    preserve_permissions: bool = false,

    /// Policy for handling symlinks
    /// Default: disallow (safest option)
    symlink_policy: SymlinkPolicy = .disallow,
};

/// Policy for handling symbolic links during extraction
pub const SymlinkPolicy = enum {
    /// Disallow all symlinks (safest)
    disallow,

    /// Allow only relative symlinks that stay within extraction directory
    only_relative,

    /// Allow all symlinks (dangerous)
    allow_all,
};

/// Sanitize and validate a path for safe extraction
///
/// Checks for various path-based attacks:
/// - Absolute paths (unless explicitly allowed)
/// - Path traversal attempts (..)
/// - NULL bytes in path
/// - Control characters
/// - Overly long paths
///
/// Parameters:
///   - path: Path to validate
///   - policy: Security policy to apply
///
/// Returns:
///   - The validated path (same as input if valid)
///
/// Errors:
///   - error.EmptyPath: Path is empty
///   - error.NullByteInPath: Path contains NULL byte
///   - error.AbsolutePathNotAllowed: Path is absolute
///   - error.PathTraversalAttempt: Path contains ".." that escapes directory
///   - error.InvalidCharacterInPath: Path contains invalid control characters
///   - error.PathTooLong: Path exceeds maximum length
pub fn sanitizePath(path: []const u8, policy: SecurityPolicy) ![]const u8 {
    // Empty path check
    if (path.len == 0) {
        return error.EmptyPath;
    }

    // NULL byte check (C string terminator - security issue)
    if (std.mem.indexOfScalar(u8, path, 0) != null) {
        std.log.warn("Path contains NULL byte: {s}", .{path});
        return error.NullByteInPath;
    }

    // Path length check
    if (path.len > types.SizeLimit.max_path_length) {
        std.log.warn("Path too long ({d} > {d}): {s}", .{
            path.len,
            types.SizeLimit.max_path_length,
            path,
        });
        return error.PathTooLong;
    }

    // Absolute path check
    if (!policy.allow_absolute_paths) {
        if (std.fs.path.isAbsolute(path)) {
            std.log.warn("Absolute path not allowed: {s}", .{path});
            return error.AbsolutePathNotAllowed;
        }

        // Windows drive letter check (C:\, D:\, etc.)
        if (path.len >= 2 and path[1] == ':') {
            const drive_letter = path[0];
            if ((drive_letter >= 'A' and drive_letter <= 'Z') or
                (drive_letter >= 'a' and drive_letter <= 'z'))
            {
                std.log.warn("Windows absolute path not allowed: {s}", .{path});
                return error.AbsolutePathNotAllowed;
            }
        }
    }

    // Path traversal check
    if (!policy.allow_path_traversal) {
        var depth: i32 = 0;
        var it = std.mem.splitAny(u8, path, "/\\");

        while (it.next()) |component| {
            if (std.mem.eql(u8, component, "..")) {
                depth -= 1;
                if (depth < 0) {
                    std.log.warn("Path traversal attempt detected: {s}", .{path});
                    return error.PathTraversalAttempt;
                }
            } else if (!std.mem.eql(u8, component, ".") and component.len > 0) {
                depth += 1;
            }
        }
    }

    // Control character check (except tab which is sometimes legitimate)
    for (path) |c| {
        if (c < 0x20 and c != '\t') {
            std.log.warn("Invalid control character in path: 0x{x}", .{c});
            return error.InvalidCharacterInPath;
        }
    }

    return path;
}

/// Check for potential zip bomb based on compression ratio
///
/// A zip bomb is a maliciously crafted archive that has a very small
/// compressed size but expands to an enormous size when decompressed.
///
/// Parameters:
///   - compressed_size: Size of compressed data
///   - uncompressed_size: Size after decompression
///   - policy: Security policy with limits
///
/// Errors:
///   - error.FileSizeExceedsLimit: Uncompressed size exceeds policy limit
///   - error.SuspiciousCompressionRatio: Compression ratio exceeds policy limit
pub fn checkZipBomb(
    compressed_size: u64,
    uncompressed_size: u64,
    policy: SecurityPolicy,
) !void {
    // Check absolute uncompressed size
    if (uncompressed_size > policy.max_file_size) {
        std.log.warn(
            "File size {d} exceeds limit {d}",
            .{ uncompressed_size, policy.max_file_size },
        );
        return error.FileSizeExceedsLimit;
    }

    // Check compression ratio (only if compressed_size > 0)
    if (compressed_size > 0) {
        const ratio = @as(f64, @floatFromInt(uncompressed_size)) /
            @as(f64, @floatFromInt(compressed_size));

        if (ratio > policy.max_compression_ratio) {
            std.log.warn(
                "Suspicious compression ratio: {d:.2}:1 (limit: {d:.2}:1)",
                .{ ratio, policy.max_compression_ratio },
            );
            return error.SuspiciousCompressionRatio;
        }
    }
}

/// Tracker for cumulative extraction metrics
///
/// Tracks total uncompressed size across all extracted files to prevent
/// archive-wide zip bombs (multiple small files that add up to huge size).
pub const ExtractionTracker = struct {
    /// Total uncompressed bytes extracted so far
    total_uncompressed: u64 = 0,

    /// Maximum total size allowed
    max_total_size: u64,

    /// Number of files extracted
    file_count: usize = 0,

    /// Initialize extraction tracker
    ///
    /// Parameters:
    ///   - policy: Security policy to get limits from
    ///
    /// Returns:
    ///   - New extraction tracker
    pub fn init(policy: SecurityPolicy) ExtractionTracker {
        return .{
            .max_total_size = policy.max_total_size,
        };
    }

    /// Add a file to the tracker and check limits
    ///
    /// Parameters:
    ///   - self: Tracker instance
    ///   - size: Size of file being extracted
    ///
    /// Errors:
    ///   - error.TotalSizeExceedsLimit: Total extracted size exceeds limit
    pub fn addFile(self: *ExtractionTracker, size: u64) !void {
        // Check for integer overflow
        const new_total = @addWithOverflow(self.total_uncompressed, size);
        if (new_total[1] != 0) {
            std.log.err("Integer overflow in total size calculation", .{});
            return error.TotalSizeExceedsLimit;
        }

        self.total_uncompressed = new_total[0];
        self.file_count += 1;

        if (self.total_uncompressed > self.max_total_size) {
            std.log.warn(
                "Total extracted size {d} exceeds limit {d} after {d} files",
                .{ self.total_uncompressed, self.max_total_size, self.file_count },
            );
            return error.TotalSizeExceedsLimit;
        }
    }
};

/// Validate a symlink for safe extraction
///
/// Checks that symlink target doesn't escape the extraction directory
/// when the policy requires it.
///
/// Parameters:
///   - allocator: Memory allocator
///   - link_path: Path of the symlink being created
///   - target: Target path the symlink points to
///   - dest_dir: Base extraction directory
///   - policy: Security policy to apply
///
/// Errors:
///   - error.SymlinkNotAllowed: Symlinks are disallowed by policy
///   - error.AbsoluteSymlinkNotAllowed: Absolute symlink not allowed
///   - error.SymlinkEscapeAttempt: Symlink points outside extraction directory
pub fn validateSymlink(
    allocator: std.mem.Allocator,
    link_path: []const u8,
    target: []const u8,
    dest_dir: []const u8,
    policy: SecurityPolicy,
) !void {
    switch (policy.symlink_policy) {
        .disallow => {
            std.log.warn("Symlink not allowed: {s} -> {s}", .{ link_path, target });
            return error.SymlinkNotAllowed;
        },

        .only_relative => {
            // Reject absolute paths
            if (std.fs.path.isAbsolute(target)) {
                std.log.warn("Absolute symlink not allowed: {s} -> {s}", .{
                    link_path,
                    target,
                });
                return error.AbsoluteSymlinkNotAllowed;
            }

            // Check if resolved symlink target stays within dest_dir
            const link_dir = std.fs.path.dirname(link_path) orelse ".";

            // Build the full path: dest_dir/link_dir/target
            const parts = [_][]const u8{ dest_dir, link_dir, target };
            const resolved_target = try std.fs.path.resolve(allocator, &parts);
            defer allocator.free(resolved_target);

            // Normalize dest_dir for comparison
            const normalized_dest = try std.fs.path.resolve(allocator, &[_][]const u8{dest_dir});
            defer allocator.free(normalized_dest);

            // Check if resolved target is under normalized_dest
            if (!std.mem.startsWith(u8, resolved_target, normalized_dest)) {
                std.log.warn("Symlink escape attempt: {s} -> {s} (resolves to {s})", .{
                    link_path,
                    target,
                    resolved_target,
                });
                return error.SymlinkEscapeAttempt;
            }
        },

        .allow_all => {
            // Allow any symlink (dangerous)
        },
    }
}

/// Normalize a filename by removing or replacing dangerous characters
///
/// This function handles:
/// - Unicode normalization (future: NFC normalization)
/// - Dangerous character replacement
/// - NULL byte detection
///
/// Parameters:
///   - allocator: Memory allocator
///   - filename: Original filename
///
/// Returns:
///   - Normalized filename (caller must free)
///
/// Errors:
///   - error.NullByteInFilename: Filename contains NULL byte
///   - error.OutOfMemory: Failed to allocate memory
pub fn normalizeFilename(
    allocator: std.mem.Allocator,
    filename: []const u8,
) ![]u8 {
    // Allocate new buffer
    const normalized = try allocator.alloc(u8, filename.len);
    errdefer allocator.free(normalized);

    // Process each character
    for (filename, 0..) |c, i| {
        normalized[i] = switch (c) {
            0 => return error.NullByteInFilename,
            '\n', '\r' => '_', // Replace newlines with underscore
            else => c,
        };
    }

    // TODO: Add Unicode NFC normalization when library is available
    // This prevents attacks using different Unicode representations
    // of the same filename (e.g., é vs é)

    return normalized;
}

// Tests
test "SecurityPolicy: default values are secure" {
    const policy = SecurityPolicy{};

    try std.testing.expectEqual(false, policy.allow_absolute_paths);
    try std.testing.expectEqual(false, policy.allow_symlink_escape);
    try std.testing.expectEqual(false, policy.allow_path_traversal);
    try std.testing.expectEqual(true, policy.verify_checksums);
    try std.testing.expectEqual(false, policy.preserve_permissions);
    try std.testing.expectEqual(SymlinkPolicy.disallow, policy.symlink_policy);
}

test "sanitizePath: valid relative paths" {
    const policy = SecurityPolicy{};

    _ = try sanitizePath("file.txt", policy);
    _ = try sanitizePath("dir/file.txt", policy);
    _ = try sanitizePath("a/b/c/file.txt", policy);
    _ = try sanitizePath("./file.txt", policy);
}

test "sanitizePath: reject empty path" {
    const policy = SecurityPolicy{};
    try std.testing.expectError(error.EmptyPath, sanitizePath("", policy));
}

test "sanitizePath: reject NULL byte" {
    const policy = SecurityPolicy{};
    const path = "file\x00.txt";
    try std.testing.expectError(error.NullByteInPath, sanitizePath(path, policy));
}

test "sanitizePath: reject absolute paths by default" {
    const policy = SecurityPolicy{};

    try std.testing.expectError(error.AbsolutePathNotAllowed, sanitizePath("/etc/passwd", policy));
    try std.testing.expectError(error.AbsolutePathNotAllowed, sanitizePath("/absolute/path", policy));
}

test "sanitizePath: allow absolute paths with policy" {
    const policy = SecurityPolicy{ .allow_absolute_paths = true };

    _ = try sanitizePath("/etc/passwd", policy);
    _ = try sanitizePath("/absolute/path", policy);
}

test "sanitizePath: reject Windows absolute paths" {
    const policy = SecurityPolicy{};

    try std.testing.expectError(error.AbsolutePathNotAllowed, sanitizePath("C:\\Windows\\System32", policy));
    try std.testing.expectError(error.AbsolutePathNotAllowed, sanitizePath("D:\\path", policy));
}

test "sanitizePath: detect path traversal" {
    const policy = SecurityPolicy{};

    try std.testing.expectError(error.PathTraversalAttempt, sanitizePath("../etc/passwd", policy));
    try std.testing.expectError(error.PathTraversalAttempt, sanitizePath("../../..", policy));
    try std.testing.expectError(error.PathTraversalAttempt, sanitizePath("foo/../../../etc/shadow", policy));
    try std.testing.expectError(error.PathTraversalAttempt, sanitizePath("..\\..\\windows", policy));
}

test "sanitizePath: allow path traversal with policy" {
    const policy = SecurityPolicy{ .allow_path_traversal = true };

    _ = try sanitizePath("../etc/passwd", policy);
    _ = try sanitizePath("foo/../../../bar", policy);
}

test "sanitizePath: allow safe .. usage" {
    const policy = SecurityPolicy{};

    // These don't actually escape the extraction directory
    _ = try sanitizePath("a/b/../c/file.txt", policy);
    _ = try sanitizePath("dir/./file.txt", policy);
}

test "sanitizePath: reject control characters" {
    const policy = SecurityPolicy{};

    try std.testing.expectError(error.InvalidCharacterInPath, sanitizePath("file\nname.txt", policy));
    try std.testing.expectError(error.InvalidCharacterInPath, sanitizePath("file\rname.txt", policy));

    // Tab should be allowed
    _ = try sanitizePath("file\tname.txt", policy);
}

test "sanitizePath: reject overly long paths" {
    const policy = SecurityPolicy{};
    const allocator = std.testing.allocator;

    // Create a path longer than SizeLimit.max_path_length
    const long_path = try allocator.alloc(u8, types.SizeLimit.max_path_length + 1);
    defer allocator.free(long_path);
    @memset(long_path, 'a');

    try std.testing.expectError(error.PathTooLong, sanitizePath(long_path, policy));
}

test "checkZipBomb: normal files pass" {
    const policy = SecurityPolicy{};

    // Normal compression ratios
    try checkZipBomb(1000, 10000, policy); // 10:1
    try checkZipBomb(1024, 2048, policy); // 2:1
    try checkZipBomb(1000000, 5000000, policy); // 5:1
}

test "checkZipBomb: detect excessive compression ratio" {
    const policy = SecurityPolicy{};

    // Suspicious compression ratio (> 1000:1)
    try std.testing.expectError(
        error.SuspiciousCompressionRatio,
        checkZipBomb(1000, 10000000, policy),
    );
}

test "checkZipBomb: detect file size limit" {
    const policy = SecurityPolicy{ .max_file_size = 1024 * 1024 }; // 1MB limit

    try std.testing.expectError(
        error.FileSizeExceedsLimit,
        checkZipBomb(1000, 2 * 1024 * 1024, policy), // 2MB file
    );
}

test "checkZipBomb: zero compressed size is safe" {
    const policy = SecurityPolicy{};

    // Stored (uncompressed) files have compressed_size = uncompressed_size or 0
    try checkZipBomb(0, 1000, policy);
}

test "ExtractionTracker: track cumulative size" {
    const policy = SecurityPolicy{ .max_total_size = 10000 };
    var tracker = ExtractionTracker.init(policy);

    try tracker.addFile(1000);
    try std.testing.expectEqual(@as(u64, 1000), tracker.total_uncompressed);
    try std.testing.expectEqual(@as(usize, 1), tracker.file_count);

    try tracker.addFile(2000);
    try std.testing.expectEqual(@as(u64, 3000), tracker.total_uncompressed);
    try std.testing.expectEqual(@as(usize, 2), tracker.file_count);

    try tracker.addFile(5000);
    try std.testing.expectEqual(@as(u64, 8000), tracker.total_uncompressed);
    try std.testing.expectEqual(@as(usize, 3), tracker.file_count);
}

test "ExtractionTracker: detect total size limit" {
    const policy = SecurityPolicy{ .max_total_size = 10000 };
    var tracker = ExtractionTracker.init(policy);

    try tracker.addFile(5000);
    try tracker.addFile(4000);

    // This should exceed the limit
    try std.testing.expectError(
        error.TotalSizeExceedsLimit,
        tracker.addFile(2000),
    );
}

test "validateSymlink: disallow policy" {
    const allocator = std.testing.allocator;
    const policy = SecurityPolicy{ .symlink_policy = .disallow };

    try std.testing.expectError(
        error.SymlinkNotAllowed,
        validateSymlink(allocator, "link", "target", "/dest", policy),
    );
}

test "validateSymlink: only_relative policy allows safe links" {
    const allocator = std.testing.allocator;
    const policy = SecurityPolicy{ .symlink_policy = .only_relative };

    // These should be allowed (relative links within directory)
    try validateSymlink(allocator, "link", "target", "/tmp", policy);
    try validateSymlink(allocator, "a/link", "../target", "/tmp", policy);
}

test "validateSymlink: only_relative rejects absolute links" {
    const allocator = std.testing.allocator;
    const policy = SecurityPolicy{ .symlink_policy = .only_relative };

    try std.testing.expectError(
        error.AbsoluteSymlinkNotAllowed,
        validateSymlink(allocator, "link", "/etc/passwd", "/tmp", policy),
    );
}

test "validateSymlink: only_relative detects escape attempts" {
    const allocator = std.testing.allocator;
    const policy = SecurityPolicy{ .symlink_policy = .only_relative };

    // These would escape the extraction directory
    try std.testing.expectError(
        error.SymlinkEscapeAttempt,
        validateSymlink(allocator, "link", "../../../../etc/passwd", "/tmp/extract", policy),
    );
}

test "normalizeFilename: basic normalization" {
    const allocator = std.testing.allocator;

    const result1 = try normalizeFilename(allocator, "normal_file.txt");
    defer allocator.free(result1);
    try std.testing.expectEqualStrings("normal_file.txt", result1);

    const result2 = try normalizeFilename(allocator, "file\nwith\nnewlines.txt");
    defer allocator.free(result2);
    try std.testing.expectEqualStrings("file_with_newlines.txt", result2);
}

test "normalizeFilename: reject NULL byte" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(
        error.NullByteInFilename,
        normalizeFilename(allocator, "file\x00.txt"),
    );
}
