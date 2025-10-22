const std = @import("std");
const zarc = @import("zarc");
const TarHeader = zarc.formats.tar.header.TarHeader;
const calculateChecksum = zarc.formats.tar.header.calculateChecksum;
const createHeader = zarc.formats.tar.header.createHeader;
const types = zarc.core.types;
const util = zarc.core.util;

// TAR header unit tests
// Following TESTING_STRATEGY.md guidelines

/// Helper function to create a valid TAR header for testing
fn createValidHeaderData() ![512]u8 {
    var data: [512]u8 = std.mem.zeroes([512]u8);

    // File name
    @memcpy(data[0..9], "test.txt\x00");

    // Mode: 0o644
    @memcpy(data[100..108], "0000644\x00");

    // UID: 1000 (0o1750)
    @memcpy(data[108..116], "0001750\x00");

    // GID: 1000 (0o1750)
    @memcpy(data[116..124], "0001750\x00");

    // Size: 1024 bytes (0o2000)
    @memcpy(data[124..136], "00000002000\x00");

    // Mtime: 1234567890 (0o11145401322)
    @memcpy(data[136..148], "11145401322\x00");

    // Type flag: regular file
    data[156] = '0';

    // USTAR magic and version
    @memcpy(data[257..263], "ustar\x00");
    @memcpy(data[263..265], "00");

    // User name
    @memcpy(data[265..269], "user");

    // Group name
    @memcpy(data[297..302], "group");

    // Calculate and set checksum
    const checksum_val = calculateChecksum(&data);
    _ = try std.fmt.bufPrint(data[148..156], "{o:0>6}\x00 ", .{checksum_val});

    return data;
}

// ============================================================================
// Checksum Tests
// ============================================================================

test "TarHeader: calculateChecksum - zero block gives 256" {
    // Arrange
    var data: [512]u8 = std.mem.zeroes([512]u8);

    // Act
    const checksum = calculateChecksum(&data);

    // Assert - checksum field (8 bytes) treated as spaces (0x20 each)
    try std.testing.expectEqual(@as(u32, 256), checksum);
}

test "TarHeader: calculateChecksum - with data" {
    // Arrange
    var data: [512]u8 = std.mem.zeroes([512]u8);
    data[0] = 'T'; // 84
    data[1] = 'E'; // 69
    data[2] = 'S'; // 83
    data[3] = 'T'; // 84

    // Act
    const checksum = calculateChecksum(&data);

    // Assert
    // Expected: 84 + 69 + 83 + 84 + (8 * 32) = 320 + 256 = 576
    try std.testing.expectEqual(@as(u32, 576), checksum);
}

test "TarHeader: calculateChecksum - ignores checksum field" {
    // Arrange
    var data: [512]u8 = std.mem.zeroes([512]u8);
    // Set checksum field to non-zero values (should be ignored)
    @memset(data[148..156], 0xFF);

    // Act
    const checksum = calculateChecksum(&data);

    // Assert - should still be 256 (8 spaces), not affected by 0xFF bytes
    try std.testing.expectEqual(@as(u32, 256), checksum);
}

// ============================================================================
// Header Parsing Tests - Normal Cases
// ============================================================================

test "TarHeader.parse: valid header - basic file" {
    // Arrange
    const allocator = std.testing.allocator;
    const header_data = try createValidHeaderData();

    // Act
    const header = try TarHeader.parse(&header_data);

    // Assert
    const name = try header.getName(allocator);
    defer allocator.free(name);
    try std.testing.expectEqualStrings("test.txt", name);

    const size = try header.getSize();
    try std.testing.expectEqual(@as(u64, 1024), size);

    const mode = try header.getMode();
    try std.testing.expectEqual(@as(u32, 0o644), mode);

    const mtime = try header.getMtime();
    try std.testing.expectEqual(@as(i64, 1234567890), mtime);

    const uid = try header.getUid();
    try std.testing.expectEqual(@as(u32, 1000), uid);

    const gid = try header.getGid();
    try std.testing.expectEqual(@as(u32, 1000), gid);

    const entry_type = header.getEntryType();
    try std.testing.expectEqual(types.EntryType.file, entry_type);

    try std.testing.expectEqualStrings("user", header.getUname());
    try std.testing.expectEqualStrings("group", header.getGname());
}

