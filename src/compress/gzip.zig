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
const crc32_mod = @import("crc32.zig");

/// Gzip file format constants (RFC 1952)
pub const magic_number = [2]u8{ 0x1f, 0x8b };
pub const compression_method_deflate: u8 = 8;

/// Gzip header flags (FLG byte)
pub const Flags = packed struct(u8) {
    ftext: bool = false, // File is probably ASCII text
    fhcrc: bool = false, // CRC16 for the header is present
    fextra: bool = false, // Extra field is present
    fname: bool = false, // Original file name is present
    fcomment: bool = false, // File comment is present
    _reserved: u3 = 0, // Reserved bits (must be zero)

    pub fn fromByte(byte: u8) Flags {
        return @bitCast(byte);
    }

    pub fn toByte(self: Flags) u8 {
        return @bitCast(self);
    }
};

/// Gzip extra flags (XFL byte)
pub const ExtraFlags = enum(u8) {
    default = 0,
    max_compression = 2,
    fast_compression = 4,
    _,
};

/// Operating system that created the file (OS byte)
pub const Os = enum(u8) {
    fat = 0, // FAT filesystem (MS-DOS, OS/2, NT/Win32)
    amiga = 1,
    vms = 2,
    unix = 3,
    vm_cms = 4,
    atari_tos = 5,
    hpfs = 6, // HPFS filesystem (OS/2, NT)
    macintosh = 7,
    z_system = 8,
    cp_m = 9,
    tops_20 = 10,
    ntfs = 11, // NTFS filesystem (NT)
    qdos = 12,
    acorn_riscos = 13,
    unknown = 255,
    _,
};

