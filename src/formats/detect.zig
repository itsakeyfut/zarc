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
const types = @import("../core/types.zig");
const errors = @import("../core/errors.zig");
const gzip = @import("../compress/gzip.zig");
const tar_header = @import("tar/header.zig");

/// Magic numbers for archive format detection
pub const MagicNumbers = struct {
    /// Gzip magic number (RFC 1952)
    pub const GZIP = [2]u8{ 0x1f, 0x8b };

    /// Bzip2 magic number
    pub const BZIP2 = [2]u8{ 0x42, 0x5a }; // "BZ"

    /// XZ magic number
    pub const XZ = [6]u8{ 0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00 };

    /// 7-Zip magic number
    pub const SEVENZIP = [6]u8{ 0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c };

    /// ZIP magic number (local file header)
    pub const ZIP = [4]u8{ 0x50, 0x4b, 0x03, 0x04 }; // "PK\x03\x04"

    /// ZIP magic number (empty archive)
    pub const ZIP_EMPTY = [4]u8{ 0x50, 0x4b, 0x05, 0x06 }; // "PK\x05\x06"

    /// TAR USTAR magic (at offset 257)
    pub const TAR_USTAR = [6]u8{ 0x75, 0x73, 0x74, 0x61, 0x72, 0x00 }; // "ustar\x00"

    /// TAR GNU old tar magic (at offset 257)
    pub const TAR_GNU = [6]u8{ 0x75, 0x73, 0x74, 0x61, 0x72, 0x20 }; // "ustar "

    /// TAR header offset where magic number is located
    pub const TAR_MAGIC_OFFSET: usize = 257;

    /// Minimum bytes needed to detect tar format (includes header)
    pub const TAR_MIN_SIZE: usize = 512;
};

/// Detect archive format from file path
///
/// This function first attempts to detect the format by reading the file's
/// magic numbers. If magic number detection is unclear or fails, it falls
/// back to extension-based detection.
///
/// Parameters:
///   - allocator: Memory allocator
///   - path: File path to analyze
///
/// Returns:
///   - Detected FormatType
///
/// Errors:
///   - error.FileNotFound: File does not exist
///   - error.PermissionDenied: Cannot read file
///   - error.ReadError: Error reading file
///
/// Example:
/// ```zig
/// const format = try detectFormat(allocator, "archive.tar.gz");
/// // format == .tar_gz
/// ```
pub fn detectFormat(allocator: std.mem.Allocator, path: []const u8) !types.FormatType {
    _ = allocator;

    // Try magic number detection first
    const magic_format = detectFormatByMagic(path) catch |err| {
        // If magic detection fails, fall back to extension
        if (err == error.FileNotFound or err == error.PermissionDenied) {
            return err;
        }
        // For other errors (like insufficient data), try extension detection
        return detectFormatByExtension(path);
    };

    // If magic detection returns unknown, try extension
    if (magic_format == .unknown) {
        return detectFormatByExtension(path);
    }

    return magic_format;
}

/// Detect archive format from magic numbers
///
/// Reads the beginning of the file to identify the format based on
/// magic number signatures.
///
/// Parameters:
///   - path: File path to analyze
///
/// Returns:
///   - Detected FormatType (may be .unknown if unrecognized)
///
/// Errors:
///   - error.FileNotFound: File does not exist
///   - error.PermissionDenied: Cannot read file
///   - error.ReadError: Error reading file
///
/// Example:
/// ```zig
/// const format = try detectFormatByMagic("archive.tar");
/// ```
pub fn detectFormatByMagic(path: []const u8) !types.FormatType {
    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        return switch (err) {
            error.FileNotFound => error.FileNotFound,
            error.AccessDenied => error.PermissionDenied,
            else => error.ReadError,
        };
    };
    defer file.close();

    // Read enough bytes to detect any format
    // We need at least 512 bytes for tar detection (offset 257 + 6 bytes)
    var buffer: [512]u8 = undefined;
    const bytes_read = file.read(&buffer) catch {
        return error.ReadError;
    };

    return detectFormatFromBytes(buffer[0..bytes_read]);
}