test "TarHeader.parse: valid header - directory" {
    // Arrange
    const allocator = std.testing.allocator;
    var header_data: [512]u8 = std.mem.zeroes([512]u8);

    @memcpy(header_data[0..7], "mydir/\x00");
    @memcpy(header_data[100..108], "0000755\x00");
    @memcpy(header_data[124..136], "00000000000\x00"); // size 0 for directory
    @memcpy(header_data[136..148], "11145401322\x00");
    header_data[156] = '5'; // Directory type flag
    @memcpy(header_data[257..263], "ustar\x00");
    @memcpy(header_data[263..265], "00");

    const checksum_val = calculateChecksum(&header_data);
    _ = try std.fmt.bufPrint(header_data[148..156], "{o:0>6}\x00 ", .{checksum_val});

    // Act
    const header = try TarHeader.parse(&header_data);

    // Assert
    const name = try header.getName(allocator);
    defer allocator.free(name);
    try std.testing.expectEqualStrings("mydir/", name);

    const entry_type = header.getEntryType();
    try std.testing.expectEqual(types.EntryType.directory, entry_type);

    const size = try header.getSize();
    try std.testing.expectEqual(@as(u64, 0), size);
}

test "TarHeader.parse: valid header - symlink" {
    // Arrange
    const allocator = std.testing.allocator;
    var header_data: [512]u8 = std.mem.zeroes([512]u8);

    @memcpy(header_data[0..9], "link.txt\x00");
    @memcpy(header_data[100..108], "0000777\x00");
    @memcpy(header_data[124..136], "00000000000\x00"); // symlinks have size 0 in header
    @memcpy(header_data[136..148], "11145401322\x00");
    header_data[156] = '2'; // Symlink type flag
    @memcpy(header_data[157..168], "target.txt\x00"); // linkname
    @memcpy(header_data[257..263], "ustar\x00");
    @memcpy(header_data[263..265], "00");

    const checksum_val = calculateChecksum(&header_data);
    _ = try std.fmt.bufPrint(header_data[148..156], "{o:0>6}\x00 ", .{checksum_val});

    // Act
    const header = try TarHeader.parse(&header_data);

    // Assert
    const name = try header.getName(allocator);
    defer allocator.free(name);
    try std.testing.expectEqualStrings("link.txt", name);

    const entry_type = header.getEntryType();
    try std.testing.expectEqual(types.EntryType.symlink, entry_type);

    const linkname = header.getLinkname();
    try std.testing.expectEqualStrings("target.txt", linkname);
}

test "TarHeader.parse: valid header - GNU tar format" {
    // Arrange
    const allocator = std.testing.allocator;
    var header_data: [512]u8 = std.mem.zeroes([512]u8);

    @memcpy(header_data[0..9], "test.txt\x00");
    @memcpy(header_data[100..108], "0000644\x00");
    @memcpy(header_data[124..136], "00000000100\x00");
    @memcpy(header_data[136..148], "11145401322\x00");
    header_data[156] = '0';

    // GNU tar uses "ustar " with spaces instead of null bytes
    @memcpy(header_data[257..263], "ustar ");
    @memcpy(header_data[263..265], "  ");

    const checksum_val = calculateChecksum(&header_data);
    _ = try std.fmt.bufPrint(header_data[148..156], "{o:0>6}\x00 ", .{checksum_val});

    // Act
    const header = try TarHeader.parse(&header_data);

    // Assert
    const name = try header.getName(allocator);
    defer allocator.free(name);
    try std.testing.expectEqualStrings("test.txt", name);
}

// ============================================================================
// Header Parsing Tests - Edge Cases
// ============================================================================

test "TarHeader.parse: boundary values - maximum file size" {
    // Arrange
    const allocator = std.testing.allocator;
    var header_data: [512]u8 = std.mem.zeroes([512]u8);

    @memcpy(header_data[0..9], "large.bin");
    @memcpy(header_data[100..108], "0000644\x00");
    // Maximum size in octal: 77777777777 = 8GB (tar format limit)
    @memcpy(header_data[124..136], "77777777777\x00");
    @memcpy(header_data[136..148], "11145401322\x00");
    header_data[156] = '0';
    @memcpy(header_data[257..263], "ustar\x00");
    @memcpy(header_data[263..265], "00");

    const checksum_val = calculateChecksum(&header_data);
    _ = try std.fmt.bufPrint(header_data[148..156], "{o:0>6}\x00 ", .{checksum_val});

    // Act
    const header = try TarHeader.parse(&header_data);

    // Assert
    const size = try header.getSize();
    try std.testing.expectEqual(@as(u64, 0o77777777777), size);

    const name = try header.getName(allocator);
    defer allocator.free(name);
}

