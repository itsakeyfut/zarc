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
const header = @import("header.zig");
const types = @import("../../core/types.zig");
const errors = @import("../../core/errors.zig");
const archive = @import("../archive.zig");
const streaming = @import("../../io/streaming.zig");

/// TAR archive reader with streaming support
///
/// Reads TAR archive entries sequentially from a file or stream.
/// Supports POSIX ustar format and GNU tar extensions (long filenames).
///
/// Example:
/// ```zig
/// const file = try std.fs.cwd().openFile("archive.tar", .{});
/// defer file.close();
///
/// var reader = try TarReader.init(allocator, file);
/// defer reader.deinit();
///
/// while (try reader.next()) |entry| {
///     std.debug.print("Entry: {s} ({d} bytes)\n", .{entry.path, entry.size});
///
///     var buffer: [4096]u8 = undefined;
///     while (true) {
///         const n = try reader.read(&buffer);
///         if (n == 0) break;
///         // Process data...
///     }
/// }
/// ```
pub const TarReader = struct {
    /// Maximum size for GNU long name/link extensions (16 MiB)
    /// Prevents pathological archives from forcing huge allocations
    const MAX_GNU_EXTENSION_SIZE: u64 = 16 * 1024 * 1024;

    allocator: std.mem.Allocator,
    file: std.fs.File,

    /// Current entry being read
    current_entry: ?types.Entry = null,

    /// Remaining bytes to read in current entry
    remaining_bytes: u64 = 0,

    /// Position in file (for error reporting)
    file_position: u64 = 0,

    /// GNU tar long name buffer (allocated when needed)
    gnu_long_name: ?[]u8 = null,

    /// GNU tar long link name buffer (allocated when needed)
    gnu_long_link: ?[]u8 = null,

    /// Initialize TAR reader
    ///
    /// Parameters:
    ///   - allocator: Memory allocator
    ///   - file: TAR archive file (must be opened for reading)
    ///
    /// Returns:
    ///   - Initialized TarReader
    ///
    /// Example:
    /// ```zig
    /// const file = try std.fs.cwd().openFile("archive.tar", .{});
    /// var reader = try TarReader.init(allocator, file);
    /// defer reader.deinit();
    /// ```
    pub fn init(allocator: std.mem.Allocator, file: std.fs.File) !TarReader {
        return TarReader{
            .allocator = allocator,
            .file = file,
        };
    }

    /// Clean up resources
    ///
    /// Note: Does not close the file (caller is responsible)
    pub fn deinit(self: *TarReader) void {
        // Free current entry if any
        if (self.current_entry) |entry| {
            self.freeEntry(entry);
            self.current_entry = null;
        }

        // Free GNU extension buffers
        if (self.gnu_long_name) |name| {
            self.allocator.free(name);
            self.gnu_long_name = null;
        }
        if (self.gnu_long_link) |link| {
            self.allocator.free(link);
            self.gnu_long_link = null;
        }
    }

    /// Create an ArchiveReader interface from this TarReader
    ///
    /// Allows TarReader to be used through the common ArchiveReader interface,
    /// enabling polymorphism across different archive formats.
    ///
    /// Returns:
    ///   - ArchiveReader wrapping this TarReader
    ///
    /// Example:
    /// ```zig
    /// var tar_reader = try TarReader.init(allocator, file);
    /// defer tar_reader.deinit();
    ///
    /// var archive_reader = tar_reader.archiveReader();
    ///
    /// while (try archive_reader.next()) |entry| {
    ///     std.debug.print("Entry: {s}\n", .{entry.path});
    /// }
    /// ```
    pub fn archiveReader(self: *TarReader) archive.ArchiveReader {
        return .{
            .ptr = self,
            .vtable = &.{
                .next = nextVTable,
                .read = readVTable,
                .deinit = deinitVTable,
            },
        };
    }

    /// VTable implementation for next()
    fn nextVTable(ptr: *anyopaque) anyerror!?types.Entry {
        const self: *TarReader = @ptrCast(@alignCast(ptr));
        return self.next();
    }

    /// VTable implementation for read()
    fn readVTable(ptr: *anyopaque, buffer: []u8) anyerror!usize {
        const self: *TarReader = @ptrCast(@alignCast(ptr));
        return self.read(buffer);
    }

    /// VTable implementation for deinit()
    fn deinitVTable(ptr: *anyopaque) void {
        const self: *TarReader = @ptrCast(@alignCast(ptr));
        self.deinit();
    }

    /// Get next entry in archive
    ///
    /// Returns:
    ///   - Next entry metadata, or null if end of archive reached
    ///
    /// Errors:
    ///   - error.CorruptedHeader: Invalid header format
    ///   - error.IncompleteArchive: Unexpected end of file
    ///   - error.ReadError: Failed to read from file
    ///
    /// Example:
    /// ```zig
    /// while (try reader.next()) |entry| {
    ///     std.debug.print("Entry: {s}\n", .{entry.path});
    /// }
    /// ```
    pub fn next(self: *TarReader) !?types.Entry {
        // Free previous entry if any
        if (self.current_entry) |entry| {
            // Skip remaining data and padding from previous entry
            try self.skipRemainingData();
            try self.skipPadding(entry.size);
            self.freeEntry(entry);
            self.current_entry = null;
        }

        // Try to read next header
        while (true) {
            var header_block: [header.TarHeader.BLOCK_SIZE]u8 = undefined;
            const n = try self.file.readAll(&header_block);

            if (n == 0) {
                // End of file
                return null;
            }

            if (n != header.TarHeader.BLOCK_SIZE) {
                return error.IncompleteArchive;
            }

            self.file_position += header.TarHeader.BLOCK_SIZE;

            // Check if this is end-of-archive marker (all zeros)
            if (isZeroBlock(&header_block)) {
                // Read one more block to confirm (TAR has two zero blocks at end)
                var second_block: [header.TarHeader.BLOCK_SIZE]u8 = undefined;
                const n2 = try self.file.readAll(&second_block);

                if (n2 == 0) {
                    // Some TAR writers only emit one zero block at EOF
                    return null;
                }
                if (n2 == header.TarHeader.BLOCK_SIZE and isZeroBlock(&second_block)) {
                    self.file_position += header.TarHeader.BLOCK_SIZE;
                    return null; // End of archive
                }

                // Not a proper end marker, treat as corrupted
                return error.CorruptedHeader;
            }

            // Parse header
            const tar_header = header.TarHeader.parse(&header_block) catch |err| {
                std.debug.print("Failed to parse header at offset 0x{x}\n", .{self.file_position - header.TarHeader.BLOCK_SIZE});
                return err;
            };

            // Handle GNU tar extensions
            if (tar_header.typeflag == header.TarHeader.TypeFlag.GNU_LONG_NAME) {
                // Next block(s) contain long filename
                try self.readGnuLongName(&tar_header);
                continue; // Read next header
            }

            if (tar_header.typeflag == header.TarHeader.TypeFlag.GNU_LONG_LINK) {
                // Next block(s) contain long link target
                try self.readGnuLongLink(&tar_header);
                continue; // Read next header
            }

            // Convert header to entry
            var entry = try tar_header.toEntry(self.allocator);

            // Replace name with GNU long name if available
            if (self.gnu_long_name) |long_name| {
                self.allocator.free(entry.path);
                entry.path = long_name;
                self.gnu_long_name = null; // Ownership transferred
            }

            // Replace link target with GNU long link if available
            if (self.gnu_long_link) |long_link| {
                self.allocator.free(entry.link_target);
                entry.link_target = long_link;
                self.gnu_long_link = null; // Ownership transferred
            }

            // Set up for reading entry data
            self.current_entry = entry;
            self.remaining_bytes = entry.size;

            return entry;
        }
    }

    /// Read data from current entry
    ///
    /// Parameters:
    ///   - buffer: Buffer to read data into
    ///
    /// Returns:
    ///   - Number of bytes read (0 when entry is fully read)
    ///
    /// Errors:
    ///   - error.ReadError: Failed to read from file
    ///   - error.NoCurrentEntry: No entry is currently being read
    ///
    /// Example:
    /// ```zig
    /// var buffer: [4096]u8 = undefined;
    /// while (true) {
    ///     const n = try reader.read(&buffer);
    ///     if (n == 0) break;
    ///     // Process buffer[0..n]
    /// }
    /// ```
    pub fn read(self: *TarReader, buffer: []u8) !usize {
        if (self.current_entry == null) {
            return error.NoCurrentEntry;
        }

        if (self.remaining_bytes == 0) {
            return 0; // Entry fully read
        }

        // Read up to remaining bytes
        const to_read_u64 = @min(@as(u64, buffer.len), self.remaining_bytes);
        const to_read: usize = @intCast(to_read_u64);
        const n = try self.file.readAll(buffer[0..to_read]);

        if (n != to_read) {
            return error.IncompleteArchive;
        }

        self.remaining_bytes -= @as(u64, n);
        self.file_position += @as(u64, n);

        return n;
    }

    /// Skip to next entry (skip remaining data of current entry)
    ///
    /// Automatically called by next(), but can be called manually
    /// to skip large files without reading all their data.
    ///
    /// Errors:
    ///   - error.SeekError: Failed to seek in file
    pub fn skipRemainingData(self: *TarReader) !void {
        if (self.remaining_bytes == 0) {
            return;
        }

        // Try to seek (faster than reading) if the offset fits in i64
        if (std.math.cast(i64, self.remaining_bytes)) |off| {
            if (self.file.seekBy(off)) |_| {
                self.file_position += self.remaining_bytes;
                self.remaining_bytes = 0;
                return;
            } else |_| {}
        }
        // Fallback: read and discard
        var discard_buffer: [4096]u8 = undefined;
        var remaining = self.remaining_bytes;

        while (remaining > 0) {
            const to_read_u64 = @min(remaining, @as(u64, discard_buffer.len));
            const to_read: usize = @intCast(to_read_u64);
            const n = try self.file.readAll(discard_buffer[0..to_read]);

            if (n != to_read) {
                return error.IncompleteArchive;
            }

            remaining -= @as(u64, n);
        }
        self.file_position += self.remaining_bytes;
        self.remaining_bytes = 0;
    }

    /// Skip padding bytes to reach 512-byte boundary
    ///
    /// TAR format requires file data to be padded to 512-byte blocks.
    ///
    /// Parameters:
    ///   - size: Original file size (before padding)
    ///
    /// Errors:
    ///   - error.IncompleteArchive: Unexpected end of file
    fn skipPadding(self: *TarReader, size: u64) !void {
        const padding = calculatePadding(size);
        if (padding == 0) {
            return;
        }

        // Try to seek (faster than reading)
        self.file.seekBy(@as(i64, @intCast(padding))) catch {
            // If seek fails, read and discard
            var discard_buffer: [512]u8 = undefined;
            const to_read: usize = @intCast(padding);
            const n = try self.file.readAll(discard_buffer[0..to_read]);

            if (n != to_read) {
                return error.IncompleteArchive;
            }
        };

        self.file_position += padding;
    }

    /// Read GNU tar long name extension
    ///
    /// Parameters:
    ///   - tar_header: Header indicating long name follows
    ///
    /// Errors:
    ///   - error.OutOfMemory: Failed to allocate buffer
    ///   - error.IncompleteArchive: Unexpected end of file
    fn readGnuLongName(self: *TarReader, tar_header: *const header.TarHeader) !void {
        const name_size = try tar_header.getSize();

        // Guard against pathological sizes
        if (name_size > MAX_GNU_EXTENSION_SIZE) {
            return error.CorruptedHeader;
        }

        // Free previous long name if any
        if (self.gnu_long_name) |old_name| {
            self.allocator.free(old_name);
        }

        // Allocate buffer for long name
        const name_buffer = try self.allocator.alloc(u8, @intCast(name_size));
        errdefer self.allocator.free(name_buffer);

        // Read name data
        const n = try self.file.readAll(name_buffer);
        if (n != name_size) {
            return error.IncompleteArchive;
        }

        self.file_position += name_size;

        // Skip padding to 512-byte boundary (with seek/read fallback)
        try self.skipPadding(name_size);

        // Remove null terminator if present
        const actual_len = if (name_size > 0 and name_buffer[name_size - 1] == 0)
            name_size - 1
        else
            name_size;

        // Store name (trim to actual length)
        if (actual_len < name_size) {
            const trimmed = try self.allocator.realloc(name_buffer, actual_len);
            self.gnu_long_name = trimmed;
        } else {
            self.gnu_long_name = name_buffer;
        }
    }

    /// Read GNU tar long link extension
    ///
    /// Parameters:
    ///   - tar_header: Header indicating long link follows
    ///
    /// Errors:
    ///   - error.OutOfMemory: Failed to allocate buffer
    ///   - error.IncompleteArchive: Unexpected end of file
    fn readGnuLongLink(self: *TarReader, tar_header: *const header.TarHeader) !void {
        const link_size = try tar_header.getSize();

        // Guard against pathological sizes
        if (link_size > MAX_GNU_EXTENSION_SIZE) {
            return error.CorruptedHeader;
        }

        // Free previous long link if any
        if (self.gnu_long_link) |old_link| {
            self.allocator.free(old_link);
        }

        // Allocate buffer for long link
        const link_buffer = try self.allocator.alloc(u8, @intCast(link_size));
        errdefer self.allocator.free(link_buffer);

        // Read link data
        const n = try self.file.readAll(link_buffer);
        if (n != link_size) {
            return error.IncompleteArchive;
        }

        self.file_position += link_size;

        // Skip padding to 512-byte boundary (with seek/read fallback)
        try self.skipPadding(link_size);

        // Remove null terminator if present
        const actual_len = if (link_size > 0 and link_buffer[link_size - 1] == 0)
            link_size - 1
        else
            link_size;

        // Store link (trim to actual length)
        if (actual_len < link_size) {
            const trimmed = try self.allocator.realloc(link_buffer, actual_len);
            self.gnu_long_link = trimmed;
        } else {
            self.gnu_long_link = link_buffer;
        }
    }

    /// Free entry resources
    fn freeEntry(self: *TarReader, entry: types.Entry) void {
        self.allocator.free(entry.path);
        self.allocator.free(entry.uname);
        self.allocator.free(entry.gname);
        self.allocator.free(entry.link_target);
    }
};

