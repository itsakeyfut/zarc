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
const zarc = @import("zarc");
const compress = zarc.compress.zlib;
const gzip_mod = zarc.compress.gzip;

test "gzip: compress and decompress round-trip" {
    const allocator = std.testing.allocator;

    const test_cases = [_][]const u8{
        "Hello, World!",
        "Short",
        "A" ** 1000, // Repeated character
        "",
        "Special chars: \n\t\r",
        "Unicode: こんにちは世界 🌍",
    };

    for (test_cases) |original| {
        // Compress
        const compressed = try compress.compress(allocator, .gzip, original);
        defer allocator.free(compressed);

        // Decompress
        const decompressed = try compress.decompress(allocator, .gzip, compressed);
        defer allocator.free(decompressed);

        // Verify
        try std.testing.expectEqualStrings(original, decompressed);
    }
}

test "zlib: compress and decompress round-trip" {
    const allocator = std.testing.allocator;

    const test_cases = [_][]const u8{
        "Hello, World!",
        "Zlib format test",
        "B" ** 500,
    };

    for (test_cases) |original| {
        // Compress
        const compressed = try compress.compress(allocator, .zlib, original);
        defer allocator.free(compressed);

        // Decompress
        const decompressed = try compress.decompress(allocator, .zlib, compressed);
        defer allocator.free(decompressed);

        // Verify
        try std.testing.expectEqualStrings(original, decompressed);
    }
}

test "gzip header: parse basic header" {
    const allocator = std.testing.allocator;

    // Create a gzip file
    const original = "Test data";
    const compressed = try compress.compress(allocator, .gzip, original);
    defer allocator.free(compressed);

    // Parse header
    var header = try compress.readGzipHeader(allocator, compressed);
    defer header.deinit(allocator);

    // Verify header fields
    try std.testing.expectEqual(@as(u8, 8), header.compression_method);
    try std.testing.expectEqual(gzip_mod.Os.unix, header.os); // C zlib uses Unix by default
}

test "gzip header: write and parse" {
    const allocator = std.testing.allocator;

    const header = gzip_mod.Header{
        .compression_method = 8,
        .flags = .{ .fname = true, .fcomment = true },
        .mtime = 1234567890,
        .extra_flags = .default,
        .os = .unix,
        .filename = "test.txt",
        .comment = "Test file",
    };

    // Write header
    var buffer: [512]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try header.write(stream.writer());

    // Parse it back
    stream.reset();
    var parsed = try gzip_mod.Header.parse(allocator, stream.reader());
    defer parsed.deinit(allocator);

    // Verify
    try std.testing.expectEqual(header.compression_method, parsed.compression_method);
    try std.testing.expectEqual(header.mtime, parsed.mtime);
    try std.testing.expectEqual(header.os, parsed.os);
    try std.testing.expectEqualStrings("test.txt", parsed.filename.?);
    try std.testing.expectEqualStrings("Test file", parsed.comment.?);
}

test "gzip: decompress with header info" {
    const allocator = std.testing.allocator;

    const original = "Data for header info extraction test";
    const compressed = try compress.compress(allocator, .gzip, original);
    defer allocator.free(compressed);

    // Decompress with header info
    var result = try compress.decompressGzipWithInfo(allocator, compressed);
    defer result.deinit(allocator);

    // Verify data
    try std.testing.expectEqualStrings(original, result.data);

    // Verify header
    try std.testing.expectEqual(@as(u8, 8), result.header.compression_method);

    // Verify footer
    try std.testing.expectEqual(@as(u32, @truncate(original.len)), result.footer.isize);

    // CRC32 verification would require computing CRC32 of original
    try std.testing.expect(result.footer.crc32 != 0);
}

test "gzip header: all optional fields" {
    const allocator = std.testing.allocator;

    const header = gzip_mod.Header{
        .compression_method = 8,
        .flags = .{
            .ftext = true,
            .fextra = true,
            .fname = true,
            .fcomment = true,
        },
        .mtime = 987654321,
        .extra_flags = .max_compression,
        .os = .macintosh,
        .extra = &[_]u8{ 1, 2, 3, 4 },
        .filename = "document.txt",
        .comment = "Important file",
    };

    // Write
    var buffer: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try header.write(stream.writer());

    // Parse
    stream.reset();
    var parsed = try gzip_mod.Header.parse(allocator, stream.reader());
    defer parsed.deinit(allocator);

    // Verify all fields
    try std.testing.expectEqual(header.compression_method, parsed.compression_method);
    try std.testing.expectEqual(header.flags.ftext, parsed.flags.ftext);
    try std.testing.expectEqual(header.flags.fextra, parsed.flags.fextra);
    try std.testing.expectEqual(header.flags.fname, parsed.flags.fname);
    try std.testing.expectEqual(header.flags.fcomment, parsed.flags.fcomment);
    try std.testing.expectEqual(header.mtime, parsed.mtime);
    try std.testing.expectEqual(header.extra_flags, parsed.extra_flags);
    try std.testing.expectEqual(header.os, parsed.os);
    try std.testing.expectEqualSlices(u8, header.extra.?, parsed.extra.?);
    try std.testing.expectEqualStrings(header.filename.?, parsed.filename.?);
    try std.testing.expectEqualStrings(header.comment.?, parsed.comment.?);
}

test "gzip header: invalid magic number" {
    const allocator = std.testing.allocator;

    const bad_data = [_]u8{
        0x00, 0x00, // Wrong magic
        0x08, 0x00,
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x03,
    };

    var stream = std.io.fixedBufferStream(&bad_data);
    const result = gzip_mod.Header.parse(allocator, stream.reader());

    try std.testing.expectError(error.InvalidGzipMagic, result);
}

test "gzip header: unsupported compression method" {
    const allocator = std.testing.allocator;

    const bad_data = [_]u8{
        0x1f, 0x8b, // Correct magic
        0x07, // Wrong compression method (not deflate)
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x03,
    };

    var stream = std.io.fixedBufferStream(&bad_data);
    const result = gzip_mod.Header.parse(allocator, stream.reader());

    try std.testing.expectError(error.UnsupportedCompressionMethod, result);
}

test "large data compression" {
    const allocator = std.testing.allocator;

    // Generate 10KB of data
    const size = 10 * 1024;
    const original = try allocator.alloc(u8, size);
    defer allocator.free(original);

    // Fill with pseudo-random data
    for (original, 0..) |*byte, i| {
        byte.* = @truncate(i * 13 + 7);
    }

    // Compress
    const compressed = try compress.compress(allocator, .gzip, original);
    defer allocator.free(compressed);

    // Should be smaller (compressible pattern)
    try std.testing.expect(compressed.len < original.len);

    // Decompress
    const decompressed = try compress.decompress(allocator, .gzip, compressed);
    defer allocator.free(decompressed);

    // Verify
    try std.testing.expectEqualSlices(u8, original, decompressed);
}