test "TarHeader.parse: edge case - zero size file" {
    // Arrange
    const allocator = std.testing.allocator;
    var header_data: [512]u8 = std.mem.zeroes([512]u8);

    @memcpy(header_data[0..10], "empty.txt\x00");
    @memcpy(header_data[100..108], "0000644\x00");
    @memcpy(header_data[124..136], "00000000000\x00"); // size = 0
    @memcpy(header_data[136..148], "11145401322\x00");
    header_data[156] = '0';
    @memcpy(header_data[257..263], "ustar\x00");
    @memcpy(header_data[263..265], "00");

    const checksum_val = calculateChecksum(&header_data);
    _ = try std.fmt.bufPrint(header_data[148..156], "{o:0>6}\x00 ", .{checksum_val});

    // Act
    const header = try TarHeader.parse(&header_data);

    // Assert
    const size = try header.getSize();
    try std.testing.expectEqual(@as(u64, 0), size);

    const name = try header.getName(allocator);
    defer allocator.free(name);
}

test "TarHeader.parse: edge case - alternative regular file type flag" {
    // Arrange
    const allocator = std.testing.allocator;
    var header_data = try createValidHeaderData();

    // Use null byte instead of '0' for regular file
    header_data[156] = '\x00';

    const checksum_val = calculateChecksum(&header_data);
    _ = try std.fmt.bufPrint(header_data[148..156], "{o:0>6}\x00 ", .{checksum_val});

    // Act
    const header = try TarHeader.parse(&header_data);

    // Assert
    const entry_type = header.getEntryType();
    try std.testing.expectEqual(types.EntryType.file, entry_type);

    const name = try header.getName(allocator);
    defer allocator.free(name);
}

// ============================================================================
// Header Parsing Tests - Error Cases
// ============================================================================

test "TarHeader.parse: error - invalid magic" {
    // Arrange
    var header_data: [512]u8 = std.mem.zeroes([512]u8);

    // Set invalid magic (not "ustar")
    @memcpy(header_data[257..263], "NOTTAR");
    @memcpy(header_data[263..265], "00");

    // Even with correct checksum, should fail on magic
    const checksum_val = calculateChecksum(&header_data);
    _ = try std.fmt.bufPrint(header_data[148..156], "{o:0>6}\x00 ", .{checksum_val});

    // Act & Assert
    try std.testing.expectError(error.CorruptedHeader, TarHeader.parse(&header_data));
}

test "TarHeader.parse: error - invalid checksum" {
    // Arrange
    var header_data: [512]u8 = std.mem.zeroes([512]u8);

    @memcpy(header_data[0..9], "test.txt\x00");
    @memcpy(header_data[257..263], "ustar\x00");
    @memcpy(header_data[263..265], "00");

    // Set wrong checksum
    @memcpy(header_data[148..156], "9999999\x00");

    // Act & Assert
    try std.testing.expectError(error.CorruptedHeader, TarHeader.parse(&header_data));
}

test "TarHeader.parse: error - unparseable checksum" {
    // Arrange
    var header_data: [512]u8 = std.mem.zeroes([512]u8);

    @memcpy(header_data[257..263], "ustar\x00");
    @memcpy(header_data[263..265], "00");

    // Set invalid octal checksum
    @memcpy(header_data[148..156], "INVALID\x00");

    // Act & Assert
    try std.testing.expectError(error.CorruptedHeader, TarHeader.parse(&header_data));
}

// ============================================================================
// Header Field Extraction Tests
// ============================================================================

test "TarHeader.getName: basic name" {
    // Arrange
    const allocator = std.testing.allocator;
    const header_data = try createValidHeaderData();
    const header = try TarHeader.parse(&header_data);

    // Act
    const name = try header.getName(allocator);
    defer allocator.free(name);

    // Assert
    try std.testing.expectEqualStrings("test.txt", name);
}