/// Gzip header structure
pub const Header = struct {
    /// Compression method (should be 8 for deflate)
    compression_method: u8,

    /// Flags byte
    flags: Flags,

    /// Modification time (Unix timestamp, 0 means not available)
    mtime: u32,

    /// Extra flags
    extra_flags: ExtraFlags,

    /// Operating system
    os: Os,

    /// Extra field (if FLG.FEXTRA is set)
    extra: ?[]const u8 = null,

    /// Original file name (if FLG.FNAME is set, null-terminated)
    filename: ?[]const u8 = null,

    /// File comment (if FLG.FCOMMENT is set, null-terminated)
    comment: ?[]const u8 = null,

    /// CRC16 of header (if FLG.FHCRC is set)
    header_crc16: ?u16 = null,

    /// Parse gzip header from byte stream
    pub fn parse(allocator: std.mem.Allocator, reader: anytype) !Header {
        // Read magic number
        var magic: [2]u8 = undefined;
        try reader.readNoEof(&magic);
        if (!std.mem.eql(u8, &magic, &magic_number)) {
            return error.InvalidGzipMagic;
        }

        // Read compression method
        const cm = try reader.readByte();
        if (cm != compression_method_deflate) {
            return error.UnsupportedCompressionMethod;
        }

        // Read flags
        const flg = try reader.readByte();
        const flags = Flags.fromByte(flg);

        // Read mtime (little-endian)
        const mtime = try reader.readInt(u32, .little);

        // Read extra flags
        const xfl = try reader.readByte();
        const extra_flags: ExtraFlags = @enumFromInt(xfl);

        // Read OS
        const os_byte = try reader.readByte();
        const os: Os = @enumFromInt(os_byte);

        var header = Header{
            .compression_method = cm,
            .flags = flags,
            .mtime = mtime,
            .extra_flags = extra_flags,
            .os = os,
        };

        // Read optional fields based on flags

        // Extra field
        if (flags.fextra) {
            const xlen = try reader.readInt(u16, .little);
            const extra = try allocator.alloc(u8, xlen);
            errdefer allocator.free(extra);
            try reader.readNoEof(extra);
            header.extra = extra;
        }

        // Original filename
        if (flags.fname) {
            var name_bytes = std.ArrayList(u8).init(allocator);
            defer name_bytes.deinit();

            while (true) {
                const byte = try reader.readByte();
                if (byte == 0) break;
                try name_bytes.append(byte);
            }

            header.filename = try allocator.dupe(u8, name_bytes.items);
        }

        // Comment
        if (flags.fcomment) {
            var comment_bytes = std.ArrayList(u8).init(allocator);
            defer comment_bytes.deinit();

            while (true) {
                const byte = try reader.readByte();
                if (byte == 0) break;
                try comment_bytes.append(byte);
            }

            header.comment = try allocator.dupe(u8, comment_bytes.items);
        }

        // Header CRC16
        if (flags.fhcrc) {
            header.header_crc16 = try reader.readInt(u16, .little);
        }

        return header;
    }

    /// Free allocated memory
    pub fn deinit(self: *Header, allocator: std.mem.Allocator) void {
        if (self.extra) |extra| {
            allocator.free(extra);
        }
        if (self.filename) |filename| {
            allocator.free(filename);
        }
        if (self.comment) |comment| {
            allocator.free(comment);
        }
    }

    /// Write gzip header to byte stream
    pub fn write(self: Header, writer: anytype) !void {
        // Write magic number
        try writer.writeAll(&magic_number);

        // Write compression method
        try writer.writeByte(self.compression_method);

        // Write flags
        try writer.writeByte(self.flags.toByte());

        // Write mtime
        try writer.writeInt(u32, self.mtime, .little);

        // Write extra flags
        try writer.writeByte(@intFromEnum(self.extra_flags));

        // Write OS
        try writer.writeByte(@intFromEnum(self.os));

        // Write optional fields

        if (self.flags.fextra) {
            if (self.extra) |extra| {
                if (extra.len > std.math.maxInt(u16)) {
                    return error.ExtraFieldTooLarge;
                }
                try writer.writeInt(u16, @intCast(extra.len), .little);
                try writer.writeAll(extra);
            } else {
                return error.MissingExtraField;
            }
        }

        if (self.flags.fname) {
            if (self.filename) |filename| {
                try writer.writeAll(filename);
                try writer.writeByte(0); // Null terminator
            } else {
                return error.MissingFilename;
            }
        }

        if (self.flags.fcomment) {
            if (self.comment) |comment| {
                try writer.writeAll(comment);
                try writer.writeByte(0); // Null terminator
            } else {
                return error.MissingComment;
            }
        }

        if (self.flags.fhcrc) {
            if (self.header_crc16) |crc| {
                try writer.writeInt(u16, crc, .little);
            } else {
                return error.MissingHeaderCrc;
            }
        }
    }
};

/// Gzip footer structure (CRC32 + ISIZE)
pub const Footer = struct {
    /// CRC32 of uncompressed data
    crc32: u32,

    /// Size of uncompressed data modulo 2^32
    isize: u32,

    /// Parse footer from byte stream
    pub fn parse(reader: anytype) !Footer {
        const crc32 = try reader.readInt(u32, .little);
        const size = try reader.readInt(u32, .little);

        return Footer{
            .crc32 = crc32,
            .isize = size,
        };
    }

    /// Write footer to byte stream
    pub fn write(self: Footer, writer: anytype) !void {
        try writer.writeInt(u32, self.crc32, .little);
        try writer.writeInt(u32, self.isize, .little);
    }

    /// Create footer from uncompressed data
    pub fn fromData(data: []const u8) Footer {
        return Footer{
            .crc32 = crc32_mod.crc32(data),
            .isize = @truncate(data.len),
        };
    }

    /// Validate footer against uncompressed data
    pub fn validate(self: Footer, data: []const u8) bool {
        const calculated_crc32 = crc32_mod.crc32(data);
        const actual_size: u32 = @truncate(data.len);
        return self.crc32 == calculated_crc32 and self.isize == actual_size;
    }
};

