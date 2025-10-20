const std = @import("std");
const types = @import("../core/types.zig");
const errors = @import("../core/errors.zig");

/// Common interface for all archive format readers
///
/// This trait provides a unified interface for reading different archive formats
/// (tar, zip, 7z, etc.). Each format implementation provides its own concrete
/// implementation that can be wrapped with this interface.
///
/// Design Pattern: VTable-based polymorphism
///
/// Example usage:
/// ```zig
/// const file = try std.fs.cwd().openFile("archive.tar", .{});
/// defer file.close();
///
/// var tar_reader = try TarReader.init(allocator, file);
/// defer tar_reader.deinit();
///
/// var archive = tar_reader.archiveReader();
///
/// while (try archive.next()) |entry| {
///     std.debug.print("Entry: {s}\n", .{entry.path});
///
///     var buffer: [4096]u8 = undefined;
///     while (true) {
///         const n = try archive.read(&buffer);
///         if (n == 0) break;
///         // Process data...
///     }
/// }
/// ```
pub const ArchiveReader = struct {
    /// Pointer to the concrete implementation (e.g., TarReader)
    ptr: *anyopaque,

    /// VTable containing function pointers for the interface
    vtable: *const VTable,

    /// Virtual function table for ArchiveReader
    pub const VTable = struct {
        /// Get next entry in archive
        ///
        /// Parameters:
        ///   - ptr: Pointer to concrete implementation
        ///
        /// Returns:
        ///   - Next entry metadata, or null if end of archive reached
        ///
        /// Errors:
        ///   - error.CorruptedHeader: Invalid header format
        ///   - error.IncompleteArchive: Unexpected end of file
        ///   - error.ReadError: Failed to read from file
        next: *const fn (ptr: *anyopaque) anyerror!?types.Entry,

        /// Read data from current entry
        ///
        /// Parameters:
        ///   - ptr: Pointer to concrete implementation
        ///   - buffer: Buffer to read data into
        ///
        /// Returns:
        ///   - Number of bytes read (0 when entry is fully read)
        ///
        /// Errors:
        ///   - error.ReadError: Failed to read from file
        ///   - error.NoCurrentEntry: No entry is currently being read
        read: *const fn (ptr: *anyopaque, buffer: []u8) anyerror!usize,

        /// Clean up resources (does not close the underlying file)
        ///
        /// Parameters:
        ///   - ptr: Pointer to concrete implementation
        ///
        /// Note: The caller is responsible for closing the underlying file
        deinit: *const fn (ptr: *anyopaque) void,
    };

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
    /// while (try archive.next()) |entry| {
    ///     std.debug.print("Entry: {s}\n", .{entry.path});
    /// }
    /// ```
    pub fn next(self: *ArchiveReader) !?types.Entry {
        return self.vtable.next(self.ptr);
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
    ///     const n = try archive.read(&buffer);
    ///     if (n == 0) break;
    ///     // Process buffer[0..n]
    /// }
    /// ```
    pub fn read(self: *ArchiveReader, buffer: []u8) !usize {
        return self.vtable.read(self.ptr, buffer);
    }

    /// Clean up resources
    ///
    /// Note: Does not close the underlying file (caller is responsible)
    ///
    /// Example:
    /// ```zig
    /// var archive = tar_reader.archiveReader();
    /// defer archive.deinit();
    /// ```
    pub fn deinit(self: *ArchiveReader) void {
        self.vtable.deinit(self.ptr);
    }
};

/// Common interface for all archive format writers
///
/// This trait provides a unified interface for creating different archive formats
/// (tar, zip, 7z, etc.). Each format implementation provides its own concrete
/// implementation that can be wrapped with this interface.
///
/// Design Pattern: VTable-based polymorphism
///
/// Example usage:
/// ```zig
/// const file = try std.fs.cwd().createFile("archive.tar", .{});
/// defer file.close();
///
/// var tar_writer = try TarWriter.init(allocator, file);
/// defer tar_writer.deinit();
///
/// var archive = tar_writer.archiveWriter();
///
/// const entry = types.Entry{
///     .path = "file.txt",
///     .entry_type = .file,
///     .size = data.len,
///     .mode = 0o644,
///     .mtime = std.time.timestamp(),
/// };
///
/// try archive.addEntry(entry);
/// try archive.write(data);
/// try archive.finalize();
/// ```
pub const ArchiveWriter = struct {
    /// Pointer to the concrete implementation (e.g., TarWriter)
    ptr: *anyopaque,

    /// VTable containing function pointers for the interface
    vtable: *const VTable,

    /// Virtual function table for ArchiveWriter
    pub const VTable = struct {
        /// Add a new entry to the archive
        ///
        /// Parameters:
        ///   - ptr: Pointer to concrete implementation
        ///   - entry: Entry metadata to add
        ///
        /// Errors:
        ///   - error.WriteError: Failed to write to file
        ///   - error.InvalidArgument: Invalid entry metadata
        addEntry: *const fn (ptr: *anyopaque, entry: types.Entry) anyerror!void,

        /// Write data for the current entry
        ///
        /// Parameters:
        ///   - ptr: Pointer to concrete implementation
        ///   - data: Data to write
        ///
        /// Returns:
        ///   - Number of bytes written
        ///
        /// Errors:
        ///   - error.WriteError: Failed to write to file
        ///   - error.NoCurrentEntry: No entry is currently being written
        write: *const fn (ptr: *anyopaque, data: []const u8) anyerror!usize,

        /// Finalize the archive (write end markers, etc.)
        ///
        /// Parameters:
        ///   - ptr: Pointer to concrete implementation
        ///
        /// Errors:
        ///   - error.WriteError: Failed to write to file
        finalize: *const fn (ptr: *anyopaque) anyerror!void,

        /// Clean up resources (does not close the underlying file)
        ///
        /// Parameters:
        ///   - ptr: Pointer to concrete implementation
        ///
        /// Note: The caller is responsible for closing the underlying file
        deinit: *const fn (ptr: *anyopaque) void,
    };

    /// Add a new entry to the archive
    ///
    /// Parameters:
    ///   - entry: Entry metadata to add
    ///
    /// Errors:
    ///   - error.WriteError: Failed to write to file
    ///   - error.InvalidArgument: Invalid entry metadata
    ///
    /// Example:
    /// ```zig
    /// const entry = types.Entry{
    ///     .path = "file.txt",
    ///     .entry_type = .file,
    ///     .size = 1024,
    ///     .mode = 0o644,
    ///     .mtime = std.time.timestamp(),
    /// };
    /// try archive.addEntry(entry);
    /// ```
    pub fn addEntry(self: *ArchiveWriter, entry: types.Entry) !void {
        return self.vtable.addEntry(self.ptr, entry);
    }

    /// Write data for the current entry
    ///
    /// Parameters:
    ///   - data: Data to write
    ///
    /// Returns:
    ///   - Number of bytes written
    ///
    /// Errors:
    ///   - error.WriteError: Failed to write to file
    ///   - error.NoCurrentEntry: No entry is currently being written
    ///
    /// Example:
    /// ```zig
    /// const data = "Hello, World!";
    /// const n = try archive.write(data);
    /// ```
    pub fn write(self: *ArchiveWriter, data: []const u8) !usize {
        return self.vtable.write(self.ptr, data);
    }

    /// Finalize the archive (write end markers, etc.)
    ///
    /// Must be called before closing the archive to ensure all data is written
    /// properly. For example, TAR format requires two zero blocks at the end.
    ///
    /// Errors:
    ///   - error.WriteError: Failed to write to file
    ///
    /// Example:
    /// ```zig
    /// try archive.finalize();
    /// ```
    pub fn finalize(self: *ArchiveWriter) !void {
        return self.vtable.finalize(self.ptr);
    }

    /// Clean up resources
    ///
    /// Note: Does not close the underlying file (caller is responsible)
    ///
    /// Example:
    /// ```zig
    /// var archive = tar_writer.archiveWriter();
    /// defer archive.deinit();
    /// ```
    pub fn deinit(self: *ArchiveWriter) void {
        self.vtable.deinit(self.ptr);
    }
};

/// Helper function to read all entries from an archive
///
/// Convenience function that reads all entries into a slice.
/// Useful for listing archive contents.
///
/// Parameters:
///   - allocator: Memory allocator
///   - archive: Archive reader
///
/// Returns:
///   - Slice of all entries (caller must free)
///
/// Errors:
///   - error.OutOfMemory: Failed to allocate memory
///   - (All ArchiveReader errors)
///
/// Example:
/// ```zig
/// const entries = try readAllEntries(allocator, &archive);
/// defer allocator.free(entries);
///
/// for (entries) |entry| {
///     std.debug.print("{}\n", .{entry});
/// }
/// ```
pub fn readAllEntries(
    allocator: std.mem.Allocator,
    archive: *ArchiveReader,
) ![]types.Entry {
    var entries = std.array_list.AlignedManaged(types.Entry, null).init(allocator);
    errdefer entries.deinit();

    while (try archive.next()) |entry| {
        try entries.append(entry);
    }

    return entries.toOwnedSlice();
}

/// Helper function to extract all entries from an archive to a directory
///
/// Convenience function that extracts all files to the specified destination.
///
/// Parameters:
///   - allocator: Memory allocator
///   - archive: Archive reader
///   - dest_dir: Destination directory (must exist)
///
/// Errors:
///   - error.OutOfMemory: Failed to allocate memory
///   - error.FileNotFound: Destination directory does not exist
///   - error.PermissionDenied: Insufficient permissions
///   - (All ArchiveReader errors)
///
/// Example:
/// ```zig
/// try extractAllEntries(allocator, &archive, dest_dir);
/// ```
pub fn extractAllEntries(
    allocator: std.mem.Allocator,
    archive: *ArchiveReader,
    dest_dir: std.fs.Dir,
) !void {
    while (try archive.next()) |entry| {
        switch (entry.entry_type) {
            .directory => {
                // Create directory
                try dest_dir.makePath(entry.path);
            },
            .file => {
                // Create file and write data
                const file = try dest_dir.createFile(entry.path, .{});
                defer file.close();

                var buffer: [types.BufferSize.default]u8 = undefined;
                while (true) {
                    const n = try archive.read(&buffer);
                    if (n == 0) break;
                    try file.writeAll(buffer[0..n]);
                }
            },
            .symlink => {
                // Create symlink
                try dest_dir.symLink(entry.link_target, entry.path, .{});
            },
            else => {
                // Skip other types for now (hardlink, devices, etc.)
                std.debug.print("Skipping unsupported entry type: {s}\n", .{entry.path});
            },
        }
    }

    _ = allocator; // Mark as used (for future enhancements)
}

// Tests
test "ArchiveReader: interface definition" {
    // This test verifies that the ArchiveReader interface is properly defined
    // Actual functionality tests are in format-specific implementations
    const TestReader = struct {
        fn nextImpl(_: *anyopaque) anyerror!?types.Entry {
            return null;
        }

        fn readImpl(_: *anyopaque, _: []u8) anyerror!usize {
            return 0;
        }

        fn deinitImpl(_: *anyopaque) void {}

        fn archiveReader(self: *@This()) ArchiveReader {
            return .{
                .ptr = self,
                .vtable = &.{
                    .next = nextImpl,
                    .read = readImpl,
                    .deinit = deinitImpl,
                },
            };
        }
    };

    var test_reader = TestReader{};
    var archive = test_reader.archiveReader();

    const entry = try archive.next();
    try std.testing.expectEqual(@as(?types.Entry, null), entry);

    var buffer: [10]u8 = undefined;
    const n = try archive.read(&buffer);
    try std.testing.expectEqual(@as(usize, 0), n);

    archive.deinit();
}

test "ArchiveWriter: interface definition" {
    // This test verifies that the ArchiveWriter interface is properly defined
    // Actual functionality tests are in format-specific implementations
    const TestWriter = struct {
        fn addEntryImpl(_: *anyopaque, _: types.Entry) anyerror!void {}

        fn writeImpl(_: *anyopaque, data: []const u8) anyerror!usize {
            return data.len;
        }

        fn finalizeImpl(_: *anyopaque) anyerror!void {}

        fn deinitImpl(_: *anyopaque) void {}

        fn archiveWriter(self: *@This()) ArchiveWriter {
            return .{
                .ptr = self,
                .vtable = &.{
                    .addEntry = addEntryImpl,
                    .write = writeImpl,
                    .finalize = finalizeImpl,
                    .deinit = deinitImpl,
                },
            };
        }
    };

    var test_writer = TestWriter{};
    var archive = test_writer.archiveWriter();

    const entry = types.Entry{
        .path = "test.txt",
        .entry_type = .file,
        .size = 10,
        .mode = 0o644,
        .mtime = 1234567890,
    };

    try archive.addEntry(entry);

    const data = "test data!";
    const n = try archive.write(data);
    try std.testing.expectEqual(@as(usize, 10), n);

    try archive.finalize();
    archive.deinit();
}

test "readAllEntries: empty archive" {
    const allocator = std.testing.allocator;

    const TestReader = struct {
        fn nextImpl(_: *anyopaque) anyerror!?types.Entry {
            return null;
        }

        fn readImpl(_: *anyopaque, _: []u8) anyerror!usize {
            return 0;
        }

        fn deinitImpl(_: *anyopaque) void {}

        fn archiveReader(self: *@This()) ArchiveReader {
            return .{
                .ptr = self,
                .vtable = &.{
                    .next = nextImpl,
                    .read = readImpl,
                    .deinit = deinitImpl,
                },
            };
        }
    };

    var test_reader = TestReader{};
    var archive = test_reader.archiveReader();

    const entries = try readAllEntries(allocator, &archive);
    defer allocator.free(entries);

    try std.testing.expectEqual(@as(usize, 0), entries.len);
}