test "TarHeader.getName: with prefix" {
    // Arrange
    const allocator = std.testing.allocator;
    var header_data: [512]u8 = std.mem.zeroes([512]u8);

    @memcpy(header_data[0..8], "file.txt"); // name
    @memcpy(header_data[345..360], "very/long/path\x00"); // prefix (starts at offset 345)
    @memcpy(header_data[257..263], "ustar\x00");
    @memcpy(header_data[263..265], "00");

    const checksum_val = calculateChecksum(&header_data);
    _ = try std.fmt.bufPrint(header_data[148..156], "{o:0>6}\x00 ", .{checksum_val});

    const header = try TarHeader.parse(&header_data);

    // Act
    const name = try header.getName(allocator);
    defer allocator.free(name);

    // Assert
    try std.testing.expectEqualStrings("very/long/path/file.txt", name);
}

test "TarHeader.getName: empty prefix" {
    // Arrange
    const allocator = std.testing.allocator;
    var header_data: [512]u8 = std.mem.zeroes([512]u8);

    @memcpy(header_data[0..5], "file\x00");
    // prefix is all zeros (empty)
    @memcpy(header_data[257..263], "ustar\x00");
    @memcpy(header_data[263..265], "00");

    const checksum_val = calculateChecksum(&header_data);
    _ = try std.fmt.bufPrint(header_data[148..156], "{o:0>6}\x00 ", .{checksum_val});

    const header = try TarHeader.parse(&header_data);

    // Act
    const name = try header.getName(allocator);
    defer allocator.free(name);

    // Assert
    try std.testing.expectEqualStrings("file", name);
}

test "TarHeader.getEntryType: all types" {
    // Test each entry type
    const test_cases = [_]struct {
        flag: u8,
        expected: types.EntryType,
    }{
        .{ .flag = '0', .expected = .file },
        .{ .flag = '\x00', .expected = .file },
        .{ .flag = '1', .expected = .hardlink },
        .{ .flag = '2', .expected = .symlink },
        .{ .flag = '3', .expected = .char_device },
        .{ .flag = '4', .expected = .block_device },
        .{ .flag = '5', .expected = .directory },
        .{ .flag = '6', .expected = .fifo },
        .{ .flag = '7', .expected = .file }, // Reserved, defaults to file
    };

    for (test_cases) |tc| {
        // Arrange
        var header_data: [512]u8 = std.mem.zeroes([512]u8);
        header_data[156] = tc.flag;
        @memcpy(header_data[257..263], "ustar\x00");
        @memcpy(header_data[263..265], "00");

        const checksum_val = calculateChecksum(&header_data);
        _ = try std.fmt.bufPrint(header_data[148..156], "{o:0>6}\x00 ", .{checksum_val});

        const header = try TarHeader.parse(&header_data);

        // Act
        const entry_type = header.getEntryType();

        // Assert
        try std.testing.expectEqual(tc.expected, entry_type);
    }
}

// ============================================================================
// Header Creation Tests
// ============================================================================

test "createHeader: simple file" {
    // Arrange
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

    // Act
    const header = try createHeader(&entry, allocator);

    // Assert
    const name = try header.getName(allocator);
    defer allocator.free(name);
    try std.testing.expectEqualStrings("test.txt", name);

    const size = try header.getSize();
    try std.testing.expectEqual(@as(u64, 1024), size);

    const mode = try header.getMode();
    try std.testing.expectEqual(@as(u32, 0o644), mode);

    try std.testing.expectEqual(TarHeader.TypeFlag.REGULAR, header.typeflag);

    // Verify USTAR magic
    try std.testing.expect(std.mem.eql(u8, header.magic[0..6], "ustar\x00"));
    try std.testing.expect(std.mem.eql(u8, header.version[0..2], "00"));
}

test "createHeader: directory" {
    // Arrange
    const allocator = std.testing.allocator;
    const entry = types.Entry{
        .path = "mydir/",
        .entry_type = .directory,
        .size = 0,
        .mode = 0o755,
        .mtime = 1234567890,
        .uid = 0,
        .gid = 0,
        .uname = "",
        .gname = "",
        .link_target = "",
    };

    // Act
    const header = try createHeader(&entry, allocator);

    // Assert
    try std.testing.expectEqual(TarHeader.TypeFlag.DIRECTORY, header.typeflag);

    const name = try header.getName(allocator);
    defer allocator.free(name);
    try std.testing.expectEqualStrings("mydir/", name);
}

test "createHeader: symlink" {
    // Arrange
    const allocator = std.testing.allocator;
    const entry = types.Entry{
        .path = "link.txt",
        .entry_type = .symlink,
        .size = 0,
        .mode = 0o777,
        .mtime = 1234567890,
        .uid = 0,
        .gid = 0,
        .uname = "",
        .gname = "",
        .link_target = "/path/to/target",
    };

    // Act
    const header = try createHeader(&entry, allocator);

    // Assert
    try std.testing.expectEqual(TarHeader.TypeFlag.SYMLINK, header.typeflag);

    const linkname = header.getLinkname();
    try std.testing.expectEqualStrings("/path/to/target", linkname);
}