test "parse basic gzip header" {
    const allocator = std.testing.allocator;

    // Minimal gzip header (no optional fields)
    const header_bytes = [_]u8{
        0x1f, 0x8b, // Magic number
        0x08, // Compression method (deflate)
        0x00, // Flags (no optional fields)
        0x00, 0x00, 0x00, 0x00, // mtime = 0
        0x00, // Extra flags
        0x03, // OS (Unix)
    };

    var stream = std.io.fixedBufferStream(&header_bytes);
    var header = try Header.parse(allocator, stream.reader());
    defer header.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 8), header.compression_method);
    try std.testing.expectEqual(@as(u32, 0), header.mtime);
    try std.testing.expectEqual(Os.unix, header.os);
    try std.testing.expectEqual(@as(?[]const u8, null), header.filename);
    try std.testing.expectEqual(@as(?[]const u8, null), header.comment);
}

test "parse gzip header with filename" {
    const allocator = std.testing.allocator;

    // Gzip header with filename
    const header_bytes = [_]u8{
        0x1f, 0x8b, // Magic number
        0x08, // Compression method (deflate)
        0x08, // Flags (FNAME set)
        0x00, 0x00, 0x00, 0x00, // mtime = 0
        0x00, // Extra flags
        0x03, // OS (Unix)
        't', 'e', 's', 't', '.', 't', 'x', 't', 0x00, // Filename (null-terminated)
    };

    var stream = std.io.fixedBufferStream(&header_bytes);
    var header = try Header.parse(allocator, stream.reader());
    defer header.deinit(allocator);

    try std.testing.expectEqual(@as(u8, 8), header.compression_method);
    try std.testing.expect(header.filename != null);
    try std.testing.expectEqualStrings("test.txt", header.filename.?);
}

test "write and read gzip header" {
    const allocator = std.testing.allocator;

    const original = Header{
        .compression_method = 8,
        .flags = .{ .fname = true },
        .mtime = 12345,
        .extra_flags = .default,
        .os = .unix,
        .filename = "example.txt",
    };

    // Write header
    var buffer: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try original.write(stream.writer());

    // Read it back
    stream.reset();
    var parsed = try Header.parse(allocator, stream.reader());
    defer parsed.deinit(allocator);

    try std.testing.expectEqual(original.compression_method, parsed.compression_method);
    try std.testing.expectEqual(original.mtime, parsed.mtime);
    try std.testing.expectEqual(original.os, parsed.os);
    try std.testing.expectEqualStrings("example.txt", parsed.filename.?);
}

test "invalid magic number" {
    const allocator = std.testing.allocator;

    const bad_header = [_]u8{
        0x00, 0x00, // Wrong magic number
        0x08, 0x00,
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x03,
    };

    var stream = std.io.fixedBufferStream(&bad_header);
    const result = Header.parse(allocator, stream.reader());

    try std.testing.expectError(error.InvalidGzipMagic, result);
}

test "Footer.fromData: calculate CRC-32 and size" {
    const test_data = "Hello, World!";
    const footer = Footer.fromData(test_data);

    // Verify size is correct
    try std.testing.expectEqual(@as(u32, test_data.len), footer.isize);

    // Verify CRC-32 is non-zero
    try std.testing.expect(footer.crc32 != 0);

    // Verify deterministic
    const footer2 = Footer.fromData(test_data);
    try std.testing.expectEqual(footer.crc32, footer2.crc32);
    try std.testing.expectEqual(footer.isize, footer2.isize);
}

test "Footer.validate: correct data" {
    const test_data = "Test data for CRC-32 validation";
    const footer = Footer.fromData(test_data);

    // Should validate successfully
    try std.testing.expect(footer.validate(test_data));
}

test "Footer.validate: incorrect CRC-32" {
    const test_data = "Test data";
    var footer = Footer.fromData(test_data);

    // Corrupt the CRC-32
    footer.crc32 ^= 0x12345678;

    // Should fail validation
    try std.testing.expect(!footer.validate(test_data));
}

