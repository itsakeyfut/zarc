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
const util = @import("../../core/util.zig");
const errors = @import("../../core/errors.zig");
const types = @import("../../core/types.zig");

/// POSIX ustar header format
/// Reference: POSIX.1-1988 (ustar), POSIX.1-2001 (PAX)
///
/// The tar archive format uses 512-byte blocks. Each file entry consists of:
/// 1. Header block (512 bytes)
/// 2. File data (padded to 512-byte boundary)
/// 3. End-of-archive marker (two 512-byte zero blocks)
pub const TarHeader = struct {
    /// File name (100 bytes, null-terminated)
    name: [100]u8,

    /// File mode/permissions (8 bytes, octal string)
    /// Example: "0000644\0" for 0o644 (rw-r--r--)
    mode: [8]u8,

    /// User ID (8 bytes, octal string)
    uid: [8]u8,

    /// Group ID (8 bytes, octal string)
    gid: [8]u8,

    /// File size in bytes (12 bytes, octal string)
    /// Maximum: 8GB (0o77777777777)
    size: [12]u8,

    /// Modification time (12 bytes, octal string, Unix timestamp)
    mtime: [12]u8,

    /// Header checksum (8 bytes, octal string)
    /// Calculated as sum of all header bytes, treating checksum field as spaces
    checksum: [8]u8,

    /// Type flag (1 byte)
    /// '0' or '\0': Regular file
    /// '1': Hard link
    /// '2': Symbolic link
    /// '3': Character device
    /// '4': Block device
    /// '5': Directory
    /// '6': FIFO/named pipe
    /// '7': Reserved
    typeflag: u8,

    /// Link target name (100 bytes, null-terminated)
    /// Used for symbolic links and hard links
    linkname: [100]u8,

    /// USTAR magic string (6 bytes)
    /// "ustar\0" for POSIX ustar format
    magic: [6]u8,

    /// USTAR version (2 bytes)
    /// "00" for POSIX ustar
    version: [2]u8,

    /// User name (32 bytes, null-terminated)
    uname: [32]u8,

    /// Group name (32 bytes, null-terminated)
    gname: [32]u8,

    /// Device major number (8 bytes, octal string)
    /// Used for character and block devices
    devmajor: [8]u8,

    /// Device minor number (8 bytes, octal string)
    /// Used for character and block devices
    devminor: [8]u8,

    /// File name prefix (155 bytes, null-terminated)
    /// Used for long file names: prefix + "/" + name
    prefix: [155]u8,

    /// Padding to reach 512 bytes
    padding: [12]u8,

    /// TAR header block size (512 bytes)
    pub const BLOCK_SIZE: usize = 512;

    /// Checksum field offset in header
    pub const CHECKSUM_OFFSET: usize = 148;

    /// Checksum field size
    pub const CHECKSUM_SIZE: usize = 8;

    /// Type flags for different entry types
    pub const TypeFlag = struct {
        pub const REGULAR: u8 = '0';
        pub const REGULAR_ALT: u8 = '\x00'; // Alternative for regular file
        pub const HARD_LINK: u8 = '1';
        pub const SYMLINK: u8 = '2';
        pub const CHAR_DEVICE: u8 = '3';
        pub const BLOCK_DEVICE: u8 = '4';
        pub const DIRECTORY: u8 = '5';
        pub const FIFO: u8 = '6';
        pub const RESERVED: u8 = '7';

        /// GNU tar extensions
        pub const GNU_LONG_NAME: u8 = 'L';
        pub const GNU_LONG_LINK: u8 = 'K';
    };

    /// Parse tar header from 512-byte block
    ///
    /// Parameters:
    ///   - data: 512-byte header block
    ///
    /// Returns:
    ///   - Parsed TarHeader struct
    ///
    /// Errors:
    ///   - error.CorruptedHeader: Header magic is not "ustar", checksum parsing failed, or checksum verification failed
    ///
    /// Example:
    /// ```zig
    /// var header_data: [512]u8 = ...;
    /// const header = try TarHeader.parse(&header_data);
    /// ```
    pub fn parse(data: *const [BLOCK_SIZE]u8) errors.FormatError!TarHeader {
        // Copy data to header struct
        var header: TarHeader = undefined;
        @memcpy(@as([*]u8, @ptrCast(&header))[0..BLOCK_SIZE], data);

        // Verify USTAR magic
        // Accept both POSIX ustar ("ustar\x00","00") and GNU old tar ("ustar "," \x00" or "  ")
        const is_posix_ustar = std.mem.eql(u8, header.magic[0..6], "ustar\x00") and
            std.mem.eql(u8, header.version[0..2], "00");
        const is_gnu_tar = std.mem.eql(u8, header.magic[0..6], "ustar ") and
            (std.mem.eql(u8, header.version[0..2], "  ") or
                std.mem.eql(u8, header.version[0..2], " \x00"));

        if (!is_posix_ustar and !is_gnu_tar) {
            return error.CorruptedHeader;
        }

        // Verify checksum
        const stored_checksum_u64 = util.parseOctal(&header.checksum) catch {
            return error.CorruptedHeader;
        };

        const calculated_checksum = calculateChecksum(data);
        const stored_checksum: u32 = @intCast(stored_checksum_u64);
        if (stored_checksum != calculated_checksum) {
            return error.CorruptedHeader;
        }

        return header;
    }

    /// Get file name from header
    ///
    /// Combines prefix and name fields according to POSIX ustar spec.
    /// If prefix is non-empty, result is: prefix + "/" + name
    /// Otherwise, result is just: name
    ///
    /// Parameters:
    ///   - allocator: Memory allocator
    ///
    /// Returns:
    ///   - Full file path (caller must free)
    ///
    /// Example:
    /// ```zig
    /// const name = try header.getName(allocator);
    /// defer allocator.free(name);
    /// ```
    pub fn getName(self: *const TarHeader, allocator: std.mem.Allocator) ![]const u8 {
        const name_len = std.mem.indexOfScalar(u8, &self.name, 0) orelse self.name.len;
        const name_str = self.name[0..name_len];

        // Check if prefix is used
        const prefix_len = std.mem.indexOfScalar(u8, &self.prefix, 0) orelse self.prefix.len;
        if (prefix_len > 0) {
            const prefix_str = self.prefix[0..prefix_len];
            return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ prefix_str, name_str });
        }

        return try allocator.dupe(u8, name_str);
    }

    /// Get file size from header
    ///
    /// Returns:
    ///   - File size in bytes
    ///
    /// Errors:
    ///   - error.InvalidCharacter: Invalid octal string
    ///   - error.Overflow: Size exceeds u64 range
    pub fn getSize(self: *const TarHeader) !u64 {
        return util.parseOctal(&self.size);
    }

    /// Get file mode/permissions from header
    ///
    /// Returns:
    ///   - File mode (e.g., 0o644, 0o755)
    ///
    /// Errors:
    ///   - error.InvalidCharacter: Invalid octal string
    ///   - error.Overflow: Mode exceeds u64 range
    pub fn getMode(self: *const TarHeader) !u32 {
        const mode = try util.parseOctal(&self.mode);
        return @intCast(mode);
    }

    /// Get modification time from header
    ///
    /// Returns:
    ///   - Unix timestamp (seconds since epoch)
    ///
    /// Errors:
    ///   - error.InvalidCharacter: Invalid octal string
    ///   - error.Overflow: Time exceeds i64 range
    pub fn getMtime(self: *const TarHeader) !i64 {
        const mtime = try util.parseOctal(&self.mtime);
        return @intCast(mtime);
    }

    /// Get user ID from header
    ///
    /// Returns:
    ///   - User ID
    ///
    /// Errors:
    ///   - error.InvalidCharacter: Invalid octal string
    ///   - error.Overflow: UID exceeds u64 range
    pub fn getUid(self: *const TarHeader) !u32 {
        const uid = try util.parseOctal(&self.uid);
        return @intCast(uid);
    }

    /// Get group ID from header
    ///
    /// Returns:
    ///   - Group ID
    ///
    /// Errors:
    ///   - error.InvalidCharacter: Invalid octal string
    ///   - error.Overflow: GID exceeds u64 range
    pub fn getGid(self: *const TarHeader) !u32 {
        const gid = try util.parseOctal(&self.gid);
        return @intCast(gid);
    }

    /// Get user name from header
    ///
    /// Returns:
    ///   - User name as string slice (may be empty)
    pub fn getUname(self: *const TarHeader) []const u8 {
        const len = std.mem.indexOfScalar(u8, &self.uname, 0) orelse self.uname.len;
        return self.uname[0..len];
    }

    /// Get group name from header
    ///
    /// Returns:
    ///   - Group name as string slice (may be empty)
    pub fn getGname(self: *const TarHeader) []const u8 {
        const len = std.mem.indexOfScalar(u8, &self.gname, 0) orelse self.gname.len;
        return self.gname[0..len];
    }

    /// Get link target name from header
    ///
    /// Returns:
    ///   - Link target path (for symlinks and hard links)
    pub fn getLinkname(self: *const TarHeader) []const u8 {
        const len = std.mem.indexOfScalar(u8, &self.linkname, 0) orelse self.linkname.len;
        return self.linkname[0..len];
    }

    /// Get entry type from type flag
    ///
    /// Returns:
    ///   - EntryType enum value
    pub fn getEntryType(self: *const TarHeader) types.EntryType {
        return switch (self.typeflag) {
            TypeFlag.REGULAR, TypeFlag.REGULAR_ALT => .file,
            TypeFlag.HARD_LINK => .hardlink,
            TypeFlag.SYMLINK => .symlink,
            TypeFlag.CHAR_DEVICE => .char_device,
            TypeFlag.BLOCK_DEVICE => .block_device,
            TypeFlag.DIRECTORY => .directory,
            TypeFlag.FIFO => .fifo,
            else => .file, // Default to regular file
        };
    }

    /// Convert header to Entry struct
    ///
    /// Parameters:
    ///   - allocator: Memory allocator
    ///
    /// Returns:
    ///   - Entry struct with metadata
    ///
    /// Errors:
    ///   - error.InvalidCharacter: Invalid octal string in header
    ///   - error.Overflow: Value exceeds range
    ///   - error.OutOfMemory: Failed to allocate memory
    ///
    /// Example:
    /// ```zig
    /// const entry = try header.toEntry(allocator);
    /// defer allocator.free(entry.path);
    /// ```
    pub fn toEntry(self: *const TarHeader, allocator: std.mem.Allocator) !types.Entry {
        const path = try self.getName(allocator);
        errdefer allocator.free(path);

        const link_target = if (self.typeflag == TypeFlag.SYMLINK or self.typeflag == TypeFlag.HARD_LINK)
            try allocator.dupe(u8, self.getLinkname())
        else
            try allocator.alloc(u8, 0);
        errdefer allocator.free(link_target);

        return types.Entry{
            .path = path,
            .entry_type = self.getEntryType(),
            .size = try self.getSize(),
            .mode = try self.getMode(),
            .mtime = try self.getMtime(),
            .uid = try self.getUid(),
            .gid = try self.getGid(),
            .uname = try allocator.dupe(u8, self.getUname()),
            .gname = try allocator.dupe(u8, self.getGname()),
            .link_target = link_target,
        };
    }
};

