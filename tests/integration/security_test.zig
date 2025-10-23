const std = @import("std");
const zarc = @import("zarc");
const security = zarc.app.security;
const types = zarc.core.types;

// Integration tests for security checks
// Verifies that the security layer protects against various attacks

// ============================================================================
// Path Sanitization Tests
// ============================================================================

test "sanitizePath: allows safe relative paths" {
    // Arrange
    const policy = security.SecurityPolicy{};

    const safe_paths = [_][]const u8{
        "file.txt",
        "dir/file.txt",
        "a/b/c/d/file.txt",
        "./file.txt",
        "dir/../other_dir/file.txt", // Safe because depth never goes negative
    };

    // Act & Assert
    for (safe_paths) |path| {
        const result = try security.sanitizePath(path, policy);
        try std.testing.expectEqualStrings(path, result);
    }
}

test "sanitizePath: rejects dangerous paths" {
    // Arrange
    const policy = security.SecurityPolicy{};

    const dangerous_paths = [_]struct {
        path: []const u8,
        expected_error: anyerror,
    }{
        .{ .path = "", .expected_error = error.EmptyPath },
        .{ .path = "file\x00.txt", .expected_error = error.NullByteInPath },
        .{ .path = "/etc/passwd", .expected_error = error.AbsolutePathNotAllowed },
        .{ .path = "C:\\Windows\\System32", .expected_error = error.AbsolutePathNotAllowed },
        .{ .path = "\\\\server\\share", .expected_error = error.AbsolutePathNotAllowed },
        .{ .path = "../../../etc/passwd", .expected_error = error.PathTraversalAttempt },
        .{ .path = "foo/../../../bar", .expected_error = error.PathTraversalAttempt },
        .{ .path = "file\nname.txt", .expected_error = error.InvalidCharacterInPath },
        .{ .path = "file\rname.txt", .expected_error = error.InvalidCharacterInPath },
    };

    // Act & Assert
    for (dangerous_paths) |tc| {
        const result = security.sanitizePath(tc.path, policy);
        try std.testing.expectError(tc.expected_error, result);
    }
}

test "sanitizePath: policy allows absolute paths" {
    // Arrange
    const policy = security.SecurityPolicy{
        .allow_absolute_paths = true,
    };

    // Act & Assert
    _ = try security.sanitizePath("/etc/passwd", policy);
    _ = try security.sanitizePath("/absolute/path", policy);
}

test "sanitizePath: policy allows path traversal" {
    // Arrange
    const policy = security.SecurityPolicy{
        .allow_path_traversal = true,
    };

    // Act & Assert
    _ = try security.sanitizePath("../../../etc/passwd", policy);
    _ = try security.sanitizePath("foo/../../../bar", policy);
}

test "sanitizePath: rejects overly long paths" {
    // Arrange
    const policy = security.SecurityPolicy{};
    const allocator = std.testing.allocator;

    const long_path = try allocator.alloc(u8, types.SizeLimit.max_path_length + 1);
    defer allocator.free(long_path);
    @memset(long_path, 'a');

    // Act & Assert
    try std.testing.expectError(error.PathTooLong, security.sanitizePath(long_path, policy));
}

// ============================================================================
// Zip Bomb Detection Tests
// ============================================================================

test "checkZipBomb: allows normal compression ratios" {
    // Arrange
    const policy = security.SecurityPolicy{};

    const test_cases = [_]struct {
        compressed: u64,
        uncompressed: u64,
    }{
        .{ .compressed = 1000, .uncompressed = 2000 }, // 2:1
        .{ .compressed = 1000, .uncompressed = 10000 }, // 10:1
        .{ .compressed = 1024 * 1024, .uncompressed = 5 * 1024 * 1024 }, // 5:1
        .{ .compressed = 100000, .uncompressed = 500000 }, // 5:1
    };

    // Act & Assert
    for (test_cases) |tc| {
        try security.checkZipBomb(tc.compressed, tc.uncompressed, policy);
    }
}

test "checkZipBomb: detects suspicious compression ratio" {
    // Arrange
    const policy = security.SecurityPolicy{
        .max_compression_ratio = 1000.0,
    };

    // Act & Assert - 10000:1 ratio exceeds limit
    try std.testing.expectError(
        error.SuspiciousCompressionRatio,
        security.checkZipBomb(1000, 10_000_000, policy),
    );

    // 2000:1 ratio exceeds limit
    try std.testing.expectError(
        error.SuspiciousCompressionRatio,
        security.checkZipBomb(1000, 2_000_000, policy),
    );
}

test "checkZipBomb: detects file size exceeds limit" {
    // Arrange
    const policy = security.SecurityPolicy{
        .max_file_size = 1 * 1024 * 1024, // 1MB limit
    };

    // Act & Assert - 2MB file exceeds 1MB limit
    // Keep ratio = 1:1 to avoid tripping the ratio check
    try std.testing.expectError(
        error.FileSizeExceedsLimit,
        security.checkZipBomb(2 * 1024 * 1024, 2 * 1024 * 1024, policy),
    );
}