/// TAR + Gzip reader for .tar.gz files
///
/// This struct manages the lifecycle of a tar.gz file extraction:
/// 1. Decompresses the gzip file to a temporary file (streaming)
/// 2. Reads the tar archive from the temporary file
/// 3. Cleans up temporary files on deinit
///
/// Example:
/// ```zig
/// var reader = try TarGzipReader.initGzip(allocator, "archive.tar.gz");
/// defer reader.deinit();
///
/// while (try reader.tar.next()) |entry| {
///     std.debug.print("Entry: {s}\n", .{entry.path});
/// }
/// ```
pub const TarGzipReader = struct {
    allocator: std.mem.Allocator,
    /// Temporary directory for decompressed tar file
    temp_dir: std.testing.TmpDir,
    /// Decompressed tar file
    tar_file: std.fs.File,
    /// TAR reader for the decompressed file
    tar: TarReader,

    /// Initialize a TAR reader for a gzipped TAR file
    ///
    /// This function:
    /// 1. Opens the .tar.gz file
    /// 2. Streams the gzip decompression to a temporary file
    /// 3. Opens the temporary file for tar reading
    ///
    /// Parameters:
    ///   - allocator: Memory allocator
    ///   - gzip_path: Path to the .tar.gz file
    ///
    /// Returns:
    ///   - Initialized TarGzipReader
    ///
    /// Errors:
    ///   - error.FileNotFound: Input file not found
    ///   - error.InvalidGzipMagic: Not a valid gzip file
    ///   - error.OutOfMemory: Failed to allocate resources
    ///
    /// Example:
    /// ```zig
    /// var reader = try TarGzipReader.initGzip(allocator, "archive.tar.gz");
    /// defer reader.deinit();
    ///
    /// while (try reader.tar.next()) |entry| {
    ///     var buffer: [4096]u8 = undefined;
    ///     while (true) {
    ///         const n = try reader.tar.read(&buffer);
    ///         if (n == 0) break;
    ///         // Process decompressed data
    ///     }
    /// }
    /// ```
    pub fn initGzip(allocator: std.mem.Allocator, gzip_path: []const u8) !TarGzipReader {
        // Open the gzipped file
        const gzip_file = try std.fs.cwd().openFile(gzip_path, .{});
        errdefer gzip_file.close();

        // Create temporary directory for decompressed tar file
        var temp_dir = std.testing.tmpDir(.{});
        errdefer temp_dir.cleanup();

        // Create temporary tar file
        const tar_file = try temp_dir.dir.createFile("decompressed.tar", .{ .read = true });
        errdefer tar_file.close();

        // Stream decompress gzip to temporary file
        {
            var gzip_reader = try streaming.GzipReader.init(allocator, gzip_file);
            defer gzip_reader.deinit();

            var buffer: [types.BufferSize.default]u8 = undefined;
            while (true) {
                const n = try gzip_reader.read(&buffer);
                if (n == 0) break;
                try tar_file.writeAll(buffer[0..n]);
            }
        }

        // Close the gzip file (no longer needed)
        gzip_file.close();

        // Seek to beginning of tar file for reading
        try tar_file.seekTo(0);

        // Initialize TAR reader
        const tar = try TarReader.init(allocator, tar_file);

        return TarGzipReader{
            .allocator = allocator,
            .temp_dir = temp_dir,
            .tar_file = tar_file,
            .tar = tar,
        };
    }

    /// Clean up resources
    ///
    /// Closes the tar file, removes temporary directory
    ///
    /// Note: This automatically calls tar.deinit()
    pub fn deinit(self: *TarGzipReader) void {
        self.tar.deinit();
        self.tar_file.close();
        self.temp_dir.cleanup();
    }

    /// Create an ArchiveReader interface from this TarGzipReader
    ///
    /// Delegates to the underlying TarReader's archiveReader() method
    ///
    /// Returns:
    ///   - ArchiveReader wrapping the underlying TarReader
    pub fn archiveReader(self: *TarGzipReader) archive.ArchiveReader {
        return self.tar.archiveReader();
    }
};