/// Calculate tar header checksum
///
/// The checksum is calculated as the sum of all bytes in the header,
/// treating the checksum field (bytes 148-155) as spaces (0x20).
///
/// Parameters:
///   - data: 512-byte header block
///
/// Returns:
///   - Calculated checksum value
///
/// Example:
/// ```zig
/// var header_data: [512]u8 = ...;
/// const checksum = calculateChecksum(&header_data);
/// ```
pub fn calculateChecksum(data: *const [TarHeader.BLOCK_SIZE]u8) u32 {
    var sum: u32 = 0;

    // Sum bytes before checksum field (0-147)
    for (data[0..TarHeader.CHECKSUM_OFFSET]) |byte| {
        sum += byte;
    }

    // Add spaces for checksum field (148-155)
    sum += ' ' * TarHeader.CHECKSUM_SIZE;

    // Sum bytes after checksum field (156-511)
    const after_checksum_offset = TarHeader.CHECKSUM_OFFSET + TarHeader.CHECKSUM_SIZE;
    for (data[after_checksum_offset..]) |byte| {
        sum += byte;
    }

    return sum;
}

/// Create tar header from entry metadata
///
/// Parameters:
///   - entry: Entry metadata
///   - allocator: Memory allocator (unused, for future extensions)
///
/// Returns:
///   - Initialized TarHeader struct
///
/// Errors:
///   - error.FilenameTooLong: File name exceeds tar limits (>255 chars total, >155 prefix, or >100 link target)
///
/// Example:
/// ```zig
/// const header = try createHeader(&entry, allocator);
/// ```
pub fn createHeader(entry: *const types.Entry, allocator: std.mem.Allocator) !TarHeader {
    _ = allocator; // Reserved for future use

    var header: TarHeader = std.mem.zeroes(TarHeader);

    // Set file name (handle long names with prefix)
    if (entry.path.len > 100) {
        // Try to split path into prefix and name
        if (entry.path.len > 255) {
            return error.FilenameTooLong; // TODO: Use GNU long name extension
        }

        const separator_pos = blk: {
            var pos = entry.path.len - 100;
            while (pos < entry.path.len) : (pos += 1) {
                if (entry.path[pos] == '/') {
                    break :blk pos;
                }
            }
            return error.FilenameTooLong;
        };

        const prefix_str = entry.path[0..separator_pos];
        const name_str = entry.path[separator_pos + 1 ..];

        if (prefix_str.len > 155) {
            return error.FilenameTooLong;
        }

        @memcpy(header.prefix[0..prefix_str.len], prefix_str);
        @memcpy(header.name[0..name_str.len], name_str);
    } else {
        @memcpy(header.name[0..entry.path.len], entry.path);
    }

    // Set file mode (7 octal digits + NUL)
    _ = try std.fmt.bufPrint(header.mode[0..7], "{o:0>7}", .{entry.mode});
    header.mode[7] = 0;

    // Set UID and GID (7 octal digits + NUL)
    _ = try std.fmt.bufPrint(header.uid[0..7], "{o:0>7}", .{entry.uid});
    header.uid[7] = 0;
    _ = try std.fmt.bufPrint(header.gid[0..7], "{o:0>7}", .{entry.gid});
    header.gid[7] = 0;

    // Set file size (11 octal digits + NUL)
    _ = try std.fmt.bufPrint(header.size[0..11], "{o:0>11}", .{entry.size});
    header.size[11] = 0;

    // Set modification time (11 octal digits + NUL, cast to u64 to avoid sign prefix)
    _ = try std.fmt.bufPrint(header.mtime[0..11], "{o:0>11}", .{@as(u64, @intCast(entry.mtime))});
    header.mtime[11] = 0;

    // Set type flag
    header.typeflag = switch (entry.entry_type) {
        .file => TarHeader.TypeFlag.REGULAR,
        .directory => TarHeader.TypeFlag.DIRECTORY,
        .symlink => TarHeader.TypeFlag.SYMLINK,
        .hardlink => TarHeader.TypeFlag.HARD_LINK,
        .char_device => TarHeader.TypeFlag.CHAR_DEVICE,
        .block_device => TarHeader.TypeFlag.BLOCK_DEVICE,
        .fifo => TarHeader.TypeFlag.FIFO,
    };

    // Set link name for symlinks and hard links
    if (entry.link_target.len > 0) {
        if (entry.link_target.len > 100) {
            return error.FilenameTooLong; // TODO: Use GNU long link extension
        }
        @memcpy(header.linkname[0..entry.link_target.len], entry.link_target);
    }

    // Set USTAR magic and version
    @memcpy(header.magic[0..6], "ustar\x00");
    @memcpy(header.version[0..2], "00");

    // Set user and group names
    if (entry.uname.len > 0) {
        const len = @min(entry.uname.len, 31);
        @memcpy(header.uname[0..len], entry.uname[0..len]);
    }
    if (entry.gname.len > 0) {
        const len = @min(entry.gname.len, 31);
        @memcpy(header.gname[0..len], entry.gname[0..len]);
    }

    // Calculate and set checksum
    // Format: 6 octal digits + null + space (traditional format)
    const checksum = calculateChecksum(@ptrCast(&header));
    _ = try std.fmt.bufPrint(header.checksum[0..6], "{o:0>6}", .{checksum});
    header.checksum[6] = 0;
    header.checksum[7] = ' ';

    return header;
}

