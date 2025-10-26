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
const gzip = @import("gzip.zig");
const c_zlib = @import("../c_compat/zlib.zig");

/// Re-export compression format from c_compat layer
pub const Format = c_zlib.Format;

/// Re-export gzip header types
pub const GzipHeader = gzip.Header;
pub const GzipFooter = gzip.Footer;
pub const GzipFlags = gzip.Flags;
pub const GzipOs = gzip.Os;

/// Compress data using zlib (via C implementation)
/// This is a wrapper around the c_compat layer for backward compatibility
pub fn compress(allocator: std.mem.Allocator, format: Format, data: []const u8) ![]u8 {
    return c_zlib.compress(allocator, format, data);
}

/// Decompress data using Zig's standard library (Pure Zig implementation)
pub fn decompress(allocator: std.mem.Allocator, format: Format, compressed_data: []const u8) ![]u8 {
    const flate = std.compress.flate;

    // Convert Format to flate.Container
    const container: flate.Container = switch (format) {
        .gzip => .gzip,
        .zlib => .zlib,
    };

    // Create Reader using std.Io.Reader.fixed()
    var in: std.Io.Reader = .fixed(compressed_data);

    // Create output buffer
    var out = std.array_list.Aligned(u8, null).empty;
    defer out.deinit(allocator);

    // Create output writer
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();

    // Decompress
    var decompressor: flate.Decompress = .init(&in, container, &.{});
    _ = try decompressor.reader.streamRemaining(&aw.writer);

    // Return the decompressed data
    return try allocator.dupe(u8, aw.written());
}

/// Result of gzip decompression with header information
pub const GzipDecompressResult = struct {
    /// Decompressed data
    data: []u8,
    /// Gzip header information
    header: GzipHeader,
    /// Gzip footer information
    footer: GzipFooter,

    pub fn deinit(self: *GzipDecompressResult, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        self.header.deinit(allocator);
    }
};

/// Decompress gzip data and extract header/footer information
pub fn decompressGzipWithInfo(allocator: std.mem.Allocator, compressed_data: []const u8) !GzipDecompressResult {
    var stream = std.io.fixedBufferStream(compressed_data);
    const reader = stream.reader();

    // Parse gzip header
    var header = try GzipHeader.parse(allocator, reader);
    errdefer header.deinit(allocator);

    // Decompress using the standard decompress function
    const decompressed = try decompress(allocator, .gzip, compressed_data);
    errdefer allocator.free(decompressed);

    // Parse footer (last 8 bytes)
    if (compressed_data.len < 8) {
        return error.InvalidGzipFooter;
    }

    var footer_stream = std.io.fixedBufferStream(compressed_data[compressed_data.len - 8 ..]);
    const footer = try GzipFooter.parse(footer_stream.reader());

    return GzipDecompressResult{
        .data = decompressed,
        .header = header,
        .footer = footer,
    };
}

/// Read only the gzip header without decompressing
pub fn readGzipHeader(allocator: std.mem.Allocator, compressed_data: []const u8) !GzipHeader {
    var stream = std.io.fixedBufferStream(compressed_data);
    return try GzipHeader.parse(allocator, stream.reader());
}

test "compress and decompress gzip" {
    const allocator = std.testing.allocator;
    const original = "Hello, World! This is a test of compression.";

    // Compress
    const compressed = try compress(allocator, .gzip, original);
    defer allocator.free(compressed);

    std.debug.print("Original size: {d}, Compressed size: {d}\n", .{ original.len, compressed.len });

    // Decompress
    const decompressed = try decompress(allocator, .gzip, compressed);
    defer allocator.free(decompressed);

    // Verify
    try std.testing.expectEqualStrings(original, decompressed);
}

test "compress and decompress zlib" {
    const allocator = std.testing.allocator;
    const original = "Hello, World! This is a test of zlib compression.";

    // Compress
    const compressed = try compress(allocator, .zlib, original);
    defer allocator.free(compressed);

    std.debug.print("Original size: {d}, Compressed size: {d}\n", .{ original.len, compressed.len });

    // Decompress
    const decompressed = try decompress(allocator, .zlib, compressed);
    defer allocator.free(decompressed);

    // Verify
    try std.testing.expectEqualStrings(original, decompressed);
}

test "decompress gzip with header info" {
    const allocator = std.testing.allocator;
    const original = "Test data for gzip header extraction";

    // Compress first
    const compressed = try compress(allocator, .gzip, original);
    defer allocator.free(compressed);

    // Decompress with header info
    var result = try decompressGzipWithInfo(allocator, compressed);
    defer result.deinit(allocator);

    // Verify decompressed data
    try std.testing.expectEqualStrings(original, result.data);

    // Verify header
    try std.testing.expectEqual(@as(u8, 8), result.header.compression_method);

    // Verify footer CRC and size
    try std.testing.expectEqual(@as(u32, @truncate(result.data.len)), result.footer.isize);
}

test "read gzip header only" {
    const allocator = std.testing.allocator;
    const original = "Sample data";

    // Compress
    const compressed = try compress(allocator, .gzip, original);
    defer allocator.free(compressed);

    // Read header only
    var header = try readGzipHeader(allocator, compressed);
    defer header.deinit(allocator);

    // Verify header
    try std.testing.expectEqual(@as(u8, 8), header.compression_method);
    try std.testing.expect(!std.mem.eql(u8, &gzip.magic_number, &[_]u8{ 0, 0 }));
}
