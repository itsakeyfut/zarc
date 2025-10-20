const std = @import("std");
const zarc = @import("zarc");
const TarReader = @import("zarc").formats.tar.reader.TarReader;
const types = @import("zarc").core.types;

test "TarReader: read simple tar archive" {
    const allocator = std.testing.allocator;

    // Open the test fixture
    const file = try std.fs.cwd().openFile("tests/fixtures/simple.tar", .{});
    defer file.close();

    var reader = try TarReader.init(allocator, file);
    defer reader.deinit();

    // Expected entries:
    // 1. test_data/ (directory)
    // 2. test_data/test.txt (file)
    // 3. test_data/hello.txt (file)

    // Entry 1: directory
    {
        const entry = try reader.next();
        try std.testing.expect(entry != null);

        const e = entry.?;
        try std.testing.expectEqualStrings("test_data/", e.path);
        try std.testing.expectEqual(types.EntryType.directory, e.entry_type);
    }

    // Entry 2: test.txt
    {
        const entry = try reader.next();
        try std.testing.expect(entry != null);

        const e = entry.?;
        try std.testing.expect(std.mem.endsWith(u8, e.path, "test.txt"));
        try std.testing.expectEqual(types.EntryType.file, e.entry_type);

        // Read file content
        var buffer: [1024]u8 = undefined;
        const n = try reader.read(&buffer);
        try std.testing.expect(n > 0);

        const content = buffer[0..n];
        try std.testing.expect(std.mem.indexOf(u8, content, "Test file 2") != null);
    }

    // Entry 3: hello.txt
    {
        const entry = try reader.next();
        try std.testing.expect(entry != null);

        const e = entry.?;
        try std.testing.expect(std.mem.endsWith(u8, e.path, "hello.txt"));
        try std.testing.expectEqual(types.EntryType.file, e.entry_type);

        // Read file content
        var buffer: [1024]u8 = undefined;
        const n = try reader.read(&buffer);
        try std.testing.expect(n > 0);

        const content = buffer[0..n];
        try std.testing.expect(std.mem.indexOf(u8, content, "Hello, World!") != null);
    }

    // No more entries
    const end = try reader.next();
    try std.testing.expectEqual(@as(?types.Entry, null), end);
}

test "TarReader: iterate through archive" {
    const allocator = std.testing.allocator;

    const file = try std.fs.cwd().openFile("tests/fixtures/simple.tar", .{});
    defer file.close();

    var reader = try TarReader.init(allocator, file);
    defer reader.deinit();

    var entry_count: usize = 0;

    while (try reader.next()) |entry| {
        entry_count += 1;

        std.debug.print("Entry {d}: {s} ({s}, {d} bytes)\n", .{
            entry_count,
            entry.path,
            @tagName(entry.entry_type),
            entry.size,
        });

        // For files, try to read content
        if (entry.entry_type == .file) {
            var buffer: [4096]u8 = undefined;
            const n = try reader.read(&buffer);
            std.debug.print("  Content: {s}\n", .{buffer[0..n]});
        }
    }

    // Should have 3 entries (1 directory + 2 files)
    try std.testing.expectEqual(@as(usize, 3), entry_count);
}

test "TarReader: skip entry data" {
    const allocator = std.testing.allocator;

    const file = try std.fs.cwd().openFile("tests/fixtures/simple.tar", .{});
    defer file.close();

    var reader = try TarReader.init(allocator, file);
    defer reader.deinit();

    // Read first entry (directory)
    _ = try reader.next();

    // Read second entry (file) but don't read its data
    _ = try reader.next();

    // Skip to next entry (should work even without reading previous data)
    const entry = try reader.next();
    try std.testing.expect(entry != null);

    // Should be able to read this entry's data
    var buffer: [1024]u8 = undefined;
    const n = try reader.read(&buffer);
    try std.testing.expect(n > 0);
}
