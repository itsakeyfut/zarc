const std = @import("std");

/// Deflate decompression implementation (RFC 1951)
///
/// This module provides Deflate decompression supporting all three block types:
/// 1. Uncompressed blocks (BTYPE=00)
/// 2. Fixed Huffman blocks (BTYPE=01)
/// 3. Dynamic Huffman blocks (BTYPE=10)
///
/// Implementation note:
/// Phase 1: Uses Zig's standard library via zlib wrapper (C library)
/// Phase 2+: Will be replaced with pure Zig implementation for full control
/// Import the zlib module for decompression
const zlib_mod = @import("../zlib.zig");

/// Deflate container format
pub const Container = enum {
    /// Raw deflate stream (no header/footer)
    /// Note: Phase 1 implementation wraps raw deflate with zlib framing
    raw,
    /// Zlib format (RFC 1950): 2-byte header + deflate + 4-byte Adler32
    zlib,
    /// Gzip format (RFC 1952): 10-byte header + deflate + 8-byte footer
    gzip,

    /// Convert to zlib.Format
    /// Returns error.UnsupportedContainer for raw deflate (not implemented in Phase 1)
    fn toZlibFormat(self: Container) !zlib_mod.Format {
        return switch (self) {
            .gzip => .gzip,
            .zlib => .zlib,
            .raw => error.UnsupportedContainer,
        };
    }
};

/// Deflate block type (BTYPE field in block header)
pub const BlockType = enum(u2) {
    /// No compression (BTYPE=00)
    /// Block structure:
    /// - Skip to byte boundary
    /// - LEN (2 bytes): number of data bytes
    /// - NLEN (2 bytes): one's complement of LEN
    /// - Data bytes (LEN bytes)
    uncompressed = 0,

    /// Compressed with fixed Huffman codes (BTYPE=01)
    /// Uses predefined Huffman tables as specified in RFC 1951 section 3.2.6
    /// - Literal/length codes: 0-143 = 8 bits, 144-255 = 9 bits, 256-279 = 7 bits, 280-287 = 8 bits
    /// - Distance codes: all 5 bits
    fixed_huffman = 1,

    /// Compressed with dynamic Huffman codes (BTYPE=10)
    /// Block structure:
    /// - HLIT (5 bits): # of literal/length codes - 257 (257-286)
    /// - HDIST (5 bits): # of distance codes - 1 (1-32)
    /// - HCLEN (4 bits): # of code length codes - 4 (4-19)
    /// - Code lengths for the code length alphabet (3 bits each, HCLEN+4 values)
    /// - Code lengths for literal/length alphabet (encoded using code length alphabet)
    /// - Code lengths for distance alphabet (encoded using code length alphabet)
    /// - Compressed data using the custom Huffman trees
    dynamic_huffman = 2,

    /// Reserved (error)
    reserved = 3,
};

/// Deflate decoder
pub const DeflateDecoder = struct {
    allocator: std.mem.Allocator,
    container: Container,

    /// Initialize a new Deflate decoder
    pub fn init(allocator: std.mem.Allocator, container: Container) DeflateDecoder {
        return .{
            .allocator = allocator,
            .container = container,
        };
    }

    /// Decompress deflate-compressed data
    ///
    /// Parameters:
    ///   - compressed: The compressed data (including container headers/footers if applicable)
    ///
    /// Returns:
    ///   - Allocated slice containing decompressed data
    ///   - Caller owns the returned memory and must free it
    ///
    /// Errors:
    ///   - error.UnsupportedContainer: Raw deflate is not supported in Phase 1
    ///   - error.CompressionFailed: Corrupted or invalid compressed stream
    ///   - error.OutOfMemory: Memory allocation failed
    ///
    /// Note: Phase 1 implementation uses zlib library for decompression
    pub fn decompress(self: DeflateDecoder, compressed: []const u8) ![]u8 {
        const format = try self.container.toZlibFormat();
        return zlib_mod.decompress(self.allocator, format, compressed);
    }

    /// Decompress deflate data from a reader
    ///
    /// This is useful for streaming decompression from files or network streams.
    ///
    /// Parameters:
    ///   - reader: Any reader that provides compressed data
    ///
    /// Returns:
    ///   - Allocated slice containing decompressed data
    ///   - Caller owns the returned memory and must free it
    ///
    /// Note: Reads up to 512 MiB from the reader by default
    pub fn decompressReader(self: DeflateDecoder, reader: anytype) ![]u8 {
        // Read all data from reader first (with reasonable size cap)
        const max_size = 512 * 1024 * 1024; // 512 MiB
        const buf = try reader.readAllAlloc(self.allocator, max_size);
        defer self.allocator.free(buf);

        // Then decompress
        return self.decompress(buf);
    }
};

/// Convenience function: decompress raw deflate data
///
/// Note: Raw deflate is not supported in Phase 1
/// Phase 2+ will handle true raw deflate streams
pub fn decompressRaw(allocator: std.mem.Allocator, compressed: []const u8) ![]u8 {
    _ = allocator;
    _ = compressed;
    return error.UnsupportedContainer;
}

/// Convenience function: decompress zlib data
pub fn decompressZlib(allocator: std.mem.Allocator, compressed: []const u8) ![]u8 {
    const decoder = DeflateDecoder.init(allocator, .zlib);
    return decoder.decompress(compressed);
}

/// Convenience function: decompress gzip data
pub fn decompressGzip(allocator: std.mem.Allocator, compressed: []const u8) ![]u8 {
    const decoder = DeflateDecoder.init(allocator, .gzip);
    return decoder.decompress(compressed);
}

// =============================================================================
// Tests
// =============================================================================

test "DeflateDecoder: zlib format" {
    const allocator = std.testing.allocator;

    const original = "Test data for zlib decompression";

    // Compress using existing zlib module
    const compressed = try zlib_mod.compress(allocator, .zlib, original);
    defer allocator.free(compressed);

    // Decompress using our decoder
    const decompressed = try decompressZlib(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

test "DeflateDecoder: gzip format" {
    const allocator = std.testing.allocator;

    const original = "Test data for gzip decompression with Deflate";

    // Compress using existing zlib module
    const compressed = try zlib_mod.compress(allocator, .gzip, original);
    defer allocator.free(compressed);

    // Decompress using our decoder
    const decompressed = try decompressGzip(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

test "DeflateDecoder: empty data" {
    const allocator = std.testing.allocator;

    const original = "";

    const compressed = try zlib_mod.compress(allocator, .gzip, original);
    defer allocator.free(compressed);

    const decompressed = try decompressGzip(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualStrings(original, decompressed);
}

test "DeflateDecoder: large data" {
    const allocator = std.testing.allocator;

    const size = 100 * 1024;
    const original = try allocator.alloc(u8, size);
    defer allocator.free(original);

    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();
    random.bytes(original);

    const compressed = try zlib_mod.compress(allocator, .gzip, original);
    defer allocator.free(compressed);

    const decompressed = try decompressGzip(allocator, compressed);
    defer allocator.free(decompressed);

    try std.testing.expectEqualSlices(u8, original, decompressed);
}
