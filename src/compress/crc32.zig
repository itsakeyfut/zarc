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

//! CRC-32 checksum calculation
//!
//! This module implements the CRC-32 algorithm (IEEE 802.3) as specified
//! in RFC 1952 (gzip file format specification).
//!
//! The CRC-32 is used to verify data integrity in gzip archives.

const std = @import("std");

/// CRC-32 polynomial (IEEE 802.3)
/// This is the standard polynomial used by gzip, zlib, PNG, Ethernet, etc.
const CRC32_POLYNOMIAL: u32 = 0xEDB88320;

/// CRC-32 lookup table (computed at compile time; thread-safe)
const crc32_table: [256]u32 = blk: {
    @setEvalBranchQuota(3000); // 256 entries * 8 iterations + overhead
    var t: [256]u32 = undefined;
    var n: u32 = 0;
    while (n < 256) : (n += 1) {
        var c: u32 = n;
        var k: u32 = 0;
        while (k < 8) : (k += 1) {
            if ((c & 1) != 0) {
                c = CRC32_POLYNOMIAL ^ (c >> 1);
            } else {
                c = c >> 1;
            }
        }
        t[n] = c;
    }
    break :blk t;
};

/// Backwards-compat no-op; table is always ready
fn initializeCrc32Table() void {}

const table_initialized = true;

/// Calculate CRC-32 checksum for the given data
///
/// This function computes the CRC-32 checksum using the IEEE 802.3
/// polynomial (0xEDB88320). This is the standard CRC-32 algorithm used
/// by gzip, zlib, PNG, and many other formats.
///
/// Parameters:
///   - data: Input data to calculate checksum for
///
/// Returns:
///   - CRC-32 checksum as u32
///
/// Example:
/// ```zig
/// const checksum = crc32("Hello, World!");
/// ```
pub fn crc32(data: []const u8) u32 {
    var c: u32 = 0xFFFFFFFF; // Initialize to all 1s

    for (data) |byte| {
        const index: u8 = @truncate((c ^ byte) & 0xFF);
        c = crc32_table[index] ^ (c >> 8);
    }

    return c ^ 0xFFFFFFFF; // Final XOR with all 1s
}

/// Incremental CRC-32 calculator
/// Useful for computing checksums of streaming data or large files
pub const Crc32 = struct {
    value: u32,

    /// Initialize a new CRC-32 calculator
    pub fn init() Crc32 {
        return .{ .value = 0xFFFFFFFF };
    }

    /// Update the CRC-32 with new data
    pub fn update(self: *Crc32, data: []const u8) void {
        for (data) |byte| {
            const index: u8 = @truncate((self.value ^ byte) & 0xFF);
            self.value = crc32_table[index] ^ (self.value >> 8);
        }
    }

    /// Get the final CRC-32 value
    pub fn final(self: Crc32) u32 {
        return self.value ^ 0xFFFFFFFF;
    }

    /// Reset the calculator to initial state
    pub fn reset(self: *Crc32) void {
        self.value = 0xFFFFFFFF;
    }
};

// Tests

test "crc32: empty data" {
    const result = crc32("");
    // CRC-32 of empty data is 0
    try std.testing.expectEqual(@as(u32, 0), result);
}

test "crc32: single byte" {
    const result = crc32(&[_]u8{0x00});
    try std.testing.expectEqual(@as(u32, 0xD202EF8D), result);
}

test "crc32: known test vectors" {
    // Test vectors verified with std.hash.crc.Crc32
    const test_cases = [_]struct {
        data: []const u8,
        expected: u32,
    }{
        // Empty string
        .{ .data = "", .expected = 0x00000000 },

        // Single characters
        .{ .data = "a", .expected = 0xE8B7BE43 },
        .{ .data = "b", .expected = 0x71BEEFF9 },

        // Common test strings (RFC 1952 standard test vector)
        .{ .data = "123456789", .expected = 0xCBF43926 },
        .{ .data = "The quick brown fox jumps over the lazy dog", .expected = 0x414FA339 },
    };

    for (test_cases) |tc| {
        const result = crc32(tc.data);
        try std.testing.expectEqual(tc.expected, result);
    }
}

test "crc32: binary data" {
    // Test with binary data (not just ASCII)
    const binary_data = [_]u8{ 0x00, 0xFF, 0xAA, 0x55, 0x12, 0x34, 0x56, 0x78 };
    const result = crc32(&binary_data);

    // Verify it's deterministic
    const result2 = crc32(&binary_data);
    try std.testing.expectEqual(result, result2);
}

test "Crc32: incremental calculation" {
    const data = "Hello, World!";

    // Calculate in one go
    const direct = crc32(data);

    // Calculate incrementally
    var incremental = Crc32.init();
    incremental.update(data[0..5]); // "Hello"
    incremental.update(data[5..7]); // ", "
    incremental.update(data[7..]); // "World!"
    const result = incremental.final();

    // Both methods should give same result
    try std.testing.expectEqual(direct, result);
}

test "Crc32: reset functionality" {
    var crc = Crc32.init();

    crc.update("test data");
    const first = crc.final();

    crc.reset();
    crc.update("test data");
    const second = crc.final();

    // Results should be identical after reset
    try std.testing.expectEqual(first, second);
}

test "Crc32: large data" {
    const allocator = std.testing.allocator;

    // Create 1MB of test data
    const size = 1024 * 1024;
    const data = try allocator.alloc(u8, size);
    defer allocator.free(data);

    // Fill with pattern
    for (data, 0..) |*byte, i| {
        byte.* = @truncate(i);
    }

    // Calculate CRC-32
    const result = crc32(data);

    // Verify it's consistent
    const result2 = crc32(data);
    try std.testing.expectEqual(result, result2);

    // Also test incremental calculation
    var incremental = Crc32.init();
    var offset: usize = 0;
    const chunk_size = 64 * 1024; // 64KB chunks
    while (offset < data.len) {
        const end = @min(offset + chunk_size, data.len);
        incremental.update(data[offset..end]);
        offset = end;
    }
    const incremental_result = incremental.final();

    try std.testing.expectEqual(result, incremental_result);
}

test "crc32: table initialization (compile-time)" {
    // Verify table is always initialized (compile-time)
    try std.testing.expect(table_initialized);

    // Verify first few entries match expected values
    // These are known values from the CRC-32 algorithm
    try std.testing.expectEqual(@as(u32, 0x00000000), crc32_table[0]);
    try std.testing.expectEqual(@as(u32, 0x77073096), crc32_table[1]);
    try std.testing.expectEqual(@as(u32, 0xEE0E612C), crc32_table[2]);
    try std.testing.expectEqual(@as(u32, 0x990951BA), crc32_table[3]);
}

test "crc32: compatibility with gzip" {
    // Test that our CRC-32 matches the standard
    // The "123456789" test vector is the official CRC-32 test case
    // from RFC 1952 and other CRC-32 specifications

    const test_data = "123456789";
    const expected: u32 = 0xCBF43926;

    const result = crc32(test_data);
    try std.testing.expectEqual(expected, result);
}