/// Detect archive format from byte buffer
///
/// Analyzes raw bytes to identify the format based on magic numbers.
///
/// Parameters:
///   - data: Byte buffer to analyze
///
/// Returns:
///   - Detected FormatType (may be .unknown if unrecognized)
///
/// Example:
/// ```zig
/// const format = detectFormatFromBytes(&file_header);
/// ```
pub fn detectFormatFromBytes(data: []const u8) types.FormatType {
    // Need at least 2 bytes for most formats
    if (data.len < 2) {
        return .unknown;
    }

    // Check gzip magic (most common for tar.gz)
    if (std.mem.eql(u8, data[0..2], &MagicNumbers.GZIP)) {
        // For gzip, we need to check if it's compressed tar
        // This is a heuristic: if the file extension suggests tar.gz, trust it
        // Otherwise, just return gzip format
        // Note: Proper tar.gz detection would require decompressing and checking,
        // which is expensive. We'll rely on extension detection for tar_gz.
        return .tar_gz;
    }

    // Check bzip2 magic
    if (std.mem.eql(u8, data[0..2], &MagicNumbers.BZIP2)) {
        return .tar_bz2;
    }

    // Check for ZIP format (needs 4 bytes)
    if (data.len >= 4) {
        if (std.mem.eql(u8, data[0..4], &MagicNumbers.ZIP) or
            std.mem.eql(u8, data[0..4], &MagicNumbers.ZIP_EMPTY))
        {
            return .zip;
        }
    }

    // Check for 7-Zip format (needs 6 bytes)
    if (data.len >= 6) {
        if (std.mem.eql(u8, data[0..6], &MagicNumbers.SEVENZIP)) {
            return .sevenzip;
        }

        // Check for XZ format
        if (std.mem.eql(u8, data[0..6], &MagicNumbers.XZ)) {
            return .tar_xz;
        }
    }

    // Check for TAR format (needs 512 bytes minimum)
    // TAR magic is at offset 257
    if (data.len >= MagicNumbers.TAR_MIN_SIZE) {
        const tar_magic_start = MagicNumbers.TAR_MAGIC_OFFSET;
        const tar_magic_end = tar_magic_start + 6;

        // Check for POSIX ustar format
        if (std.mem.eql(u8, data[tar_magic_start..tar_magic_end], &MagicNumbers.TAR_USTAR)) {
            return .tar;
        }

        // Check for GNU old tar format
        if (std.mem.eql(u8, data[tar_magic_start..tar_magic_end], &MagicNumbers.TAR_GNU)) {
            return .tar;
        }
    }

    return .unknown;
}

/// Detect archive format from file extension
///
/// Analyzes the file path extension to determine the format.
/// This is a fallback when magic number detection is unclear.
///
/// Parameters:
///   - path: File path to analyze
///
/// Returns:
///   - Detected FormatType (may be .unknown if unrecognized extension)
///
/// Example:
/// ```zig
/// const format = detectFormatByExtension("archive.tar.gz");
/// // format == .tar_gz
/// ```
pub fn detectFormatByExtension(path: []const u8) types.FormatType {
    return types.FormatType.fromExtension(path);
}

// Tests
test "detectFormatFromBytes: gzip magic" {
    const gzip_header = [_]u8{
        0x1f, 0x8b, // Gzip magic
        0x08, 0x00,
        0x00, 0x00,
        0x00, 0x00,
        0x00, 0x03,
    };

    const format = detectFormatFromBytes(&gzip_header);
    try std.testing.expectEqual(types.FormatType.tar_gz, format);
}

test "detectFormatFromBytes: bzip2 magic" {
    const bzip2_header = [_]u8{
        0x42, 0x5a, // Bzip2 magic "BZ"
        0x68, 0x39, // Version and block size
    };

    const format = detectFormatFromBytes(&bzip2_header);
    try std.testing.expectEqual(types.FormatType.tar_bz2, format);
}

test "detectFormatFromBytes: zip magic" {
    const zip_header = [_]u8{
        0x50, 0x4b, 0x03, 0x04, // ZIP magic "PK\x03\x04"
        0x0a, 0x00, 0x00, 0x00,
    };

    const format = detectFormatFromBytes(&zip_header);
    try std.testing.expectEqual(types.FormatType.zip, format);
}

