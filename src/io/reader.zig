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
const crc = std.hash.crc;

/// Buffered reader with seeking support for efficient archive reading
///
/// This reader provides:
/// - Configurable buffer sizes for different file types
/// - Seeking capabilities for random access
/// - Efficient buffering to minimize system calls
/// - CRC32 checksum calculation (optional)
pub const BufferedReader = struct {
    /// Underlying file handle
    file: std.fs.File,

    /// Allocator for buffer management
    allocator: std.mem.Allocator,

    /// Internal read buffer
    buffer: []u8,

    /// Current position within buffer
    buffer_pos: usize,

    /// Number of valid bytes in buffer
    buffer_end: usize,

    /// Current file position (absolute)
    file_pos: u64,

    /// Total bytes read (for statistics)
    total_bytes_read: u64,

    /// CRC32 state (if enabled)
    crc32_state: ?crc.Crc32,

    /// Initialize a buffered reader with custom buffer size
    ///
    /// Parameters:
    ///   - allocator: Memory allocator
    ///   - file: File handle to read from
    ///   - buffer_size: Size of the read buffer
    ///
    /// Returns:
    ///   - Initialized BufferedReader
    ///
    /// Errors:
    ///   - error.OutOfMemory: Failed to allocate buffer
    pub fn init(
        allocator: std.mem.Allocator,
        file: std.fs.File,
        buffer_size: usize,
    ) !BufferedReader {
        const buffer = try allocator.alloc(u8, buffer_size);
        errdefer allocator.free(buffer);

        return BufferedReader{
            .file = file,
            .allocator = allocator,
            .buffer = buffer,
            .buffer_pos = 0,
            .buffer_end = 0,
            .file_pos = try file.getPos(),
            .total_bytes_read = 0,
            .crc32_state = null,
        };
    }

    /// Initialize with default buffer size
    pub fn initDefault(
        allocator: std.mem.Allocator,
        file: std.fs.File,
    ) !BufferedReader {
        return init(allocator, file, types.BufferSize.default);
    }

    /// Clean up resources
    pub fn deinit(self: *BufferedReader) void {
        self.allocator.free(self.buffer);
    }

    /// Enable CRC32 checksum calculation
    pub fn enableCrc32(self: *BufferedReader) void {
        self.crc32_state = crc.Crc32.init();
    }

    /// Get current CRC32 checksum
    pub fn getCrc32(self: *BufferedReader) ?u32 {
        if (self.crc32_state) |st| return st.final();
        return null;
    }

    /// Reset CRC32 checksum
    pub fn resetCrc32(self: *BufferedReader) void {
        if (self.crc32_state) |*st| st.* = crc.Crc32.init();
    }

    /// Read data into the provided buffer
    ///
    /// Parameters:
    ///   - dest: Destination buffer
    ///
    /// Returns:
    ///   - Number of bytes read (0 = EOF)
    ///
    /// Errors:
    ///   - error.ReadError: Failed to read from file
    pub fn read(self: *BufferedReader, dest: []u8) !usize {
        if (dest.len == 0) return 0;

        var total_read: usize = 0;

        while (total_read < dest.len) {
            // Check if we need to refill the buffer
            if (self.buffer_pos >= self.buffer_end) {
                try self.fillBuffer();
                if (self.buffer_end == 0) {
                    // EOF reached
                    break;
                }
            }

            // Copy from buffer to destination
            const available = self.buffer_end - self.buffer_pos;
            const to_copy = @min(available, dest.len - total_read);

            @memcpy(
                dest[total_read .. total_read + to_copy],
                self.buffer[self.buffer_pos .. self.buffer_pos + to_copy],
            );

            self.buffer_pos += to_copy;
            total_read += to_copy;
            self.total_bytes_read += to_copy;

            // Update CRC32 if enabled
            if (self.crc32_state != null) {
                self.updateCrc32(dest[total_read - to_copy .. total_read]);
            }
        }

        return total_read;
    }

    /// Read exactly the requested number of bytes
    ///
    /// Parameters:
    ///   - dest: Destination buffer
    ///
    /// Returns:
    ///   - void on success
    ///
    /// Errors:
    ///   - error.UnexpectedEOF: Not enough data available
    ///   - error.ReadError: Failed to read from file
    pub fn readAll(self: *BufferedReader, dest: []u8) !void {
        const bytes_read = try self.read(dest);
        if (bytes_read < dest.len) {
            return error.UnexpectedEOF;
        }
    }

    /// Read a single byte
    ///
    /// Returns:
    ///   - The byte read
    ///
    /// Errors:
    ///   - error.UnexpectedEOF: No more data available
    ///   - error.ReadError: Failed to read from file
    pub fn readByte(self: *BufferedReader) !u8 {
        var byte: [1]u8 = undefined;
        try self.readAll(&byte);
        return byte[0];
    }

    /// Skip the specified number of bytes
    ///
    /// Parameters:
    ///   - count: Number of bytes to skip
    ///
    /// Errors:
    ///   - error.SeekError: Failed to seek
    pub fn skip(self: *BufferedReader, count: u64) !void {
        // Try to skip within buffer first
        const available_u64: u64 = @as(u64, @intCast(self.buffer_end - self.buffer_pos));
        if (count <= available_u64) {
            self.buffer_pos += @as(usize, @intCast(count));
            self.total_bytes_read += count;
            return;
        }

        // Skip remaining in buffer
        self.buffer_pos = self.buffer_end;
        self.total_bytes_read += available_u64;

        // Seek file position
        const remaining: u64 = count - available_u64;
        try self.seekBy(@as(i64, @intCast(remaining)));
    }

    /// Seek to absolute position
    ///
    /// Parameters:
    ///   - pos: Absolute position to seek to
    ///
    /// Errors:
    ///   - error.SeekError: Failed to seek
    pub fn seekTo(self: *BufferedReader, pos: u64) !void {
        try self.file.seekTo(pos);
        self.file_pos = pos;
        self.buffer_pos = 0;
        self.buffer_end = 0;
    }

    /// Seek relative to current position
    ///
    /// Parameters:
    ///   - offset: Offset from current position (can be negative)
    ///
    /// Errors:
    ///   - error.SeekError: Failed to seek
    pub fn seekBy(self: *BufferedReader, offset: i64) !void {
        const current_pos = try self.getPos();
        const new_pos = if (offset < 0) blk: {
            const back: u64 = @as(u64, @intCast(-offset));
            if (back > current_pos) return error.SeekError;
            break :blk current_pos - back;
        } else current_pos + @as(u64, @intCast(offset));

        try self.seekTo(new_pos);
    }

    /// Get current absolute position
    ///
    /// Returns:
    ///   - Current position in the file
    pub fn getPos(self: *BufferedReader) !u64 {
        const buffered_bytes = self.buffer_end - self.buffer_pos;
        return self.file_pos - buffered_bytes;
    }

    /// Get total bytes read
    pub fn getTotalBytesRead(self: *BufferedReader) u64 {
        return self.total_bytes_read;
    }

    /// Get file size
    ///
    /// Returns:
    ///   - File size in bytes
    ///
    /// Errors:
    ///   - error.SeekError: Failed to get file size
    pub fn getFileSize(self: *BufferedReader) !u64 {
        return try self.file.getEndPos();
    }

    /// Check if at end of file
    ///
    /// Returns:
    ///   - true if at EOF, false otherwise
    pub fn isEof(self: *BufferedReader) !bool {
        if (self.buffer_pos < self.buffer_end) {
            return false;
        }

        try self.fillBuffer();
        return self.buffer_end == 0;
    }

    /// Fill internal buffer from file
    fn fillBuffer(self: *BufferedReader) !void {
        self.buffer_pos = 0;
        self.buffer_end = 0;

        const bytes_read = try self.file.read(self.buffer);
        self.buffer_end = bytes_read;
        self.file_pos += bytes_read;
    }

    /// Update CRC32 checksum
    fn updateCrc32(self: *BufferedReader, data: []const u8) void {
        if (self.crc32_state) |*st| st.update(data);
    }
};