/// Check if a block is all zeros
fn isZeroBlock(block: *const [header.TarHeader.BLOCK_SIZE]u8) bool {
    for (block) |byte| {
        if (byte != 0) return false;
    }
    return true;
}

/// Calculate padding bytes to reach 512-byte boundary
fn calculatePadding(size: u64) u64 {
    const remainder = size % header.TarHeader.BLOCK_SIZE;
    if (remainder == 0) {
        return 0;
    }
    return header.TarHeader.BLOCK_SIZE - remainder;
}

// Tests
test "TarReader: basic initialization" {
    const allocator = std.testing.allocator;

    // Create a temporary file
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const file = try tmp_dir.dir.createFile("test.tar", .{ .read = true });
    defer file.close();

    var reader = try TarReader.init(allocator, file);
    defer reader.deinit();

    try std.testing.expectEqual(@as(?types.Entry, null), reader.current_entry);
    try std.testing.expectEqual(@as(u64, 0), reader.remaining_bytes);
}

test "isZeroBlock: all zeros" {
    var block: [512]u8 = undefined;
    @memset(&block, 0);

    try std.testing.expect(isZeroBlock(&block));
}

test "isZeroBlock: not all zeros" {
    var block: [512]u8 = undefined;
    @memset(&block, 0);
    block[256] = 1;

    try std.testing.expect(!isZeroBlock(&block));
}