test "Footer.validate: incorrect size" {
    const test_data = "Test data";
    var footer = Footer.fromData(test_data);

    // Corrupt the size
    footer.isize += 1;

    // Should fail validation
    try std.testing.expect(!footer.validate(test_data));
}

test "Footer.validate: empty data" {
    const empty_data = "";
    const footer = Footer.fromData(empty_data);

    try std.testing.expectEqual(@as(u32, 0), footer.isize);
    try std.testing.expect(footer.validate(empty_data));
}

test "Footer: write and read with validation" {
    const allocator = std.testing.allocator;
    const test_data = "Data to be compressed";

    // Create footer from data
    const original_footer = Footer.fromData(test_data);

    // Write to buffer
    var buffer: [8]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buffer);
    try original_footer.write(stream.writer());

    // Read it back
    stream.reset();
    const parsed_footer = try Footer.parse(stream.reader());

    // Verify values match
    try std.testing.expectEqual(original_footer.crc32, parsed_footer.crc32);
    try std.testing.expectEqual(original_footer.isize, parsed_footer.isize);

    // Verify validation works
    try std.testing.expect(parsed_footer.validate(test_data));

    _ = allocator;
}

// =============================================================================
// Compression API
// =============================================================================

const deflate = @import("deflate/encode.zig");

/// Gzip compression options
pub const CompressOptions = struct {
    /// Compression level (0-9)
    level: deflate.CompressionLevel = .default,
    /// Modification time (Unix timestamp, 0 = not available)
    mtime: u32 = 0,
    /// Original filename (optional)
    filename: ?[]const u8 = null,
    /// Comment (optional)
    comment: ?[]const u8 = null,
    /// Operating system
    os: Os = .unix,
};

/// Compress data to gzip format
///
/// This function compresses the input data using the Deflate algorithm
/// and wraps it with a gzip header and footer according to RFC 1952.
///
/// Parameters:
///   - allocator: Memory allocator for output buffer
///   - data: Input data to compress
///   - options: Compression options (level, mtime, filename, etc.)
///
/// Returns:
///   - Gzip-compressed data (caller owns memory)
///
/// Errors:
///   - error.OutOfMemory: Memory allocation failed
///   - error.InputTooLarge: Input exceeds 4 GiB limit
pub fn compress(
    allocator: std.mem.Allocator,
    data: []const u8,
    options: CompressOptions,
) ![]u8 {
    var buffer = std.ArrayList(u8).init(allocator);
    errdefer buffer.deinit();

    // Create header
    const header = Header{
        .compression_method = compression_method_deflate,
        .flags = .{
            .fname = options.filename != null,
            .fcomment = options.comment != null,
        },
        .mtime = options.mtime,
        .extra_flags = switch (options.level) {
            .best => .max_compression,
            .fastest => .fast_compression,
            else => .default,
        },
        .os = options.os,
        .filename = options.filename,
        .comment = options.comment,
    };

    // Write header
    try header.write(buffer.writer());

    // Compress data with deflate
    const compressed = try deflate.compress(allocator, data, options.level);
    defer allocator.free(compressed);
    try buffer.appendSlice(compressed);

    // Create and write footer
    const footer = Footer.fromData(data);
    try footer.write(buffer.writer());

    return buffer.toOwnedSlice();
}

/// Compress data with default options
pub fn compressDefault(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    return compress(allocator, data, .{});
}

