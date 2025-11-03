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

//! C compatibility wrapper for zlib library
//!
//! This module provides a Zig-friendly interface to the zlib C library
//! for compression operations. This is a temporary solution during Phase 1-2,
//! and will be replaced with a pure Zig implementation in Phase 3+.
//!
//! See ADR-004-zlib-integration.md for the rationale behind this decision.
//!
//! Migration Path:
//! - Phase 1-2: C integration (this module)
//! - Phase 3: Pure Zig implementation
//! - Phase 4+: C dependencies removed
//!
//! External Dependencies:
//! - zlib 1.3.1+ (zlib License - MIT compatible)
//! - C wrapper: src/c/zlib_compress.c

const std = @import("std");

/// Compression format
pub const Format = enum(c_int) {
    /// Gzip format (RFC 1952)
    gzip = 0,
    /// Zlib format (RFC 1950)
    zlib = 1,
};

/// C compression result structure
/// This matches the struct defined in src/c/zlib_compress.h
const CCompressResult = extern struct {
    data: ?[*]u8,
    size: usize,
    error_code: c_int,
};

/// External C function for compression
/// Implemented in src/c/zlib_compress.c
extern "c" fn zlib_compress(format: Format, src: [*]const u8, src_len: usize) CCompressResult;

/// External C function for decompression
/// Implemented in src/c/zlib_compress.c
extern "c" fn zlib_decompress(format: Format, src: [*]const u8, src_len: usize) CCompressResult;

/// External C function to free zlib-allocated memory
/// Implemented in src/c/zlib_compress.c
extern "c" fn zlib_free(ptr: ?*anyopaque) void;

/// Compress data using zlib (via C implementation)
///
/// This function wraps the zlib C library for compression operations.
/// The compressed data is allocated using the Zig allocator and must be
/// freed by the caller.
///
/// Parameters:
///   - allocator: Memory allocator for the output buffer
///   - format: Compression format (gzip or zlib)
///   - data: Input data to compress
///
/// Returns:
///   - Compressed data (caller owns the memory)
///
/// Errors:
///   - error.CompressionFailed: zlib compression failed
///   - error.OutOfMemory: Memory allocation failed
pub fn compress(allocator: std.mem.Allocator, format: Format, data: []const u8) ![]u8 {
    // Call C compression function
    const result = zlib_compress(format, data.ptr, data.len);

    // Check for errors
    if (result.error_code != 0) {
        // Free C-allocated memory if any
        if (result.data) |ptr| {
            zlib_free(ptr);
        }
        return error.CompressionFailed;
    }

    // Ensure we got data back
    const c_data = result.data orelse return error.CompressionFailed;
    if (result.size == 0) {
        zlib_free(c_data);
        return error.CompressionFailed;
    }

    // Copy C-allocated data to Zig-managed memory
    const compressed = try allocator.alloc(u8, result.size);
    errdefer allocator.free(compressed);

    @memcpy(compressed, c_data[0..result.size]);

    // Free C-allocated memory
    zlib_free(c_data);

    return compressed;
}

/// Decompress data using zlib (via C implementation)
///
/// This function wraps the zlib C library for decompression operations.
/// The decompressed data is allocated using the Zig allocator and must be
/// freed by the caller.
///
/// Parameters:
///   - allocator: Memory allocator for the output buffer
///   - format: Compression format (gzip or zlib)
///   - data: Compressed data to decompress
///
/// Returns:
///   - Decompressed data (caller owns the memory)
///
/// Errors:
///   - error.ChecksumMismatch: CRC/Adler32 checksum validation failed
///   - error.DecompressionFailed: zlib decompression failed
///   - error.OutOfMemory: Memory allocation failed
pub fn decompress(allocator: std.mem.Allocator, format: Format, data: []const u8) ![]u8 {
    // Call C decompression function
    const result = zlib_decompress(format, data.ptr, data.len);

    // Check for errors
    if (result.error_code != 0) {
        // Free C-allocated memory if any
        if (result.data) |ptr| {
            zlib_free(ptr);
        }
        // Z_DATA_ERROR (-3) indicates corrupted data or checksum mismatch
        if (result.error_code == -3) {
            return error.ChecksumMismatch;
        }
        return error.DecompressionFailed;
    }

    // Ensure we got data back
    const c_data = result.data orelse return error.DecompressionFailed;

    // Allow empty decompressed data (valid for empty inputs)
    if (result.size == 0) {
        zlib_free(c_data);
        return try allocator.alloc(u8, 0);
    }

    // Copy C-allocated data to Zig-managed memory
    const decompressed = try allocator.alloc(u8, result.size);
    errdefer allocator.free(decompressed);

    @memcpy(decompressed, c_data[0..result.size]);

    // Free C-allocated memory
    zlib_free(c_data);

    return decompressed;
}

test "compress gzip format" {
    const allocator = std.testing.allocator;
    const original = "Hello, World! This is a test of gzip compression.";

    const compressed = try compress(allocator, .gzip, original);
    defer allocator.free(compressed);

    // Verify compressed data exists
    try std.testing.expect(compressed.len > 0);

    // Verify gzip magic number (0x1f 0x8b)
    try std.testing.expectEqual(@as(u8, 0x1f), compressed[0]);
    try std.testing.expectEqual(@as(u8, 0x8b), compressed[1]);

    // Note: For small strings, compressed size may be larger due to
    // gzip header (10 bytes) and footer (8 bytes) overhead
}

test "compress zlib format" {
    const allocator = std.testing.allocator;
    const original = "Hello, World! This is a test of zlib compression.";

    const compressed = try compress(allocator, .zlib, original);
    defer allocator.free(compressed);

    // Verify compressed data exists
    try std.testing.expect(compressed.len > 0);

    // Verify zlib header (0x78 for default compression)
    try std.testing.expectEqual(@as(u8, 0x78), compressed[0]);
}

test "compress empty data" {
    const allocator = std.testing.allocator;
    const original = "";

    const compressed = try compress(allocator, .gzip, original);
    defer allocator.free(compressed);

    // Even empty data should produce a valid gzip stream with header and footer
    try std.testing.expect(compressed.len > 0);
    try std.testing.expectEqual(@as(u8, 0x1f), compressed[0]);
    try std.testing.expectEqual(@as(u8, 0x8b), compressed[1]);
}