test "checkZipBomb: handles zero compressed size" {
    // Arrange
    const policy = security.SecurityPolicy{};

    // Act & Assert - stored (uncompressed) files should not trigger ratio check
    try security.checkZipBomb(0, 1000, policy);
    try security.checkZipBomb(0, 1_000_000, policy);
}

// ============================================================================
// Extraction Tracker Tests
// ============================================================================

test "ExtractionTracker: tracks cumulative size" {
    // Arrange
    const policy = security.SecurityPolicy{
        .max_total_size = 10000,
    };
    var tracker = security.ExtractionTracker.init(policy);

    // Act
    try tracker.addFile(1000);
    try tracker.addFile(2000);
    try tracker.addFile(3000);

    // Assert
    try std.testing.expectEqual(@as(u64, 6000), tracker.total_uncompressed);
    try std.testing.expectEqual(@as(usize, 3), tracker.file_count);
}

test "ExtractionTracker: detects total size limit exceeded" {
    // Arrange
    const policy = security.SecurityPolicy{
        .max_total_size = 10000,
    };
    var tracker = security.ExtractionTracker.init(policy);

    // Act
    try tracker.addFile(5000);
    try tracker.addFile(4000);

    // Assert - next file would exceed limit
    try std.testing.expectError(
        error.TotalSizeExceedsLimit,
        tracker.addFile(2000),
    );
}

test "ExtractionTracker: detects integer overflow" {
    // Arrange
    const policy = security.SecurityPolicy{
        .max_total_size = std.math.maxInt(u64),
    };
    var tracker = security.ExtractionTracker.init(policy);

    // Act - add max value
    try tracker.addFile(std.math.maxInt(u64) - 1000);

    // Assert - adding more would overflow
    try std.testing.expectError(
        error.TotalSizeExceedsLimit,
        tracker.addFile(2000),
    );
}

test "ExtractionTracker: allows extraction within limit" {
    // Arrange
    const policy = security.SecurityPolicy{
        .max_total_size = 100_000,
    };
    var tracker = security.ExtractionTracker.init(policy);

    // Act - add files totaling exactly the limit
    try tracker.addFile(30_000);
    try tracker.addFile(30_000);
    try tracker.addFile(30_000);
    try tracker.addFile(10_000);

    // Assert
    try std.testing.expectEqual(@as(u64, 100_000), tracker.total_uncompressed);
    try std.testing.expectEqual(@as(usize, 4), tracker.file_count);
}

// ============================================================================
// Symlink Validation Tests
// ============================================================================

test "validateSymlink: disallow policy rejects all symlinks" {
    // Arrange
    const allocator = std.testing.allocator;
    const policy = security.SecurityPolicy{
        .symlink_policy = .disallow,
    };

    const test_cases = [_]struct {
        link: []const u8,
        target: []const u8,
    }{
        .{ .link = "link", .target = "target" },
        .{ .link = "link", .target = "../target" },
        .{ .link = "link", .target = "/absolute/target" },
    };

    // Act & Assert
    for (test_cases) |tc| {
        try std.testing.expectError(
            error.SymlinkNotAllowed,
            security.validateSymlink(allocator, tc.link, tc.target, "/tmp", policy),
        );
    }
}

test "validateSymlink: only_relative allows safe relative links" {
    // Arrange
    const allocator = std.testing.allocator;
    const policy = security.SecurityPolicy{
        .symlink_policy = .only_relative,
    };

    const safe_links = [_]struct {
        link: []const u8,
        target: []const u8,
    }{
        .{ .link = "link", .target = "target" },
        .{ .link = "dir/link", .target = "../file" },
        .{ .link = "a/b/link", .target = "../c/file" },
    };

    // Act & Assert
    for (safe_links) |tc| {
        try security.validateSymlink(allocator, tc.link, tc.target, "/tmp", policy);
    }
}

test "validateSymlink: only_relative rejects absolute links" {
    // Arrange
    const allocator = std.testing.allocator;
    const policy = security.SecurityPolicy{
        .symlink_policy = .only_relative,
    };

    // Act & Assert
    try std.testing.expectError(
        error.AbsoluteSymlinkNotAllowed,
        security.validateSymlink(allocator, "link", "/etc/passwd", "/tmp", policy),
    );

    try std.testing.expectError(
        error.AbsoluteSymlinkNotAllowed,
        security.validateSymlink(allocator, "link", "/absolute/path", "/tmp", policy),
    );
}

