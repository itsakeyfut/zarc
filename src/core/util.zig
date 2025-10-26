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

/// Parse octal string to unsigned integer
///
/// Commonly used in tar headers for file mode, size, etc.
///
/// Parameters:
///   - text: Octal string (may contain spaces and null terminators)
///
/// Returns:
///   - Parsed unsigned integer value
///
/// Errors:
///   - error.InvalidCharacter: Non-octal character found
///   - error.Overflow: Value exceeds u64 range
///
/// Example:
/// ```zig
/// const mode = try parseOctal("0000644");  // 420 (0o644 in decimal)
/// const size = try parseOctal("00000001234"); // 668 (0o1234 in decimal)
/// ```
pub fn parseOctal(text: []const u8) !u64 {
    var result: u64 = 0;
    var found_digit = false;

    for (text) |c| {
        switch (c) {
            '0'...'7' => {
                const digit = c - '0';
                result = try std.math.mul(u64, result, 8);
                result = try std.math.add(u64, result, digit);
                found_digit = true;
            },
            ' ', '\x00' => {
                // Skip spaces and null terminators
                if (found_digit) break; // Stop at first space after digits
            },
            else => return error.InvalidCharacter,
        }
    }

    return result;
}

/// Format file size in human-readable format
///
/// Parameters:
///   - allocator: Memory allocator
///   - bytes: File size in bytes
///
/// Returns:
///   - Formatted size string (e.g., "1.5 KB", "2.3 MB")
///   - Caller must free the returned string
///
/// Example:
/// ```zig
/// const size_str = try formatSize(allocator, 1536); // "1.5 KB"
/// defer allocator.free(size_str);
/// ```
pub fn formatSize(allocator: std.mem.Allocator, bytes: u64) ![]const u8 {
    const kb: f64 = 1024.0;
    const mb: f64 = kb * 1024.0;
    const gb: f64 = mb * 1024.0;
    const tb: f64 = gb * 1024.0;

    const bytes_f = @as(f64, @floatFromInt(bytes));

    if (bytes_f >= tb) {
        return try std.fmt.allocPrint(allocator, "{d:.1} TB", .{bytes_f / tb});
    } else if (bytes_f >= gb) {
        return try std.fmt.allocPrint(allocator, "{d:.1} GB", .{bytes_f / gb});
    } else if (bytes_f >= mb) {
        return try std.fmt.allocPrint(allocator, "{d:.1} MB", .{bytes_f / mb});
    } else if (bytes_f >= kb) {
        return try std.fmt.allocPrint(allocator, "{d:.1} KB", .{bytes_f / kb});
    } else {
        return try std.fmt.allocPrint(allocator, "{d} B", .{bytes});
    }
}

/// Format Unix timestamp to ISO 8601 string
///
/// Parameters:
///   - allocator: Memory allocator
///   - timestamp: Unix timestamp (seconds since epoch)
///
/// Returns:
///   - ISO 8601 formatted string (YYYY-MM-DD HH:MM:SS)
///   - Caller must free the returned string
///
/// Example:
/// ```zig
/// const time_str = try formatTimestamp(allocator, 1234567890);
/// defer allocator.free(time_str);
/// // "2009-02-13 23:31:30"
/// ```
pub fn formatTimestamp(allocator: std.mem.Allocator, timestamp: i64) ![]const u8 {
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    return try std.fmt.allocPrint(
        allocator,
        "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}",
        .{
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        },
    );
}

/// Check if path is safe (no path traversal)
///
/// Parameters:
///   - path: Path to check
///
/// Returns:
///   - true if path is safe, false otherwise
///
/// Example:
/// ```zig
/// try std.testing.expect(isSafePath("foo/bar.txt"));
/// try std.testing.expect(!isSafePath("../etc/passwd"));
/// ```
pub fn isSafePath(path: []const u8) bool {
    // Check for absolute paths
    if (std.fs.path.isAbsolute(path)) {
        return false;
    }

    // Check for path traversal
    var it = std.mem.splitScalar(u8, path, '/');
    var depth: i32 = 0;

    while (it.next()) |component| {
        if (std.mem.eql(u8, component, "..")) {
            depth -= 1;
            if (depth < 0) {
                return false; // Attempts to escape root
            }
        } else if (!std.mem.eql(u8, component, ".") and component.len > 0) {
            depth += 1;
        }
    }

    return true;
}

/// Sanitize path by removing dangerous components
///
/// Parameters:
///   - allocator: Memory allocator
///   - path: Path to sanitize
///
/// Returns:
///   - Sanitized path (caller must free)
///
/// Errors:
///   - error.PathTraversalAttempt: Path contains unsafe traversal
///
/// Example:
/// ```zig
/// const safe = try sanitizePath(allocator, "./foo/./bar.txt");
/// defer allocator.free(safe);
/// // Result: "foo/bar.txt"
/// ```
pub fn sanitizePath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (!isSafePath(path)) {
        return error.PathTraversalAttempt;
    }

    var components = std.array_list.Aligned([]const u8, null).empty;
    defer components.deinit(allocator);

    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |component| {
        if (std.mem.eql(u8, component, ".") or component.len == 0) {
            continue; // Skip "." and empty components
        } else if (std.mem.eql(u8, component, "..")) {
            if (components.items.len > 0) {
                _ = components.pop();
            }
        } else {
            try components.append(allocator, component);
        }
    }

    return try std.mem.join(allocator, "/", components.items);
}

