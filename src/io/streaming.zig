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

//! Streaming I/O for compression/decompression
//!
//! This module provides streaming interfaces for gzip compression and decompression
//! enabling memory-efficient processing of large files without loading entire contents
//! into memory.
//!
//! Architecture:
//!   Extraction (tar.gz → files):
//!     FileReader → GzipReader → TarReader → Files
//!
//!   Compression (files → tar.gz):
//!     Files → TarWriter → GzipWriter → FileWriter

const std = @import("std");
const gzip = @import("../compress/gzip.zig");
const crc32_mod = @import("../compress/crc32.zig");
const zlib = @import("../compress/zlib.zig");

/// Default buffer size for streaming operations (64KB)
pub const default_buffer_size = 64 * 1024;

/// Streaming gzip reader for decompression
///
/// This reader wraps an underlying file/reader and provides transparent
/// gzip decompression in a streaming fashion.
///
/// Memory usage: O(1) - uses fixed-size buffers regardless of file size
///
/// Example:
/// ```zig
/// var file = try std.fs.cwd().openFile("archive.tar.gz", .{});
/// defer file.close();
///
/// var gzip_reader = try GzipReader.init(allocator, file);
/// defer gzip_reader.deinit();
///
/// var buffer: [4096]u8 = undefined;
/// while (true) {
///     const n = try gzip_reader.read(&buffer);
///     if (n == 0) break; // EOF
///     // Process decompressed data in buffer[0..n]
/// }
/// ```
pub const GzipReader = struct {
    allocator: std.mem.Allocator,
    inner: std.fs.File,
    file_read_buffer: []u8,
    file_reader: std.fs.File.Reader,
    decompress_buffer: []u8,
    header: gzip.Header,
    decompressor: std.compress.flate.Decompress,
    crc32: crc32_mod.Crc32,
    uncompressed_size: u32,
    finished: bool,
    footer_validated: bool,

    /// Initialize a gzip streaming reader
    ///
    /// Parameters:
    ///   - allocator: Memory allocator
    ///   - file: File to read from
    ///
    /// Returns:
    ///   - Initialized GzipReader
    ///
    /// Errors:
    ///   - error.InvalidGzipMagic: Not a valid gzip file
    ///   - error.UnsupportedCompressionMethod: Unsupported compression
    pub fn init(allocator: std.mem.Allocator, file: std.fs.File) !GzipReader {
        // Allocate buffer for file reader (required by file.reader in Zig 0.15)
        const file_read_buffer = try allocator.alloc(u8, 4096);
        errdefer allocator.free(file_read_buffer);

        // Create reader from file
        const file_reader = file.reader(file_read_buffer);

        // Parse gzip header
        var reader_interface = file_reader.interface;
        var header = try gzip.Header.parse(allocator, &reader_interface);
        errdefer header.deinit(allocator);

        // Allocate buffer for decompressor (required by Decompress.init)
        const decompress_buffer = try allocator.alloc(u8, std.compress.flate.max_window_len);
        errdefer allocator.free(decompress_buffer);

        // Create decompressor for gzip container
        const decompressor = std.compress.flate.Decompress.init(
            &reader_interface,
            .gzip,
            decompress_buffer,
        );

        return GzipReader{
            .allocator = allocator,
            .inner = file,
            .file_read_buffer = file_read_buffer,
            .file_reader = file_reader,
            .decompress_buffer = decompress_buffer,
            .header = header,
            .decompressor = decompressor,
            .crc32 = crc32_mod.Crc32.init(),
            .uncompressed_size = 0,
            .finished = false,
            .footer_validated = false,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *GzipReader) void {
        self.header.deinit(self.allocator);
        self.allocator.free(self.file_read_buffer);
        self.allocator.free(self.decompress_buffer);
    }

    /// Read decompressed data
    ///
    /// Parameters:
    ///   - dest: Destination buffer
    ///
    /// Returns:
    ///   - Number of bytes read (0 = EOF)
    ///
    /// Errors:
    ///   - Various I/O and decompression errors
    pub fn read(self: *GzipReader, dest: []u8) !usize {
        if (self.finished) {
            // Validate footer if not already done
            if (!self.footer_validated) {
                try self.validateFooter();
            }
            return 0;
        }

        // Read and decompress data using readSliceShort
        // This returns the number of bytes read, which is less than dest.len only at EOF
        const n = try self.decompressor.reader.readSliceShort(dest);

        // If we read fewer bytes than requested, we've reached EOF
        if (n < dest.len) {
            self.finished = true;
            if (!self.footer_validated) {
                try self.validateFooter();
            }
        }

        // Update CRC32 and size
        if (n > 0) {
            self.crc32.update(dest[0..n]);
            self.uncompressed_size +%= @truncate(n);
        }

        return n;
    }

    /// Read all remaining data
    ///
    /// Parameters:
    ///   - dest: Destination buffer
    ///
    /// Errors:
    ///   - error.UnexpectedEOF: Not enough data
    pub fn readAll(self: *GzipReader, dest: []u8) !void {
        var pos: usize = 0;
        while (pos < dest.len) {
            const n = try self.read(dest[pos..]);
            if (n == 0) return error.UnexpectedEOF;
            pos += n;
        }
    }

    /// Get the gzip header information
    pub fn getHeader(self: *GzipReader) *const gzip.Header {
        return &self.header;
    }

    /// Get current CRC32 value
    pub fn getCrc32(self: *GzipReader) u32 {
        return self.crc32.final();
    }

    /// Get uncompressed size so far
    pub fn getUncompressedSize(self: *GzipReader) u32 {
        return self.uncompressed_size;
    }

    /// Validate gzip footer (CRC32 and size)
    fn validateFooter(self: *GzipReader) !void {
        if (self.footer_validated) return;

        // Read footer from current file position using the file reader's interface
        var reader_interface = self.file_reader.interface;
        const footer = try gzip.Footer.parse(&reader_interface);

        // Validate CRC32
        const calculated_crc32 = self.crc32.final();
        if (footer.crc32 != calculated_crc32) {
            return error.ChecksumMismatch;
        }

        // Validate size (modulo 2^32)
        if (footer.isize != self.uncompressed_size) {
            return error.SizeMismatch;
        }

        self.footer_validated = true;
    }
};

/// Streaming gzip writer for compression
///
/// This writer wraps an underlying file/writer and provides transparent
/// gzip compression in a streaming fashion.
///
/// Memory usage: O(1) - uses fixed-size buffers regardless of data size
///
/// Example:
/// ```zig
/// var file = try std.fs.cwd().createFile("output.tar.gz", .{});
/// defer file.close();
///
/// var gzip_writer = try GzipWriter.init(allocator, file, .{});
/// defer gzip_writer.deinit();
///
/// try gzip_writer.write(data);
/// try gzip_writer.finish(); // Flush and write footer
/// ```
pub const GzipWriter = struct {
    allocator: std.mem.Allocator,
    inner: std.fs.File,
    file_write_buffer: []u8,
    file_writer: std.fs.File.Writer,
    buffer: []u8,
    compressor: std.compress.flate.Compress,
    crc32: crc32_mod.Crc32,
    uncompressed_size: u32,
    finished: bool,
    compression_level: u8,

    /// Gzip writer options
    pub const Options = struct {
        /// Compression level (1-9, 6 is default)
        level: u8 = 6,
        /// Original filename (optional)
        filename: ?[]const u8 = null,
        /// File comment (optional)
        comment: ?[]const u8 = null,
        /// Modification time (0 = not available)
        mtime: u32 = 0,
    };

    /// Initialize a gzip streaming writer
    ///
    /// Parameters:
    ///   - allocator: Memory allocator
    ///   - file: File to write to
    ///   - options: Compression options
    ///
    /// Returns:
    ///   - Initialized GzipWriter
    ///
    /// Errors:
    ///   - error.OutOfMemory: Failed to allocate resources
    ///   - error.WriteError: Failed to write header
    pub fn init(allocator: std.mem.Allocator, file: std.fs.File, options: Options) !GzipWriter {
        // Allocate buffer for file writer (required by file.writer in Zig 0.15)
        const file_write_buffer = try allocator.alloc(u8, 4096);
        errdefer allocator.free(file_write_buffer);

        // Create writer from file
        var file_writer = file.writer(file_write_buffer);

        // Build and write gzip header
        const header = gzip.Header{
            .compression_method = gzip.compression_method_deflate,
            .flags = .{
                .fname = options.filename != null,
                .fcomment = options.comment != null,
            },
            .mtime = options.mtime,
            .extra_flags = if (options.level >= 9)
                .max_compression
            else if (options.level <= 2)
                .fast_compression
            else
                .default,
            .os = switch (@import("builtin").os.tag) {
                .windows => .ntfs,
                .macos => .macintosh,
                else => .unix,
            },
            .filename = options.filename,
            .comment = options.comment,
        };

        // Write header using the file writer's interface
        // Need a mutable copy for writeAll which requires *Writer
        var writer_interface = file_writer.interface;
        try header.write(&writer_interface);

        // Allocate buffer for compressor (required by Compress.init)
        const buffer = try allocator.alloc(u8, 64 * 1024);
        errdefer allocator.free(buffer);

        // Determine compression level
        const level: std.compress.flate.Compress.Level = switch (options.level) {
            1 => .fast,
            2...5 => .default,
            6...9 => .best,
            else => .default,
        };

        // Initialize compressor using Compress.init(output: *Writer, buffer: []u8, options: Options)
        // Pass the file writer's interface directly
        const compressor = std.compress.flate.Compress.init(
            &file_writer.interface,
            buffer,
            .{
                .level = level,
                .container = .gzip,
            },
        );

        return GzipWriter{
            .allocator = allocator,
            .inner = file,
            .file_write_buffer = file_write_buffer,
            .file_writer = file_writer,
            .buffer = buffer,
            .compressor = compressor,
            .crc32 = crc32_mod.Crc32.init(),
            .uncompressed_size = 0,
            .finished = false,
            .compression_level = options.level,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *GzipWriter) void {
        // Attempt to finish if not already done
        if (!self.finished) {
            self.finish() catch {};
        }
        // Free the buffers
        self.allocator.free(self.buffer);
        self.allocator.free(self.file_write_buffer);
    }

    /// Write uncompressed data
    ///
    /// Parameters:
    ///   - data: Data to compress and write
    ///
    /// Returns:
    ///   - Number of bytes written
    ///
    /// Errors:
    ///   - error.AlreadyFinished: Writer was already finished
    ///   - Various I/O and compression errors
    pub fn write(self: *GzipWriter, data: []const u8) !usize {
        if (self.finished) return error.AlreadyFinished;

        // Update CRC32 and size
        self.crc32.update(data);
        self.uncompressed_size +%= @truncate(data.len);

        // Compress and write using the compressor's writer field
        try self.compressor.writer.writeAll(data);

        return data.len;
    }

    /// Write all data
    pub fn writeAll(self: *GzipWriter, data: []const u8) !void {
        const written = try self.write(data);
        if (written != data.len) {
            return error.WriteError;
        }
    }

    /// Finish compression and write footer
    ///
    /// This must be called before closing the file to ensure
    /// all data is flushed and the footer is written correctly.
    ///
    /// Errors:
    ///   - error.AlreadyFinished: Already called
    ///   - Various I/O errors
    pub fn finish(self: *GzipWriter) !void {
        if (self.finished) return error.AlreadyFinished;

        // End compression (flushes all data and writes final block)
        try self.compressor.end();

        // Write gzip footer
        const footer = gzip.Footer{
            .crc32 = self.crc32.final(),
            .isize = self.uncompressed_size,
        };

        // Write footer using the file writer's interface
        var writer_interface = self.file_writer.interface;
        try footer.write(&writer_interface);

        self.finished = true;
    }

    /// Get current CRC32 value
    pub fn getCrc32(self: *GzipWriter) u32 {
        return self.crc32.final();
    }

    /// Get uncompressed size written so far
    pub fn getUncompressedSize(self: *GzipWriter) u32 {
        return self.uncompressed_size;
    }
};

// Tests

test "GzipReader: stream decompression" {
    const allocator = std.testing.allocator;

    // Create a compressed gzip file
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_data = "Hello, World! This is streaming compression test data.";

    // First create a compressed file
    var compressed_file = try tmp_dir.dir.createFile("test.gz", .{ .read = true });
    defer compressed_file.close();

    {
        var writer = try GzipWriter.init(allocator, compressed_file, .{});
        defer writer.deinit();

        try writer.writeAll(test_data);
        try writer.finish();
    }

    // Now test reading it back
    try compressed_file.seekTo(0);

    var reader = try GzipReader.init(allocator, compressed_file);
    defer reader.deinit();

    var decompressed = std.array_list.Aligned(u8, null).empty;
    defer decompressed.deinit(allocator);

    var buffer: [16]u8 = undefined;
    while (true) {
        const n = try reader.read(&buffer);
        if (n == 0) break;
        try decompressed.appendSlice(allocator, buffer[0..n]);
    }

    try std.testing.expectEqualStrings(test_data, decompressed.items);
}

test "GzipWriter: stream compression" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var file = try tmp_dir.dir.createFile("test.gz", .{ .read = true });
    defer file.close();

    const test_data = "Test data for streaming compression";

    // Write compressed data
    {
        var writer = try GzipWriter.init(allocator, file, .{
            .level = 6,
            .filename = "test.txt",
        });
        defer writer.deinit();

        try writer.writeAll(test_data);
        try writer.finish();
    }

    // Verify by reading back
    try file.seekTo(0);

    var reader = try GzipReader.init(allocator, file);
    defer reader.deinit();

    var buffer: [256]u8 = undefined;
    const n = try reader.read(&buffer);

    try std.testing.expectEqualStrings(test_data, buffer[0..n]);
    try std.testing.expectEqualStrings("test.txt", reader.getHeader().filename.?);
}

test "GzipWriter: multiple writes" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var file = try tmp_dir.dir.createFile("test.gz", .{ .read = true });
    defer file.close();

    // Write in chunks
    {
        var writer = try GzipWriter.init(allocator, file, .{});
        defer writer.deinit();

        try writer.writeAll("Part 1, ");
        try writer.writeAll("Part 2, ");
        try writer.writeAll("Part 3");
        try writer.finish();
    }

    // Read back
    try file.seekTo(0);

    var reader = try GzipReader.init(allocator, file);
    defer reader.deinit();

    var buffer: [256]u8 = undefined;
    const n = try reader.read(&buffer);

    try std.testing.expectEqualStrings("Part 1, Part 2, Part 3", buffer[0..n]);
}