test "calculatePadding: no padding needed" {
    try std.testing.expectEqual(@as(u64, 0), calculatePadding(512));
    try std.testing.expectEqual(@as(u64, 0), calculatePadding(1024));
    try std.testing.expectEqual(@as(u64, 0), calculatePadding(0));
}

test "calculatePadding: padding needed" {
    try std.testing.expectEqual(@as(u64, 511), calculatePadding(1));
    try std.testing.expectEqual(@as(u64, 256), calculatePadding(256));
    try std.testing.expectEqual(@as(u64, 12), calculatePadding(500));
}

test "TarReader: empty archive (end marker only)" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const file = try tmp_dir.dir.createFile("empty.tar", .{ .read = true });
    defer file.close();

    // Write two zero blocks (end-of-archive marker)
    var zero_block: [512]u8 = undefined;
    @memset(&zero_block, 0);
    try file.writeAll(&zero_block);
    try file.writeAll(&zero_block);
    try file.seekTo(0);

    var reader = try TarReader.init(allocator, file);
    defer reader.deinit();

    const entry = try reader.next();
    try std.testing.expectEqual(@as(?types.Entry, null), entry);
}

test "TarReader: ArchiveReader trait implementation" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const file = try tmp_dir.dir.createFile("trait_test.tar", .{ .read = true });
    defer file.close();

    // Write two zero blocks (end-of-archive marker)
    var zero_block: [512]u8 = undefined;
    @memset(&zero_block, 0);
    try file.writeAll(&zero_block);
    try file.writeAll(&zero_block);
    try file.seekTo(0);

    // Create TarReader and get ArchiveReader interface
    var tar_reader = try TarReader.init(allocator, file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();

    // Test next() through the trait (empty archive returns null)
    const entry = try archive_reader.next();
    try std.testing.expectEqual(@as(?types.Entry, null), entry);

    // Note: We can't test read() when there's no current entry
    // That's tested in the full TarReader tests with actual entries
}