/// Calculate checksum for data block
///
/// Parameters:
///   - data: Data to checksum
///
/// Returns:
///   - Simple sum checksum (used in tar headers)
///
/// Example:
/// ```zig
/// const checksum = calculateChecksum(&header_data);
/// ```
pub fn calculateChecksum(data: []const u8) u32 {
    var sum: u32 = 0;
    for (data) |byte| {
        sum += byte;
    }
    return sum;
}

// Tests
test "parseOctal: valid octal strings" {
    try std.testing.expectEqual(@as(u64, 0), try parseOctal("0000000"));
    try std.testing.expectEqual(@as(u64, 0o644), try parseOctal("0000644"));
    try std.testing.expectEqual(@as(u64, 0o755), try parseOctal("0000755"));
    try std.testing.expectEqual(@as(u64, 0o1234), try parseOctal("00001234"));
}

test "parseOctal: with spaces and null terminators" {
    try std.testing.expectEqual(@as(u64, 0o644), try parseOctal("0000644 "));
    try std.testing.expectEqual(@as(u64, 0o644), try parseOctal("0000644\x00"));
    try std.testing.expectEqual(@as(u64, 0o755), try parseOctal(" 0000755"));
}

test "parseOctal: invalid characters" {
    try std.testing.expectError(error.InvalidCharacter, parseOctal("12345678"));
    try std.testing.expectError(error.InvalidCharacter, parseOctal("abc"));
    try std.testing.expectError(error.InvalidCharacter, parseOctal("0o644"));
}

test "formatSize: various sizes" {
    const allocator = std.testing.allocator;

    {
        const s = try formatSize(allocator, 512);
        defer allocator.free(s);
        try std.testing.expectEqualStrings("512 B", s);
    }

    {
        const s = try formatSize(allocator, 1024);
        defer allocator.free(s);
        try std.testing.expectEqualStrings("1.0 KB", s);
    }

    {
        const s = try formatSize(allocator, 1536);
        defer allocator.free(s);
        try std.testing.expectEqualStrings("1.5 KB", s);
    }

    {
        const s = try formatSize(allocator, 1024 * 1024);
        defer allocator.free(s);
        try std.testing.expectEqualStrings("1.0 MB", s);
    }

    {
        const s = try formatSize(allocator, 1024 * 1024 * 1024);
        defer allocator.free(s);
        try std.testing.expectEqualStrings("1.0 GB", s);
    }
}

test "formatTimestamp: Unix epoch" {
    const allocator = std.testing.allocator;

    const s = try formatTimestamp(allocator, 0);
    defer allocator.free(s);

    // Unix epoch: 1970-01-01 00:00:00
    try std.testing.expectEqualStrings("1970-01-01 00:00:00", s);
}

test "formatTimestamp: specific date" {
    const allocator = std.testing.allocator;

    // 2009-02-13 23:31:30
    const s = try formatTimestamp(allocator, 1234567890);
    defer allocator.free(s);

    try std.testing.expectEqualStrings("2009-02-13 23:31:30", s);
}

test "isSafePath: safe paths" {
    try std.testing.expect(isSafePath("foo/bar.txt"));
    try std.testing.expect(isSafePath("./foo/bar.txt"));
    try std.testing.expect(isSafePath("foo/./bar.txt"));
    try std.testing.expect(isSafePath("foo/bar/../baz.txt"));
}

test "isSafePath: unsafe paths" {
    try std.testing.expect(!isSafePath("../etc/passwd"));
    try std.testing.expect(!isSafePath("foo/../../etc/passwd"));
    try std.testing.expect(!isSafePath("/etc/passwd"));
    try std.testing.expect(!isSafePath("/absolute/path"));
}

test "sanitizePath: remove dots and empty components" {
    const allocator = std.testing.allocator;

    {
        const s = try sanitizePath(allocator, "./foo/./bar.txt");
        defer allocator.free(s);
        try std.testing.expectEqualStrings("foo/bar.txt", s);
    }

    {
        const s = try sanitizePath(allocator, "foo//bar///baz.txt");
        defer allocator.free(s);
        try std.testing.expectEqualStrings("foo/bar/baz.txt", s);
    }

    {
        const s = try sanitizePath(allocator, "foo/bar/../baz.txt");
        defer allocator.free(s);
        try std.testing.expectEqualStrings("foo/baz.txt", s);
    }
}

test "sanitizePath: path traversal error" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(
        error.PathTraversalAttempt,
        sanitizePath(allocator, "../etc/passwd"),
    );

    try std.testing.expectError(
        error.PathTraversalAttempt,
        sanitizePath(allocator, "/absolute/path"),
    );
}

test "calculateChecksum: simple sum" {
    const data = "Hello, World!";
    const checksum = calculateChecksum(data);

    // Manual calculation: sum of ASCII values
    var expected: u32 = 0;
    for (data) |c| {
        expected += c;
    }

    try std.testing.expectEqual(expected, checksum);
}

test "calculateChecksum: empty data" {
    const checksum = calculateChecksum("");
    try std.testing.expectEqual(@as(u32, 0), checksum);
}
