const std = @import("std");
const types = @import("../core/types.zig");
const errors = @import("../core/errors.zig");

/// Buffered writer for efficient file output
///
/// This writer provides:
/// - Configurable buffer sizes for different scenarios
/// - Automatic flushing when buffer is full
/// - CRC32 checksum calculation (optional)
/// - Statistics tracking
pub const BufferedWriter = struct {
    /// Underlying file handle
    file: std.fs.File,

    /// Allocator for buffer management
    allocator: std.mem.Allocator,

    /// Internal write buffer
    buffer: []u8,

    /// Current position within buffer
    buffer_pos: usize,

    /// Total bytes written (for statistics)
    total_bytes_written: u64,

    /// CRC32 checksum (if enabled)
    crc32: ?u32,

    /// Enable CRC32 calculation
    enable_crc: bool,

    /// Initialize a buffered writer with custom buffer size
    ///
    /// Parameters:
    ///   - allocator: Memory allocator
    ///   - file: File handle to write to
    ///   - buffer_size: Size of the write buffer
    ///
    /// Returns:
    ///   - Initialized BufferedWriter
    ///
    /// Errors:
    ///   - error.OutOfMemory: Failed to allocate buffer
    pub fn init(
        allocator: std.mem.Allocator,
        file: std.fs.File,
        buffer_size: usize,
    ) !BufferedWriter {
        const buffer = try allocator.alloc(u8, buffer_size);
        errdefer allocator.free(buffer);

        return BufferedWriter{
            .file = file,
            .allocator = allocator,
            .buffer = buffer,
            .buffer_pos = 0,
            .total_bytes_written = 0,
            .crc32 = null,
            .enable_crc = false,
        };
    }

    /// Initialize with default buffer size
    pub fn initDefault(
        allocator: std.mem.Allocator,
        file: std.fs.File,
    ) !BufferedWriter {
        return init(allocator, file, types.BufferSize.default);
    }

    /// Clean up resources and flush any remaining data
    pub fn deinit(self: *BufferedWriter) void {
        self.flush() catch {};
        self.allocator.free(self.buffer);
    }

    /// Enable CRC32 checksum calculation
    pub fn enableCrc32(self: *BufferedWriter) void {
        self.enable_crc = true;
        self.crc32 = 0;
    }

    /// Get current CRC32 checksum
    pub fn getCrc32(self: *BufferedWriter) ?u32 {
        return self.crc32;
    }

    /// Reset CRC32 checksum
    pub fn resetCrc32(self: *BufferedWriter) void {
        self.crc32 = 0;
    }

    /// Write data from the provided buffer
    ///
    /// Parameters:
    ///   - data: Data to write
    ///
    /// Returns:
    ///   - Number of bytes written
    ///
    /// Errors:
    ///   - error.WriteError: Failed to write to file
    pub fn write(self: *BufferedWriter, data: []const u8) !usize {
        if (data.len == 0) return 0;

        var total_written: usize = 0;

        // Update CRC32 if enabled
        if (self.enable_crc) {
            self.updateCrc32(data);
        }

        while (total_written < data.len) {
            const available = self.buffer.len - self.buffer_pos;
            const to_copy = @min(available, data.len - total_written);

            // Copy to buffer
            @memcpy(
                self.buffer[self.buffer_pos .. self.buffer_pos + to_copy],
                data[total_written .. total_written + to_copy],
            );

            self.buffer_pos += to_copy;
            total_written += to_copy;
            self.total_bytes_written += to_copy;

            // Flush if buffer is full
            if (self.buffer_pos >= self.buffer.len) {
                try self.flush();
            }
        }

        return total_written;
    }

    /// Write all data from the provided buffer
    ///
    /// Parameters:
    ///   - data: Data to write
    ///
    /// Errors:
    ///   - error.WriteError: Failed to write to file
    pub fn writeAll(self: *BufferedWriter, data: []const u8) !void {
        const written = try self.write(data);
        if (written != data.len) {
            return error.WriteError;
        }
    }

    /// Write a single byte
    ///
    /// Parameters:
    ///   - byte: Byte to write
    ///
    /// Errors:
    ///   - error.WriteError: Failed to write to file
    pub fn writeByte(self: *BufferedWriter, byte: u8) !void {
        const data = [_]u8{byte};
        try self.writeAll(&data);
    }

    /// Write integer in little-endian format
    ///
    /// Parameters:
    ///   - value: Integer value to write
    ///
    /// Errors:
    ///   - error.WriteError: Failed to write to file
    pub fn writeIntLittle(self: *BufferedWriter, comptime T: type, value: T) !void {
        var bytes: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &bytes, value, .little);
        try self.writeAll(&bytes);
    }

    /// Write integer in big-endian format
    ///
    /// Parameters:
    ///   - value: Integer value to write
    ///
    /// Errors:
    ///   - error.WriteError: Failed to write to file
    pub fn writeIntBig(self: *BufferedWriter, comptime T: type, value: T) !void {
        var bytes: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &bytes, value, .big);
        try self.writeAll(&bytes);
    }

    /// Write zeros (padding)
    ///
    /// Parameters:
    ///   - count: Number of zero bytes to write
    ///
    /// Errors:
    ///   - error.WriteError: Failed to write to file
    ///   - error.OutOfMemory: Failed to allocate padding buffer
    pub fn writeZeros(self: *BufferedWriter, count: usize) !void {
        // For small counts, use stack allocation
        if (count <= 256) {
            var zeros = [_]u8{0} ** 256;
            try self.writeAll(zeros[0..count]);
            return;
        }

        // For larger counts, use heap allocation
        const zeros = try self.allocator.alloc(u8, count);
        defer self.allocator.free(zeros);
        @memset(zeros, 0);
        try self.writeAll(zeros);
    }

    /// Flush buffered data to file
    ///
    /// Errors:
    ///   - error.WriteError: Failed to write to file
    pub fn flush(self: *BufferedWriter) !void {
        if (self.buffer_pos == 0) return;

        try self.file.writeAll(self.buffer[0..self.buffer_pos]);
        self.buffer_pos = 0;
    }

    /// Get total bytes written
    pub fn getTotalBytesWritten(self: *BufferedWriter) u64 {
        return self.total_bytes_written;
    }

    /// Get current position in file
    ///
    /// Returns:
    ///   - Current position including buffered data
    ///
    /// Errors:
    ///   - error.SeekError: Failed to get file position
    pub fn getPos(self: *BufferedWriter) !u64 {
        const file_pos = try self.file.getPos();
        return file_pos + self.buffer_pos;
    }

    /// Align to specified boundary by writing zeros
    ///
    /// Parameters:
    ///   - alignment: Alignment boundary (must be power of 2)
    ///
    /// Errors:
    ///   - error.WriteError: Failed to write to file
    ///   - error.InvalidArgument: alignment is not power of 2
    pub fn alignTo(self: *BufferedWriter, alignment: usize) !void {
        if (!std.math.isPowerOfTwo(alignment)) {
            return error.InvalidArgument;
        }

        const current_pos = try self.getPos();
        const remainder = current_pos % alignment;

        if (remainder != 0) {
            const padding = alignment - remainder;
            try self.writeZeros(padding);
        }
    }

    /// Update CRC32 checksum
    fn updateCrc32(self: *BufferedWriter, data: []const u8) void {
        if (self.crc32) |*crc| {
            crc.* = std.hash.Crc32.hash(data);
        }
    }
};

