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

/// Entry type in an archive
pub const EntryType = enum {
    /// Regular file
    file,
    /// Directory
    directory,
    /// Symbolic link
    symlink,
    /// Hard link
    hardlink,
    /// Character device (POSIX)
    char_device,
    /// Block device (POSIX)
    block_device,
    /// FIFO/Named pipe (POSIX)
    fifo,
};

/// Archive entry metadata
pub const Entry = struct {
    /// Entry path (relative to archive root)
    path: []const u8,

    /// Entry type (file, directory, symlink, etc.)
    entry_type: EntryType,

    /// File size in bytes (0 for directories)
    size: u64,

    /// File mode/permissions (POSIX: 0o755, etc.)
    mode: u32,

    /// Modification time (Unix timestamp)
    mtime: i64,

    /// User ID (POSIX)
    uid: u32 = 0,

    /// Group ID (POSIX)
    gid: u32 = 0,

    /// User name (optional)
    uname: []const u8 = "",

    /// Group name (optional)
    gname: []const u8 = "",

    /// Symlink target path (for symlink/hardlink)
    link_target: []const u8 = "",

    /// Format entry for display
    pub fn format(
        self: Entry,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        const type_str = switch (self.entry_type) {
            .file => "FILE",
            .directory => "DIR ",
            .symlink => "LINK",
            .hardlink => "HARD",
            .char_device => "CHAR",
            .block_device => "BLCK",
            .fifo => "FIFO",
        };

        try writer.print("{s} {o:0>4} {d:>10} {s}", .{
            type_str,
            self.mode,
            self.size,
            self.path,
        });

        if (self.entry_type == .symlink or self.entry_type == .hardlink) {
            try writer.print(" -> {s}", .{self.link_target});
        }
    }
};

/// Compression level
pub const CompressionLevel = enum(u8) {
    /// Fastest compression (lowest ratio)
    fastest = 1,
    /// Fast compression
    fast = 3,
    /// Default compression (balanced)
    default = 6,
    /// Best compression (slowest)
    best = 9,

    /// Convert integer to compression level
    pub fn fromInt(level: u8) !CompressionLevel {
        return switch (level) {
            0...9 => @enumFromInt(level),
            else => error.InvalidCompressionLevel,
        };
    }

    /// Get integer value
    pub fn toInt(self: CompressionLevel) u8 {
        return @intFromEnum(self);
    }
};

/// Archive format type
pub const FormatType = enum {
    /// Plain tar
    tar,
    /// Tar with gzip compression
    tar_gz,
    /// Tar with bzip2 compression
    tar_bz2,
    /// Tar with xz/lzma2 compression
    tar_xz,
    /// ZIP format
    zip,
    /// 7-Zip format
    sevenzip,
    /// Unknown format
    unknown,

    /// Get file extension for this format
    pub fn extension(self: FormatType) []const u8 {
        return switch (self) {
            .tar => ".tar",
            .tar_gz => ".tar.gz",
            .tar_bz2 => ".tar.bz2",
            .tar_xz => ".tar.xz",
            .zip => ".zip",
            .sevenzip => ".7z",
            .unknown => "",
        };
    }

    /// Detect format from file extension
    pub fn fromExtension(path: []const u8) FormatType {
        if (std.mem.endsWith(u8, path, ".tar.gz") or std.mem.endsWith(u8, path, ".tgz")) {
            return .tar_gz;
        } else if (std.mem.endsWith(u8, path, ".tar.bz2") or std.mem.endsWith(u8, path, ".tbz2")) {
            return .tar_bz2;
        } else if (std.mem.endsWith(u8, path, ".tar.xz") or std.mem.endsWith(u8, path, ".txz")) {
            return .tar_xz;
        } else if (std.mem.endsWith(u8, path, ".tar")) {
            return .tar;
        } else if (std.mem.endsWith(u8, path, ".zip")) {
            return .zip;
        } else if (std.mem.endsWith(u8, path, ".7z")) {
            return .sevenzip;
        } else {
            return .unknown;
        }
    }
};

/// Buffer size constants
pub const BufferSize = struct {
    /// Small buffer (4KB) - for headers, metadata
    pub const small: usize = 4 * 1024;

    /// Default buffer (64KB) - for general I/O
    pub const default: usize = 64 * 1024;

    /// Large buffer (1MB) - for large files
    pub const large: usize = 1 * 1024 * 1024;

    /// Huge buffer (4MB) - for very large files
    pub const huge: usize = 4 * 1024 * 1024;
};