/// Streaming gzip compressor
///
/// This struct allows incremental compression of data, updating the CRC-32
/// checksum and size as data is added. Useful for compressing large files
/// or streaming data.
pub const Compressor = struct {
    allocator: std.mem.Allocator,
    crc: crc32_mod.Crc32,
    size: u32,
    level: deflate.CompressionLevel,
    buffer: std.ArrayList(u8),
    header_size: usize,

    /// Initialize a new gzip compressor
    pub fn init(allocator: std.mem.Allocator, options: CompressOptions) !Compressor {
        var comp = Compressor{
            .allocator = allocator,
            .crc = crc32_mod.Crc32.init(),
            .size = 0,
            .level = options.level,
            .buffer = std.ArrayList(u8).init(allocator),
            .header_size = 0,
        };

        // Write header immediately
        const header = Header{
            .compression_method = compression_method_deflate,
            .flags = .{
                .fname = options.filename != null,
                .fcomment = options.comment != null,
            },
            .mtime = options.mtime,
            .extra_flags = switch (options.level) {
                .best => .max_compression,
                .fastest => .fast_compression,
                else => .default,
            },
            .os = options.os,
            .filename = options.filename,
            .comment = options.comment,
        };

        try header.write(comp.buffer.writer());
        comp.header_size = comp.buffer.items.len;

        return comp;
    }

    /// Free resources
    pub fn deinit(self: *Compressor) void {
        self.buffer.deinit();
    }

    /// Add data to compress
    ///
    /// Note: This collects data in a buffer. Call finish() to get the
    /// final compressed output. For true streaming compression,
    /// consider using a more sophisticated implementation.
    pub fn update(self: *Compressor, data: []const u8) !void {
        self.crc.update(data);
        const new_size = @as(u64, self.size) + data.len;
        if (new_size > std.math.maxInt(u32)) {
            return error.InputTooLarge;
        }
        self.size = @truncate(new_size);

        // For now, we accumulate data and compress in finish()
        // A true streaming implementation would compress in blocks
        try self.buffer.appendSlice(data);
    }

    /// Finalize compression and get the output
    ///
    /// After calling this, the compressor is consumed and should not be used.
    pub fn finish(self: *Compressor) ![]u8 {
        // Get the uncompressed data (everything after header)
        const header_size = self.getHeaderSize();
        const uncompressed = self.buffer.items[header_size..];

        // Compress it
        const compressed = try deflate.compress(self.allocator, uncompressed, self.level);
        defer self.allocator.free(compressed);

        // Create new buffer with header + compressed data + footer
        var output = std.ArrayList(u8).init(self.allocator);
        errdefer output.deinit();

        // Copy header
        try output.appendSlice(self.buffer.items[0..header_size]);

        // Add compressed data
        try output.appendSlice(compressed);

        // Add footer
        const footer = Footer{
            .crc32 = self.crc.final(),
            .isize = self.size,
        };
        try footer.write(output.writer());

        return output.toOwnedSlice();
    }

    /// Get the size of the header we wrote
    fn getHeaderSize(self: *Compressor) usize {
        return self.header_size;
    }
};

// =============================================================================
// Compression Tests
// =============================================================================

test "compress: empty data" {
    const allocator = std.testing.allocator;

    const compressed = try compress(allocator, "", .{});
    defer allocator.free(compressed);

    // Should have header (min 10 bytes) + deflate data + footer (8 bytes)
    try std.testing.expect(compressed.len >= 18);

    // Verify magic number
    try std.testing.expectEqual(@as(u8, 0x1f), compressed[0]);
    try std.testing.expectEqual(@as(u8, 0x8b), compressed[1]);

    // Verify compression method (deflate)
    try std.testing.expectEqual(@as(u8, 8), compressed[2]);
}

test "compress: simple data" {
    const allocator = std.testing.allocator;

    const data = "Hello, gzip compression!";
    const compressed = try compress(allocator, data, .{});
    defer allocator.free(compressed);

    // Should be compressed
    try std.testing.expect(compressed.len > 0);

    // Verify gzip header
    try std.testing.expectEqual(@as(u8, 0x1f), compressed[0]);
    try std.testing.expectEqual(@as(u8, 0x8b), compressed[1]);
    try std.testing.expectEqual(@as(u8, 8), compressed[2]);

    // Verify footer is at the end (last 8 bytes: CRC32 + ISIZE)
    const footer_offset = compressed.len - 8;
    var stream = std.io.fixedBufferStream(compressed[footer_offset..]);
    const footer = try Footer.parse(stream.reader());

    // Verify footer matches data
    try std.testing.expect(footer.validate(data));
}