test "validateSymlink: only_relative detects escape attempts" {
    // Arrange
    const allocator = std.testing.allocator;
    const policy = security.SecurityPolicy{
        .symlink_policy = .only_relative,
    };

    // Act & Assert - link that escapes extraction directory
    try std.testing.expectError(
        error.SymlinkEscapeAttempt,
        security.validateSymlink(
            allocator,
            "link",
            "../../../../etc/passwd",
            "/tmp/extract",
            policy,
        ),
    );
}

test "validateSymlink: allow_all permits any symlink" {
    // Arrange
    const allocator = std.testing.allocator;
    const policy = security.SecurityPolicy{
        .symlink_policy = .allow_all,
    };

    // Act & Assert - all should pass
    try security.validateSymlink(allocator, "link", "target", "/tmp", policy);
    try security.validateSymlink(allocator, "link", "/etc/passwd", "/tmp", policy);
    try security.validateSymlink(allocator, "link", "../../../etc/passwd", "/tmp", policy);
}

// ============================================================================
// Filename Normalization Tests
// ============================================================================

test "normalizeFilename: passes through normal filenames" {
    // Arrange
    const allocator = std.testing.allocator;

    const normal_names = [_][]const u8{
        "file.txt",
        "document.pdf",
        "my_file_123.dat",
        "file-with-dashes.txt",
    };

    // Act & Assert
    for (normal_names) |name| {
        const result = try security.normalizeFilename(allocator, name);
        defer allocator.free(result);
        try std.testing.expectEqualStrings(name, result);
    }
}

test "normalizeFilename: replaces newlines with underscores" {
    // Arrange
    const allocator = std.testing.allocator;

    // Act
    const result = try security.normalizeFilename(allocator, "file\nwith\nnewlines.txt");
    defer allocator.free(result);

    // Assert
    try std.testing.expectEqualStrings("file_with_newlines.txt", result);
}

test "normalizeFilename: replaces carriage returns" {
    // Arrange
    const allocator = std.testing.allocator;

    // Act
    const result = try security.normalizeFilename(allocator, "file\rwith\rreturns.txt");
    defer allocator.free(result);

    // Assert
    try std.testing.expectEqualStrings("file_with_returns.txt", result);
}

test "normalizeFilename: rejects NULL bytes" {
    // Arrange
    const allocator = std.testing.allocator;

    // Act & Assert
    try std.testing.expectError(
        error.NullByteInFilename,
        security.normalizeFilename(allocator, "file\x00.txt"),
    );
}

// ============================================================================
// SecurityPolicy Tests
// ============================================================================

test "SecurityPolicy: defaults are secure" {
    // Arrange & Act
    const policy = security.SecurityPolicy{};

    // Assert
    try std.testing.expectEqual(false, policy.allow_absolute_paths);
    try std.testing.expectEqual(false, policy.allow_symlink_escape);
    try std.testing.expectEqual(false, policy.allow_path_traversal);
    try std.testing.expectEqual(true, policy.verify_checksums);
    try std.testing.expectEqual(false, policy.preserve_permissions);
    try std.testing.expectEqual(security.SymlinkPolicy.disallow, policy.symlink_policy);

    // Verify size limits are reasonable
    try std.testing.expectEqual(@as(u64, 10 * 1024 * 1024 * 1024), policy.max_file_size);
    try std.testing.expectEqual(@as(u64, 100 * 1024 * 1024 * 1024), policy.max_total_size);
    try std.testing.expectEqual(@as(f64, 1000.0), policy.max_compression_ratio);
}

test "SecurityPolicy: can customize limits" {
    // Arrange & Act
    const policy = security.SecurityPolicy{
        .max_file_size = 1 * 1024 * 1024, // 1MB
        .max_total_size = 10 * 1024 * 1024, // 10MB
        .max_compression_ratio = 100.0,
        .allow_path_traversal = true,
        .symlink_policy = .allow_all,
    };

    // Assert
    try std.testing.expectEqual(@as(u64, 1 * 1024 * 1024), policy.max_file_size);
    try std.testing.expectEqual(@as(u64, 10 * 1024 * 1024), policy.max_total_size);
    try std.testing.expectEqual(@as(f64, 100.0), policy.max_compression_ratio);
    try std.testing.expectEqual(true, policy.allow_path_traversal);
    try std.testing.expectEqual(security.SymlinkPolicy.allow_all, policy.symlink_policy);
}

// ============================================================================
// Memory Leak Tests
// ============================================================================

test "normalizeFilename: no memory leak" {
    // Arrange
    const allocator = std.testing.allocator;

    // Act
    const result = try security.normalizeFilename(allocator, "test.txt");
    defer allocator.free(result);

    // Assert (std.testing.allocator checks for leaks)
}

test "validateSymlink: no memory leak" {
    // Arrange
    const allocator = std.testing.allocator;

    const policy = security.SecurityPolicy{
        .symlink_policy = .only_relative,
    };

    // Act
    try security.validateSymlink(allocator, "link", "target", "/tmp", policy);

    // Assert (std.testing.allocator checks for leaks)
}