// Tests
test "TarHeader: block size is 512 bytes" {
    try std.testing.expectEqual(512, @sizeOf(TarHeader));
    try std.testing.expectEqual(512, TarHeader.BLOCK_SIZE);
}

test "TarHeader: checksum field offset" {
    try std.testing.expectEqual(148, TarHeader.CHECKSUM_OFFSET);
    try std.testing.expectEqual(8, TarHeader.CHECKSUM_SIZE);
}

test "calculateChecksum: zero block" {
    var data: [512]u8 = std.mem.zeroes([512]u8);
    const checksum = calculateChecksum(&data);

    // Checksum should be 8 * ' ' (0x20) = 8 * 32 = 256
    try std.testing.expectEqual(@as(u32, 256), checksum);
}

test "calculateChecksum: with data" {
    var data: [512]u8 = undefined;
    @memset(&data, 0);

    // Set some test data (excluding checksum field)
    data[0] = 'T';
    data[1] = 'E';
    data[2] = 'S';
    data[3] = 'T';

    const checksum = calculateChecksum(&data);

    // Expected: 'T' + 'E' + 'S' + 'T' + (8 * ' ')
    // = 84 + 69 + 83 + 84 + 256 = 576
    try std.testing.expectEqual(@as(u32, 576), checksum);
}