/// Create a buffered reader with adaptive buffer size based on file size
///
/// Parameters:
///   - allocator: Memory allocator
///   - file: File handle to read from
///
/// Returns:
///   - Initialized BufferedReader with optimized buffer size
///
/// Errors:
///   - error.OutOfMemory: Failed to allocate buffer
///   - error.SeekError: Failed to get file size
pub fn createAdaptiveReader(
    allocator: std.mem.Allocator,
    file: std.fs.File,
) !BufferedReader {
    const file_size = try file.getEndPos();

    const buffer_size = if (file_size < 100 * 1024)
        types.BufferSize.small
    else if (file_size < 10 * 1024 * 1024)
        types.BufferSize.default
    else if (file_size < 100 * 1024 * 1024)
        types.BufferSize.large
    else
        types.BufferSize.huge;

    return try BufferedReader.init(allocator, file, buffer_size);
}

// Tests
test "BufferedReader: basic read" {
    const allocator = std.testing.allocator;

    // Create temporary test file
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_data = "Hello, World! This is a test.";
    var file = try tmp_dir.dir.createFile("test.txt", .{ .read = true });
    defer file.close();

    try file.writeAll(test_data);
    try file.seekTo(0);

    // Test buffered reader
    var reader = try BufferedReader.init(allocator, file, 16);
    defer reader.deinit();

    var buffer: [50]u8 = undefined;
    const bytes_read = try reader.read(&buffer);

    try std.testing.expectEqual(test_data.len, bytes_read);
    try std.testing.expectEqualStrings(test_data, buffer[0..bytes_read]);
}