test "createHeader: error - filename too long (>255 without separator)" {
    // Arrange
    const allocator = std.testing.allocator;

    // Create a path >255 characters without a separator in the right place
    const long_name = "x" ** 256;
    const entry = types.Entry{
        .path = long_name,
        .entry_type = .file,
        .size = 0,
        .mode = 0o644,
        .mtime = 1234567890,
        .uid = 0,
        .gid = 0,
        .uname = "",
        .gname = "",
        .link_target = "",
    };

    // Act & Assert
    try std.testing.expectError(error.FilenameTooLong, createHeader(&entry, allocator));
}

test "createHeader: error - link target too long" {
    // Arrange
    const allocator = std.testing.allocator;
    const long_link = "x" ** 101; // >100 characters

    const entry = types.Entry{
        .path = "link.txt",
        .entry_type = .symlink,
        .size = 0,
        .mode = 0o777,
        .mtime = 1234567890,
        .uid = 0,
        .gid = 0,
        .uname = "",
        .gname = "",
        .link_target = long_link,
    };

    // Act & Assert
    try std.testing.expectError(error.FilenameTooLong, createHeader(&entry, allocator));
}

// ============================================================================
// Round-trip Tests
// ============================================================================

test "TarHeader: round-trip - entry to header to entry" {
    // Arrange
    const allocator = std.testing.allocator;

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

    // Act
    const header = try createHeader(&original_entry, allocator);
    const converted_entry = try header.toEntry(allocator);

    // Cleanup
    defer allocator.free(converted_entry.path);
    defer allocator.free(converted_entry.uname);
    defer allocator.free(converted_entry.gname);
    defer allocator.free(converted_entry.link_target);

    // Assert
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

test "TarHeader: round-trip - with long path using prefix" {
    // Arrange
    const allocator = std.testing.allocator;

    const long_path = "very/long/path/prefix/that/exceeds/one/hundred/characters/and/needs/to/be/split/into/prefix/and/name/parts/file.txt";

    const original_entry = types.Entry{
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

    // Act
    const header = try createHeader(&original_entry, allocator);
    const converted_entry = try header.toEntry(allocator);

    // Cleanup
    defer allocator.free(converted_entry.path);
    defer allocator.free(converted_entry.uname);
    defer allocator.free(converted_entry.gname);
    defer allocator.free(converted_entry.link_target);

    // Assert
    try std.testing.expectEqualStrings(original_entry.path, converted_entry.path);
}

// ============================================================================
// Memory Leak Tests
// ============================================================================

test "TarHeader: no memory leak - getName" {
    // Arrange
    const allocator = std.testing.allocator;

    const header_data = try createValidHeaderData();
    const header = try TarHeader.parse(&header_data);

    // Act
    const name = try header.getName(allocator);
    defer allocator.free(name);

    // Assert (std.testing.allocator checks for leaks)
}

test "TarHeader: no memory leak - toEntry" {
    // Arrange
    const allocator = std.testing.allocator;

    const header_data = try createValidHeaderData();
    const header = try TarHeader.parse(&header_data);

    // Act
    const entry = try header.toEntry(allocator);
    defer allocator.free(entry.path);
    defer allocator.free(entry.uname);
    defer allocator.free(entry.gname);
    defer allocator.free(entry.link_target);

    // Assert (std.testing.allocator checks for leaks)
}

test "TarHeader: no memory leak - createHeader and toEntry" {
    // Arrange
    const allocator = std.testing.allocator;

    const original_entry = types.Entry{
        .path = "test.txt",
        .entry_type = .file,
        .size = 1024,
        .mode = 0o644,
        .mtime = 1234567890,
        .uid = 0,
        .gid = 0,
        .uname = "user",
        .gname = "group",
        .link_target = "",
    };

    // Act
    const header = try createHeader(&original_entry, allocator);
    const converted_entry = try header.toEntry(allocator);
    defer allocator.free(converted_entry.path);
    defer allocator.free(converted_entry.uname);
    defer allocator.free(converted_entry.gname);
    defer allocator.free(converted_entry.link_target);

    // Assert (std.testing.allocator checks for leaks)
}