test "TarHeader.parse: simple header" {
    const allocator = std.testing.allocator;

    // Create a simple tar header
    var header_data: [512]u8 = std.mem.zeroes([512]u8);

    // File name
    @memcpy(header_data[0..9], "test.txt\x00");

    // Mode: 0o644
    @memcpy(header_data[100..108], "0000644\x00");

    // Size: 100 bytes (0o144)
    @memcpy(header_data[124..136], "00000000144\x00");

    // Mtime: 1234567890 (0o11145401322)
    @memcpy(header_data[136..148], "11145401322\x00");

    // Type flag: regular file
    header_data[156] = '0';

    // USTAR magic
    @memcpy(header_data[257..263], "ustar\x00");

    // USTAR version
    @memcpy(header_data[263..265], "00");

    // Calculate and set checksum
    const checksum = calculateChecksum(&header_data);
    _ = try std.fmt.bufPrint(header_data[148..156], "{o:0>6}\x00 ", .{checksum});

    // Parse header
    const header = try TarHeader.parse(&header_data);

    // Verify parsed values
    const name = try header.getName(allocator);
    defer allocator.free(name);
    try std.testing.expectEqualStrings("test.txt", name);

    const size = try header.getSize();
    try std.testing.expectEqual(@as(u64, 100), size);

    const mode = try header.getMode();
    try std.testing.expectEqual(@as(u32, 0o644), mode);

    const mtime = try header.getMtime();
    try std.testing.expectEqual(@as(i64, 1234567890), mtime);

    const entry_type = header.getEntryType();
    try std.testing.expectEqual(types.EntryType.file, entry_type);
}