/// Create a buffered writer with adaptive buffer size
///
/// Parameters:
///   - allocator: Memory allocator
///   - file: File handle to write to
///   - expected_size: Expected total size to write (0 if unknown)
///
/// Returns:
///   - Initialized BufferedWriter with optimized buffer size
///
/// Errors:
///   - error.OutOfMemory: Failed to allocate buffer
pub fn createAdaptiveWriter(
    allocator: std.mem.Allocator,
    file: std.fs.File,
    expected_size: u64,
) !BufferedWriter {
    const buffer_size = if (expected_size < 100 * 1024)
        types.BufferSize.small
    else if (expected_size < 10 * 1024 * 1024)
        types.BufferSize.default
    else if (expected_size < 100 * 1024 * 1024)
        types.BufferSize.large
    else
        types.BufferSize.huge;

    return try BufferedWriter.init(allocator, file, buffer_size);
}

// Tests
test "BufferedWriter: basic write" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var file = try tmp_dir.dir.createFile("test.txt", .{ .read = true });
    defer file.close();

    var writer = try BufferedWriter.init(allocator, file, 16);
    defer writer.deinit();

    const test_data = "Hello, World!";
    try writer.writeAll(test_data);
    try writer.flush();

    // Read back and verify
    try file.seekTo(0);
    var buffer: [50]u8 = undefined;
    const bytes_read = try file.read(&buffer);

    try std.testing.expectEqual(test_data.len, bytes_read);
    try std.testing.expectEqualStrings(test_data, buffer[0..bytes_read]);
}

test "BufferedWriter: writeAll" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var file = try tmp_dir.dir.createFile("test.txt", .{ .read = true });
    defer file.close();

    var writer = try BufferedWriter.initDefault(allocator, file);
    defer writer.deinit();

    try writer.writeAll("Line 1\n");
    try writer.writeAll("Line 2\n");
    try writer.flush();

    try file.seekTo(0);
    var buffer: [20]u8 = undefined;
    const bytes_read = try file.read(&buffer);

    try std.testing.expectEqualStrings("Line 1\nLine 2\n", buffer[0..bytes_read]);
}

