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
const deflate = zarc.compress.deflate.decode;
const zlib = zarc.compress.zlib;

// =============================================================================
// Block Type Tests
// Note: We use zlib.compress for creating test data (C library),
//       and test our deflate.decompress* functions against it.
// =============================================================================

// Note: Raw deflate decompression is not fully supported in Phase 1
// The uncompressed block test is disabled until Phase 2
// test "deflate: uncompressed block decompression" {
//     // Will be implemented in Phase 2 with pure Zig implementation
// }

test "deflate: fixed Huffman block decompression" {
    const allocator = std.testing.allocator;

    // Use zlib compression to create a deflate stream
    // (The actual block type used depends on the compressor's heuristics)
    const original = "AAAABBBBCCCCDDDD"; // Simple repeating pattern

    const compressed = try zlib.compress(allocator, .gzip, original);
    defer allocator.free(compressed);

    // Decompress using gzip container
    const decompressed = try deflate.decompressGzip(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

test "deflate: dynamic Huffman block decompression" {
    const allocator = std.testing.allocator;

    // Create larger data to encourage dynamic Huffman encoding
    var original = std.ArrayList(u8).init(allocator);
    defer original.deinit();

    const sentence = "The quick brown fox jumps over the lazy dog. ";
    for (0..50) |_| {
        try original.appendSlice(sentence);
    }

    const compressed = try zlib.compress(allocator, .gzip, original.items);
    defer allocator.free(compressed);

    // Decompress
    const decompressed = try deflate.decompressGzip(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, original.items, decompressed);
}

// =============================================================================
// LZ77 Back-reference Tests
// =============================================================================

test "deflate: LZ77 short distance back-reference" {
    const allocator = std.testing.allocator;

    // Create data with nearby repetitions (short distance)
    const original = "abcabcabcabcabc";

    const compressed = try zlib.compress(allocator, .gzip, original);
    defer allocator.free(compressed);

    // Decompress
    const decompressed = try deflate.decompressGzip(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

test "deflate: LZ77 long distance back-reference" {
    const allocator = std.testing.allocator;

    // Create data with far-apart repetitions (long distance)
    var original = std.ArrayList(u8).init(allocator);
    defer original.deinit();

    const pattern = "pattern123";
    // Add pattern at the start
    try original.appendSlice(pattern);
    // Add filler data
    for (0..1000) |i| {
        try original.append(@truncate(i));
    }
    // Repeat pattern (should create a long-distance back-reference)
    try original.appendSlice(pattern);

    const compressed = try zlib.compress(allocator, .gzip, original.items);
    defer allocator.free(compressed);

    // Decompress
    const decompressed = try deflate.decompressGzip(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, original.items, decompressed);
}

test "deflate: LZ77 maximum length match" {
    const allocator = std.testing.allocator;

    // Create very long repetitive sequence
    const pattern = "0123456789";
    var original = std.ArrayList(u8).init(allocator);
    defer original.deinit();

    for (0..300) |_| {
        try original.appendSlice(pattern);
    }

    const compressed = try zlib.compress(allocator, .gzip, original.items);
    defer allocator.free(compressed);

    // Verify good compression ratio (should be good for repetitive data)
    try std.testing.expect(compressed.len < original.items.len / 2);

    // Decompress
    const decompressed = try deflate.decompressGzip(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, original.items, decompressed);
}

// =============================================================================
// Container Format Tests
// =============================================================================

test "deflate: zlib container" {
    const allocator = std.testing.allocator;

    const original = "Zlib container format test with header and Adler32";

    const compressed = try zlib.compress(allocator, .zlib, original);
    defer allocator.free(compressed);

    // Verify zlib header is present (2 bytes)
    try std.testing.expect(compressed.len >= 2);

    // Test decompression
    const decompressed = try deflate.decompressZlib(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

test "deflate: gzip container" {
    const allocator = std.testing.allocator;

    const original = "Gzip container format test with header and CRC32";

    const compressed = try zlib.compress(allocator, .gzip, original);
    defer allocator.free(compressed);

    // Verify gzip magic number (1f 8b)
    try std.testing.expect(compressed.len >= 10);
    try std.testing.expectEqual(@as(u8, 0x1f), compressed[0]);
    try std.testing.expectEqual(@as(u8, 0x8b), compressed[1]);

    // Test decompression
    const decompressed = try deflate.decompressGzip(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

// =============================================================================
// Edge Case Tests
// =============================================================================

test "deflate: empty data" {
    const allocator = std.testing.allocator;

    const original = "";

    const compressed = try zlib.compress(allocator, .gzip, original);
    defer allocator.free(compressed);

    const decompressed = try deflate.decompressGzip(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

test "deflate: single byte" {
    const allocator = std.testing.allocator;

    const original = "X";

    const compressed = try zlib.compress(allocator, .gzip, original);
    defer allocator.free(compressed);

    const decompressed = try deflate.decompressGzip(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

test "deflate: large data (100KB)" {
    const allocator = std.testing.allocator;

    // Generate 100KB of pseudo-random data
    const size = 100 * 1024;
    const original = try allocator.alloc(u8, size);
    defer allocator.free(original);

    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();
    random.bytes(original);

    const compressed = try zlib.compress(allocator, .gzip, original);
    defer allocator.free(compressed);

    const decompressed = try deflate.decompressGzip(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, original, decompressed);
}

test "deflate: all zeros (best case for compression)" {
    const allocator = std.testing.allocator;

    const size = 10000;
    const original = try allocator.alloc(u8, size);
    defer allocator.free(original);
    @memset(original, 0);

    const compressed = try zlib.compress(allocator, .gzip, original);
    defer allocator.free(compressed);

    // Should achieve very good compression
    try std.testing.expect(compressed.len < size / 10);

    const decompressed = try deflate.decompressGzip(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, original, decompressed);
}

test "deflate: binary data" {
    const allocator = std.testing.allocator;

    // Binary data with all byte values
    var original: [256]u8 = undefined;
    for (&original, 0..) |*byte, i| {
        byte.* = @truncate(i);
    }

    const compressed = try zlib.compress(allocator, .gzip, &original);
    defer allocator.free(compressed);

    const decompressed = try deflate.decompressGzip(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, &original, decompressed);
}

test "deflate: unicode text" {
    const allocator = std.testing.allocator;

    const original = "Hello 世界! Привет мир! مرحبا بالعالم! 🌍🌎🌏";

    const compressed = try zlib.compress(allocator, .gzip, original);
    defer allocator.free(compressed);

    const decompressed = try deflate.decompressGzip(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

// =============================================================================
// Streaming Tests
// =============================================================================

test "deflate: streaming decompression from reader" {
    const allocator = std.testing.allocator;

    const original = "Streaming decompression test with reader interface";

    // Compress to buffer
    const compressed = try zlib.compress(allocator, .zlib, original);
    defer allocator.free(compressed);

    // Create reader from compressed data
    var stream = std.io.fixedBufferStream(compressed);
    const reader = stream.reader();

    // Decompress using reader interface
    const decoder = deflate.DeflateDecoder.init(allocator, .zlib);
    const decompressed = try decoder.decompressReader(reader);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

// =============================================================================
// Multiple Blocks Test
// =============================================================================

test "deflate: multiple blocks in stream" {
    const allocator = std.testing.allocator;

    // Create large enough data to potentially span multiple deflate blocks
    var original = std.ArrayList(u8).init(allocator);
    defer original.deinit();

    // Add diverse data that might create different block types
    for (0..100) |_| {
        try original.appendSlice("Repeated text for compression. ");
        try original.appendSlice("AAAAAABBBBBBCCCCCCDDDDDD");
        try original.appendSlice("Random text with various characters: !@#$%^&*()");
    }

    const compressed = try zlib.compress(allocator, .gzip, original.items);
    defer allocator.free(compressed);

    const decompressed = try deflate.decompressGzip(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, original.items, decompressed);
}

// =============================================================================
// Integration with existing zlib module
// =============================================================================

test "deflate: matches zlib.decompress for gzip" {
    const allocator = std.testing.allocator;

    const original = "Test data for comparing deflate and zlib decompression";

    // Compress
    const compressed = try zlib.compress(allocator, .gzip, original);
    defer allocator.free(compressed);

    // Decompress with both methods
    const decompressed_zlib = try zlib.decompress(allocator, .gzip, compressed);
    defer allocator.free(decompressed_zlib);

    const decompressed_deflate = try deflate.decompressGzip(allocator, compressed);
    defer allocator.free(decompressed_deflate);

    // Both should produce the same result
    try std.testing.expectEqualSlices(u8, decompressed_zlib, decompressed_deflate);
    try std.testing.expectEqualStrings(original, decompressed_deflate);
}

test "deflate: matches zlib.decompress for zlib" {
    const allocator = std.testing.allocator;

    const original = "Another test for zlib container";

    // Compress
    const compressed = try zlib.compress(allocator, .zlib, original);
    defer allocator.free(compressed);

    // Decompress with both methods
    const decompressed_zlib = try zlib.decompress(allocator, .zlib, compressed);
    defer allocator.free(decompressed_zlib);

    const decompressed_deflate = try deflate.decompressZlib(allocator, compressed);
    defer allocator.free(decompressed_deflate);

    // Both should produce the same result
    try std.testing.expectEqualSlices(u8, decompressed_zlib, decompressed_deflate);
    try std.testing.expectEqualStrings(original, decompressed_deflate);
}