test "TarHeader.parse: invalid magic" {
    var header_data: [512]u8 = std.mem.zeroes([512]u8);

    // Set invalid magic
    @memcpy(header_data[257..263], "NOTTAR");

    // Try to parse - should fail
    try std.testing.expectError(error.CorruptedHeader, TarHeader.parse(&header_data));
}

test "TarHeader.parse: invalid checksum" {
    var header_data: [512]u8 = std.mem.zeroes([512]u8);

    // Set valid magic and version
    @memcpy(header_data[257..263], "ustar\x00");
    @memcpy(header_data[263..265], "00");

    // Set wrong checksum
    @memcpy(header_data[148..156], "9999999\x00");

    // Try to parse - should fail
    try std.testing.expectError(error.CorruptedHeader, TarHeader.parse(&header_data));
}

test "createHeader: simple file" {
    const allocator = std.testing.allocator;

    const entry = types.Entry{
        .path = "test.txt",
        .entry_type = .file,
        .size = 1024,
        .mode = 0o644,
        .mtime = 1234567890,
        .uid = 1000,
        .gid = 1000,
        .uname = "user",
        .gname = "group",
        .link_target = "",
    };

    const header = try createHeader(&entry, allocator);

    // Verify header fields
    const name = try header.getName(allocator);
    defer allocator.free(name);
    try std.testing.expectEqualStrings("test.txt", name);

    const size = try header.getSize();
    try std.testing.expectEqual(@as(u64, 1024), size);

    const mode = try header.getMode();
    try std.testing.expectEqual(@as(u32, 0o644), mode);

    try std.testing.expectEqual(TarHeader.TypeFlag.REGULAR, header.typeflag);

    // Verify USTAR magic and version
    try std.testing.expect(std.mem.eql(u8, header.magic[0..6], "ustar\x00"));
    try std.testing.expect(std.mem.eql(u8, header.version[0..2], "00"));
}