test "BufferedWriter: writeByte" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var file = try tmp_dir.dir.createFile("test.txt", .{ .read = true });
    defer file.close();

    var writer = try BufferedWriter.initDefault(allocator, file);
    defer writer.deinit();

    try writer.writeByte('A');
    try writer.writeByte('B');
    try writer.writeByte('C');
    try writer.flush();

    try file.seekTo(0);
    var buffer: [3]u8 = undefined;
    const bytes_read = try file.read(&buffer);

    try std.testing.expectEqual(@as(usize, 3), bytes_read);
    try std.testing.expectEqualStrings("ABC", &buffer);
}

test "BufferedWriter: writeIntLittle and writeIntBig" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var file = try tmp_dir.dir.createFile("test.bin", .{ .read = true });
    defer file.close();

    var writer = try BufferedWriter.initDefault(allocator, file);
    defer writer.deinit();

    try writer.writeIntLittle(u32, 0x12345678);
    try writer.writeIntBig(u32, 0x12345678);
    try writer.flush();

    try file.seekTo(0);
    var buffer: [8]u8 = undefined;
    _ = try file.read(&buffer);

    try std.testing.expectEqual(@as(u32, 0x12345678), std.mem.readInt(u32, buffer[0..4], .little));
    try std.testing.expectEqual(@as(u32, 0x12345678), std.mem.readInt(u32, buffer[4..8], .big));
}

test "BufferedWriter: writeZeros" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var file = try tmp_dir.dir.createFile("test.bin", .{ .read = true });
    defer file.close();

    var writer = try BufferedWriter.initDefault(allocator, file);
    defer writer.deinit();

    try writer.writeByte(0xFF);
    try writer.writeZeros(10);
    try writer.writeByte(0xFF);
    try writer.flush();

    try file.seekTo(0);
    var buffer: [12]u8 = undefined;
    const bytes_read = try file.read(&buffer);

    try std.testing.expectEqual(@as(usize, 12), bytes_read);
    try std.testing.expectEqual(@as(u8, 0xFF), buffer[0]);
    try std.testing.expectEqual(@as(u8, 0xFF), buffer[11]);

    for (buffer[1..11]) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }
}

test "BufferedWriter: alignTo" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var file = try tmp_dir.dir.createFile("test.bin", .{ .read = true });
    defer file.close();

    var writer = try BufferedWriter.initDefault(allocator, file);
    defer writer.deinit();

    try writer.writeAll("ABC"); // 3 bytes
    try writer.alignTo(8); // Should add 5 zero bytes
    try writer.writeByte(0xFF);
    try writer.flush();

    const size = try file.getEndPos();
    try std.testing.expectEqual(@as(u64, 9), size); // 3 + 5 + 1

    try file.seekTo(0);
    var buffer: [9]u8 = undefined;
    _ = try file.read(&buffer);

    try std.testing.expectEqualStrings("ABC", buffer[0..3]);
    for (buffer[3..8]) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }
    try std.testing.expectEqual(@as(u8, 0xFF), buffer[8]);
}

test "BufferedWriter: auto flush on buffer full" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var file = try tmp_dir.dir.createFile("test.txt", .{ .read = true });
    defer file.close();

    // Use small buffer to test auto-flush
    var writer = try BufferedWriter.init(allocator, file, 8);
    defer writer.deinit();

    try writer.writeAll("12345678"); // Fills buffer exactly
    try std.testing.expectEqual(@as(usize, 0), writer.buffer_pos); // Should be flushed

    try writer.writeAll("90"); // Should be in buffer
    try std.testing.expectEqual(@as(usize, 2), writer.buffer_pos);
}

test "BufferedWriter: getTotalBytesWritten" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var file = try tmp_dir.dir.createFile("test.txt", .{});
    defer file.close();

    var writer = try BufferedWriter.initDefault(allocator, file);
    defer writer.deinit();

    try std.testing.expectEqual(@as(u64, 0), writer.getTotalBytesWritten());

    try writer.writeAll("Hello");
    try std.testing.expectEqual(@as(u64, 5), writer.getTotalBytesWritten());

    try writer.writeAll(" World");
    try std.testing.expectEqual(@as(u64, 11), writer.getTotalBytesWritten());
}

test "createAdaptiveWriter: buffer size selection" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var file = try tmp_dir.dir.createFile("test.bin", .{});
    defer file.close();

    // Small size
    var small_writer = try createAdaptiveWriter(allocator, file, 50 * 1024);
    defer small_writer.deinit();
    try std.testing.expectEqual(types.BufferSize.small, small_writer.buffer.len);

    // Default size
    var default_writer = try createAdaptiveWriter(allocator, file, 500 * 1024);
    defer default_writer.deinit();
    try std.testing.expectEqual(types.BufferSize.default, default_writer.buffer.len);

    // Large size
    var large_writer = try createAdaptiveWriter(allocator, file, 50 * 1024 * 1024);
    defer large_writer.deinit();
    try std.testing.expectEqual(types.BufferSize.large, large_writer.buffer.len);
}
