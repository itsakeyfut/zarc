const std = @import("std");

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
            var name_bytes = std.array_list.AlignedManaged(u8, null).init(allocator);
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
            var comment_bytes = std.array_list.AlignedManaged(u8, null).init(allocator);
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
        0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03,
    };

    var stream = std.io.fixedBufferStream(&bad_header);
    const result = Header.parse(allocator, stream.reader());

    try std.testing.expectError(error.InvalidGzipMagic, result);
}