test "createHeader: with prefix" {
    const allocator = std.testing.allocator;

    // Create a path longer than 100 characters
    const long_path = "very/long/path/prefix/that/exceeds/one/hundred/characters/and/needs/to/be/split/into/prefix/and/name/parts/file.txt";

    const entry = types.Entry{
        .path = long_path,
        .entry_type = .file,
        .size = 100,
        .mode = 0o644,
        .mtime = 1234567890,
        .uid = 0,
        .gid = 0,
        .uname = "",
        .gname = "",
        .link_target = "",
    };

    const header = try createHeader(&entry, allocator);

    // Verify that we can reconstruct the full path
    const reconstructed = try header.getName(allocator);
    defer allocator.free(reconstructed);

    try std.testing.expectEqualStrings(long_path, reconstructed);
}

test "TarHeader: round-trip conversion" {
    const allocator = std.testing.allocator;

    // Create original entry
    const original_entry = types.Entry{
        .path = "test/file.txt",
        .entry_type = .file,
        .size = 2048,
        .mode = 0o755,
        .mtime = 1234567890,
        .uid = 1000,
        .gid = 1000,
        .uname = "testuser",
        .gname = "testgroup",
        .link_target = "",
    };

    // Convert to header
    const header = try createHeader(&original_entry, allocator);

    // Convert back to entry
    const converted_entry = try header.toEntry(allocator);
    defer allocator.free(converted_entry.path);
    defer allocator.free(converted_entry.uname);
    defer allocator.free(converted_entry.gname);
    defer allocator.free(converted_entry.link_target);

    // Verify round-trip
    try std.testing.expectEqualStrings(original_entry.path, converted_entry.path);
    try std.testing.expectEqual(original_entry.entry_type, converted_entry.entry_type);
    try std.testing.expectEqual(original_entry.size, converted_entry.size);
    try std.testing.expectEqual(original_entry.mode, converted_entry.mode);
    try std.testing.expectEqual(original_entry.mtime, converted_entry.mtime);
    try std.testing.expectEqual(original_entry.uid, converted_entry.uid);
    try std.testing.expectEqual(original_entry.gid, converted_entry.gid);
    try std.testing.expectEqualStrings(original_entry.uname, converted_entry.uname);
    try std.testing.expectEqualStrings(original_entry.gname, converted_entry.gname);
}