test "detectFormatFromBytes: 7z magic" {
    const sevenzip_header = [_]u8{
        0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c, // 7z magic
        0x00, 0x04,
    };

    const format = detectFormatFromBytes(&sevenzip_header);
    try std.testing.expectEqual(types.FormatType.sevenzip, format);
}

test "detectFormatFromBytes: xz magic" {
    const xz_header = [_]u8{
        0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00, // XZ magic
        0x00, 0x01,
    };

    const format = detectFormatFromBytes(&xz_header);
    try std.testing.expectEqual(types.FormatType.tar_xz, format);
}

test "detectFormatFromBytes: tar ustar magic" {
    // Create a minimal valid tar header
    var header_data: [512]u8 = std.mem.zeroes([512]u8);

    // File name
    @memcpy(header_data[0..9], "test.txt\x00");

    // Mode: 0o644
    @memcpy(header_data[100..108], "0000644\x00");

    // Size: 0
    @memcpy(header_data[124..136], "00000000000\x00");

    // Mtime: 0
    @memcpy(header_data[136..148], "00000000000\x00");

    // Type flag: regular file
    header_data[156] = '0';

    // USTAR magic at offset 257
    @memcpy(header_data[257..263], "ustar\x00");

    // USTAR version
    @memcpy(header_data[263..265], "00");

    // Calculate and set checksum
    const checksum = tar_header.calculateChecksum(&header_data);
    _ = try std.fmt.bufPrint(header_data[148..156], "{o:0>6}\x00 ", .{checksum});

    const format = detectFormatFromBytes(&header_data);
    try std.testing.expectEqual(types.FormatType.tar, format);
}

test "detectFormatFromBytes: insufficient data" {
    const small_data = [_]u8{0x00};

    const format = detectFormatFromBytes(&small_data);
    try std.testing.expectEqual(types.FormatType.unknown, format);
}

test "detectFormatFromBytes: unknown format" {
    const unknown_data = [_]u8{
        0xff, 0xfe, 0xfd, 0xfc,
        0x00, 0x01, 0x02, 0x03,
    };

    const format = detectFormatFromBytes(&unknown_data);
    try std.testing.expectEqual(types.FormatType.unknown, format);
}

test "detectFormatByExtension: tar.gz variants" {
    try std.testing.expectEqual(
        types.FormatType.tar_gz,
        detectFormatByExtension("archive.tar.gz"),
    );
    try std.testing.expectEqual(
        types.FormatType.tar_gz,
        detectFormatByExtension("archive.tgz"),
    );
}

test "detectFormatByExtension: tar" {
    try std.testing.expectEqual(
        types.FormatType.tar,
        detectFormatByExtension("archive.tar"),
    );
}

test "detectFormatByExtension: zip" {
    try std.testing.expectEqual(
        types.FormatType.zip,
        detectFormatByExtension("archive.zip"),
    );
}

test "detectFormatByExtension: 7z" {
    try std.testing.expectEqual(
        types.FormatType.sevenzip,
        detectFormatByExtension("archive.7z"),
    );
}

test "detectFormatByExtension: unknown" {
    try std.testing.expectEqual(
        types.FormatType.unknown,
        detectFormatByExtension("file.dat"),
    );
}

test "MagicNumbers: constants are correct" {
    // Verify magic number constants
    try std.testing.expectEqual(@as(u8, 0x1f), MagicNumbers.GZIP[0]);
    try std.testing.expectEqual(@as(u8, 0x8b), MagicNumbers.GZIP[1]);

    try std.testing.expectEqual(@as(u8, 0x42), MagicNumbers.BZIP2[0]);
    try std.testing.expectEqual(@as(u8, 0x5a), MagicNumbers.BZIP2[1]);

    try std.testing.expectEqual(@as(usize, 257), MagicNumbers.TAR_MAGIC_OFFSET);
    try std.testing.expectEqual(@as(usize, 512), MagicNumbers.TAR_MIN_SIZE);
}