test "BufferedReader: readAll" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const test_data = "Test data";
    var file = try tmp_dir.dir.createFile("test.txt", .{ .read = true });
    defer file.close();

    try file.writeAll(test_data);
    try file.seekTo(0);

    var reader = try BufferedReader.initDefault(allocator, file);
    defer reader.deinit();

    var buffer: [9]u8 = undefined;
    try reader.readAll(&buffer);

    try std.testing.expectEqualStrings(test_data, &buffer);

    // Test UnexpectedEOF
    var extra: [1]u8 = undefined;
    try std.testing.expectError(error.UnexpectedEOF, reader.readAll(&extra));
}

test "BufferedReader: readByte" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var file = try tmp_dir.dir.createFile("test.txt", .{ .read = true });
    defer file.close();

    try file.writeAll("ABC");
    try file.seekTo(0);

    var reader = try BufferedReader.initDefault(allocator, file);
    defer reader.deinit();

    try std.testing.expectEqual(@as(u8, 'A'), try reader.readByte());
    try std.testing.expectEqual(@as(u8, 'B'), try reader.readByte());
    try std.testing.expectEqual(@as(u8, 'C'), try reader.readByte());

    try std.testing.expectError(error.UnexpectedEOF, reader.readByte());
}

test "BufferedReader: seeking" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var file = try tmp_dir.dir.createFile("test.txt", .{ .read = true });
    defer file.close();

    try file.writeAll("0123456789");
    try file.seekTo(0);

    var reader = try BufferedReader.initDefault(allocator, file);
    defer reader.deinit();

    // Seek to position 5
    try reader.seekTo(5);
    try std.testing.expectEqual(@as(u8, '5'), try reader.readByte());

    // Seek forward by 2
    try reader.seekBy(2);
    try std.testing.expectEqual(@as(u8, '8'), try reader.readByte());

    // Seek backward by 5
    try reader.seekBy(-5);
    try std.testing.expectEqual(@as(u8, '4'), try reader.readByte());
}

test "BufferedReader: skip" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var file = try tmp_dir.dir.createFile("test.txt", .{ .read = true });
    defer file.close();

    try file.writeAll("0123456789");
    try file.seekTo(0);

    var reader = try BufferedReader.init(allocator, file, 4);
    defer reader.deinit();

    try reader.skip(3);
    try std.testing.expectEqual(@as(u8, '3'), try reader.readByte());

    try reader.skip(2);
    try std.testing.expectEqual(@as(u8, '6'), try reader.readByte());
}

test "BufferedReader: getPos and isEof" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var file = try tmp_dir.dir.createFile("test.txt", .{ .read = true });
    defer file.close();

    try file.writeAll("Hello");
    try file.seekTo(0);

    var reader = try BufferedReader.initDefault(allocator, file);
    defer reader.deinit();

    try std.testing.expectEqual(@as(u64, 0), try reader.getPos());
    try std.testing.expect(!try reader.isEof());

    _ = try reader.readByte();
    try std.testing.expectEqual(@as(u64, 1), try reader.getPos());

    try reader.seekTo(5);
    try std.testing.expect(try reader.isEof());
}

test "createAdaptiveReader: buffer size selection" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Small file (< 100KB)
    var small_file = try tmp_dir.dir.createFile("small.txt", .{ .read = true });
    defer small_file.close();
    const buf = [_]u8{'x'} ** 50;
    try small_file.writeAll(&buf);
    try small_file.seekTo(0);

    var small_reader = try createAdaptiveReader(allocator, small_file);
    defer small_reader.deinit();
    try std.testing.expectEqual(types.BufferSize.small, small_reader.buffer.len);
}