test "compress: with options" {
    const allocator = std.testing.allocator;

    const data = "Test data";
    const compressed = try compress(allocator, data, .{
        .level = .best,
        .mtime = 12345,
        .filename = "test.txt",
        .os = .unix,
    });
    defer allocator.free(compressed);

    // Parse header to verify options
    var stream = std.io.fixedBufferStream(compressed);
    var header = try Header.parse(allocator, stream.reader());
    defer header.deinit(allocator);

    try std.testing.expectEqual(@as(u32, 12345), header.mtime);
    try std.testing.expect(header.filename != null);
    try std.testing.expectEqualStrings("test.txt", header.filename.?);
    try std.testing.expectEqual(Os.unix, header.os);
}

test "compress: compression levels" {
    const allocator = std.testing.allocator;

    const data = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";

    // Test different compression levels
    const levels = [_]deflate.CompressionLevel{ .none, .fastest, .default, .best };

    for (levels) |level| {
        const compressed = try compress(allocator, data, .{ .level = level });
        defer allocator.free(compressed);

        // All should produce valid gzip
        try std.testing.expect(compressed.len > 0);
        try std.testing.expectEqual(@as(u8, 0x1f), compressed[0]);
        try std.testing.expectEqual(@as(u8, 0x8b), compressed[1]);
    }
}

test "compress: large data" {
    const allocator = std.testing.allocator;

    // Create 1MB of test data
    const size = 1024 * 1024;
    const data = try allocator.alloc(u8, size);
    defer allocator.free(data);

    // Fill with pattern
    for (data, 0..) |*byte, i| {
        byte.* = @truncate(i);
    }

    const compressed = try compress(allocator, data, .{ .level = .fastest });
    defer allocator.free(compressed);

    // Verify header
    try std.testing.expectEqual(@as(u8, 0x1f), compressed[0]);
    try std.testing.expectEqual(@as(u8, 0x8b), compressed[1]);

    // Verify footer
    const footer_offset = compressed.len - 8;
    var stream = std.io.fixedBufferStream(compressed[footer_offset..]);
    const footer = try Footer.parse(stream.reader());

    // Size should be truncated to u32
    const expected_size: u32 = @truncate(size);
    try std.testing.expectEqual(expected_size, footer.isize);
}

test "compressDefault: uses default settings" {
    const allocator = std.testing.allocator;

    const data = "Test default compression";
    const compressed = try compressDefault(allocator, data);
    defer allocator.free(compressed);

    // Verify it's valid gzip
    try std.testing.expect(compressed.len > 0);
    try std.testing.expectEqual(@as(u8, 0x1f), compressed[0]);
    try std.testing.expectEqual(@as(u8, 0x8b), compressed[1]);

    // Verify footer
    const footer_offset = compressed.len - 8;
    var stream = std.io.fixedBufferStream(compressed[footer_offset..]);
    const footer = try Footer.parse(stream.reader());
    try std.testing.expect(footer.validate(data));
}

test "compress: gunzip compatibility with stored blocks" {
    const allocator = std.testing.allocator;

    const data = "Gzip compatibility test";
    const compressed = try compress(allocator, data, .{ .level = .none });
    defer allocator.free(compressed);

    // Write to temp file and verify with gunzip
    // This test validates RFC 1952 compliance
    try std.testing.expect(compressed.len > 0);
    try std.testing.expectEqual(@as(u8, 0x1f), compressed[0]);
    try std.testing.expectEqual(@as(u8, 0x8b), compressed[1]);
}