/// File size limits
pub const SizeLimit = struct {
    /// Maximum file size (10GB by default)
    pub const max_file_size: u64 = 10 * 1024 * 1024 * 1024;

    /// Maximum archive size (unlimited)
    pub const max_archive_size: u64 = std.math.maxInt(u64);

    /// Maximum path length (4096 bytes)
    pub const max_path_length: usize = 4096;

    /// Maximum symlink target length (4096 bytes)
    pub const max_link_target_length: usize = 4096;
};

// Tests
test "EntryType: basic types" {
    try std.testing.expectEqual(EntryType.file, EntryType.file);
    try std.testing.expectEqual(EntryType.directory, EntryType.directory);
    try std.testing.expectEqual(EntryType.symlink, EntryType.symlink);
}

test "Entry: default values" {
    const entry = Entry{
        .path = "test.txt",
        .entry_type = .file,
        .size = 1024,
        .mode = 0o644,
        .mtime = 1234567890,
    };

    try std.testing.expectEqualStrings("test.txt", entry.path);
    try std.testing.expectEqual(EntryType.file, entry.entry_type);
    try std.testing.expectEqual(@as(u64, 1024), entry.size);
    try std.testing.expectEqual(@as(u32, 0o644), entry.mode);
    try std.testing.expectEqual(@as(i64, 1234567890), entry.mtime);
    try std.testing.expectEqual(@as(u32, 0), entry.uid);
    try std.testing.expectEqual(@as(u32, 0), entry.gid);
}

test "Entry: format output" {
    const entry = Entry{
        .path = "test.txt",
        .entry_type = .file,
        .size = 1024,
        .mode = 0o644,
        .mtime = 1234567890,
    };

    var buffer = std.array_list.Aligned(u8, null).empty;
    defer buffer.deinit(std.testing.allocator);

    try entry.format("", .{}, buffer.writer(std.testing.allocator));

    const output = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "FILE") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "0644") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "1024") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "test.txt") != null);
}

test "Entry: symlink format" {
    const entry = Entry{
        .path = "link.txt",
        .entry_type = .symlink,
        .size = 0,
        .mode = 0o777,
        .mtime = 1234567890,
        .link_target = "/path/to/target.txt",
    };

    var buffer = std.array_list.Aligned(u8, null).empty;
    defer buffer.deinit(std.testing.allocator);

    try entry.format("", .{}, buffer.writer(std.testing.allocator));

    const output = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "LINK") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "->") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "/path/to/target.txt") != null);
}

test "CompressionLevel: fromInt and toInt" {
    const level = try CompressionLevel.fromInt(6);
    try std.testing.expectEqual(CompressionLevel.default, level);
    try std.testing.expectEqual(@as(u8, 6), level.toInt());

    try std.testing.expectError(error.InvalidCompressionLevel, CompressionLevel.fromInt(10));
}

test "FormatType: extension" {
    try std.testing.expectEqualStrings(".tar", FormatType.tar.extension());
    try std.testing.expectEqualStrings(".tar.gz", FormatType.tar_gz.extension());
    try std.testing.expectEqualStrings(".zip", FormatType.zip.extension());
    try std.testing.expectEqualStrings(".7z", FormatType.sevenzip.extension());
}

test "FormatType: fromExtension" {
    try std.testing.expectEqual(FormatType.tar, FormatType.fromExtension("archive.tar"));
    try std.testing.expectEqual(FormatType.tar_gz, FormatType.fromExtension("archive.tar.gz"));
    try std.testing.expectEqual(FormatType.tar_gz, FormatType.fromExtension("archive.tgz"));
    try std.testing.expectEqual(FormatType.tar_bz2, FormatType.fromExtension("archive.tar.bz2"));
    try std.testing.expectEqual(FormatType.tar_xz, FormatType.fromExtension("archive.tar.xz"));
    try std.testing.expectEqual(FormatType.zip, FormatType.fromExtension("archive.zip"));
    try std.testing.expectEqual(FormatType.sevenzip, FormatType.fromExtension("archive.7z"));
    try std.testing.expectEqual(FormatType.unknown, FormatType.fromExtension("unknown.bin"));
}

test "BufferSize: constants" {
    try std.testing.expectEqual(@as(usize, 4 * 1024), BufferSize.small);
    try std.testing.expectEqual(@as(usize, 64 * 1024), BufferSize.default);
    try std.testing.expectEqual(@as(usize, 1 * 1024 * 1024), BufferSize.large);
    try std.testing.expectEqual(@as(usize, 4 * 1024 * 1024), BufferSize.huge);
}

test "SizeLimit: constants" {
    try std.testing.expectEqual(@as(u64, 10 * 1024 * 1024 * 1024), SizeLimit.max_file_size);
    try std.testing.expectEqual(@as(usize, 4096), SizeLimit.max_path_length);
    try std.testing.expectEqual(@as(usize, 4096), SizeLimit.max_link_target_length);
}