test "TarReader: ArchiveReader polymorphism" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const file = try tmp_dir.dir.createFile("poly_test.tar", .{ .read = true });
    defer file.close();

    // Write end-of-archive marker
    var zero_block: [512]u8 = undefined;
    @memset(&zero_block, 0);
    try file.writeAll(&zero_block);
    try file.writeAll(&zero_block);
    try file.seekTo(0);

    var tar_reader = try TarReader.init(allocator, file);
    defer tar_reader.deinit();

    // This demonstrates that we can pass ArchiveReader to generic functions
    var archive_reader = tar_reader.archiveReader();
    const entries = try archive.readAllEntries(allocator, &archive_reader);
    defer allocator.free(entries);

    try std.testing.expectEqual(@as(usize, 0), entries.len);
}

test "TarGzipReader: decompress and read tar.gz" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create a simple tar file (empty with just end markers)
    const tar_file = try tmp_dir.dir.createFile("test.tar", .{ .read = true });
    defer tar_file.close();

    var zero_block: [512]u8 = undefined;
    @memset(&zero_block, 0);
    try tar_file.writeAll(&zero_block);
    try tar_file.writeAll(&zero_block);
    try tar_file.seekTo(0);

    // Compress it with gzip
    const gz_file = try tmp_dir.dir.createFile("test.tar.gz", .{ .read = true });
    defer gz_file.close();

    {
        var gzip_writer = try streaming.GzipWriter.init(allocator, gz_file, .{});
        defer gzip_writer.deinit();

        var buffer: [4096]u8 = undefined;
        while (true) {
            const n = try tar_file.read(&buffer);
            if (n == 0) break;
            try gzip_writer.writeAll(buffer[0..n]);
        }
        try gzip_writer.finish();
    }

    // Get the absolute path for the tar.gz file
    const gz_path = try tmp_dir.dir.realpathAlloc(allocator, "test.tar.gz");
    defer allocator.free(gz_path);

    // Now test reading the tar.gz file
    var reader = try TarGzipReader.initGzip(allocator, gz_path);
    defer reader.deinit();

    // Should be able to read entries (empty archive)
    const entry = try reader.tar.next();
    try std.testing.expectEqual(@as(?types.Entry, null), entry);
}