test "GzipReader: CRC32 validation" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_data = "Data for CRC validation test";

    // Create valid gzip file
    var file = try tmp_dir.dir.createFile("valid.gz", .{ .read = true });
    defer file.close();

    {
        var writer = try GzipWriter.init(allocator, file, .{});
        defer writer.deinit();

        try writer.writeAll(test_data);
        try writer.finish();
    }

    // Read and verify CRC is validated
    try file.seekTo(0);

    var reader = try GzipReader.init(allocator, file);
    defer reader.deinit();

    var buffer: [256]u8 = undefined;
    const n = try reader.read(&buffer);

    try std.testing.expectEqualStrings(test_data, buffer[0..n]);

    // Read to EOF to trigger footer validation
    const eof = try reader.read(&buffer);
    try std.testing.expectEqual(@as(usize, 0), eof);
}

test "GzipWriter: compression levels" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_data = "Test data " ** 100; // Repeat to make compression meaningful

    // Test different compression levels
    const levels = [_]u8{ 1, 6, 9 };

    for (levels) |level| {
        var filename_buf: [32]u8 = undefined;
        const filename = try std.fmt.bufPrint(&filename_buf, "test_level_{d}.gz", .{level});

        var file = try tmp_dir.dir.createFile(filename, .{ .read = true });
        defer file.close();

        var writer = try GzipWriter.init(allocator, file, .{ .level = level });
        defer writer.deinit();

        try writer.writeAll(test_data);
        try writer.finish();

        // Verify decompression works
        try file.seekTo(0);

        var reader = try GzipReader.init(allocator, file);
        defer reader.deinit();

        const buffer = try allocator.alloc(u8, test_data.len);
        defer allocator.free(buffer);

        try reader.readAll(buffer);
        try std.testing.expectEqualStrings(test_data, buffer);
    }
}
