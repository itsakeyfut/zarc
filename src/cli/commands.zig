const std = @import("std");
const app = @import("../app/extract.zig");
const formats = @import("../formats/archive.zig");
const tar = @import("../formats/tar/reader.zig");
const args_mod = @import("args.zig");
const output = @import("output.zig");
const progress_mod = @import("progress.zig");

const version = "0.1.0";

/// Run extract command
pub fn runExtract(
    allocator: std.mem.Allocator,
    extract_args: args_mod.ExtractArgs,
) !u8 {
    const stdout_file = std.fs.File.stdout();
    const stderr_file = std.fs.File.stderr();

    var out = output.OutputWriter.init(
        stdout_file,
        extract_args.global.output_level,
        extract_args.global.color_mode,
    );

    var err_out = output.OutputWriter.init(
        stderr_file,
        extract_args.global.output_level,
        extract_args.global.color_mode,
    );

    // Open archive file
    const archive_file = std.fs.cwd().openFile(extract_args.archive_path, .{}) catch |err| {
        try err_out.printError("Cannot open archive file '{s}'", .{extract_args.archive_path});
        try err_out.printError("Reason: {s}", .{@errorName(err)});
        return switch (err) {
            error.FileNotFound => 3,
            error.AccessDenied => 4,
            else => 1,
        };
    };
    defer archive_file.close();

    try out.printInfo("Extracting {s}...", .{extract_args.archive_path});

    const start_time = std.time.nanoTimestamp();

    // Create tar reader
    var tar_reader = try tar.TarReader.init(allocator, archive_file);
    defer tar_reader.deinit();

    var archive_reader = tar_reader.archiveReader();
    defer archive_reader.deinit();

    // Extract archive
    const extract_options = extract_args.toExtractOptions();
    var result = app.extractArchive(
        allocator,
        &archive_reader,
        extract_args.destination,
        extract_options,
    ) catch |err| {
        try err_out.printError("Extraction failed: {s}", .{@errorName(err)});
        return switch (err) {
            error.FileNotFound => 3,
            error.AccessDenied, error.PermissionDenied => 4,
            error.CorruptedArchive, error.CorruptedHeader, error.InvalidFormat => 5,
            error.UnsupportedVersion => 6,
            else => 1,
        };
    };
    defer result.deinit(allocator);

    const end_time = std.time.nanoTimestamp();
    const duration = @as(u64, @intCast(end_time - start_time));

    // Print results
    if (result.succeeded > 0) {
        const size_str = try output.formatSize(allocator, result.total_bytes);
        defer allocator.free(size_str);

        const duration_str = try output.formatDuration(allocator, duration);
        defer allocator.free(duration_str);

        try out.printSuccess(
            "Extracted {d} files ({s}) in {s}",
            .{ result.succeeded, size_str, duration_str },
        );
    }

    // Print warnings
    if (result.warnings.items.len > 0) {
        try err_out.printWarning("{d} warnings occurred:", .{result.warnings.items.len});
        for (result.warnings.items) |warning| {
            try err_out.printWarning("  {s}: {s}", .{ warning.entry_path, warning.message });
        }
    }

    // Print failures
    if (result.failed > 0) {
        try err_out.printError("{d} files failed to extract", .{result.failed});
        return 1;
    }

    return 0;
}

/// Print help message
pub fn printHelp(file: std.fs.File, subcommand: ?[]const u8) !void {
    if (subcommand) |cmd| {
        if (std.mem.eql(u8, cmd, "extract") or std.mem.eql(u8, cmd, "x")) {
            try printExtractHelp(file);
        } else {
            var buf: [256]u8 = undefined;
            const msg = try std.fmt.bufPrint(&buf, "Unknown subcommand: {s}\n\n", .{cmd});
            try file.writeAll(msg);
            try printMainHelp(file);
        }
    } else {
        try printMainHelp(file);
    }
}

/// Print main help message
fn printMainHelp(file: std.fs.File) !void {
    try file.writeAll(
        \\zarc - Zig Archive Tool
        \\
        \\USAGE:
        \\    zarc <subcommand> [options] <arguments>
        \\
        \\SUBCOMMANDS:
        \\    extract, x      Extract archive
        \\    compress, c     Create archive (not yet implemented)
        \\    list, l         List contents (not yet implemented)
        \\    test, t         Test integrity (not yet implemented)
        \\    info, i         Show information (not yet implemented)
        \\    help, h         Show help
        \\    version, v      Show version
        \\
        \\OPTIONS:
        \\    -h, --help      Show help
        \\    -V, --version   Show version
        \\    -v, --verbose   Verbose output
        \\    -q, --quiet     Minimal output
        \\    --no-color      Disable color output
        \\
        \\EXAMPLES:
        \\    zarc extract archive.tar.gz
        \\    zarc x archive.tar.gz -C /tmp/output
        \\    zarc help extract
        \\
        \\For more information about a specific command, use:
        \\    zarc help <command>
        \\
    );
}

/// Print extract command help
fn printExtractHelp(file: std.fs.File) !void {
    try file.writeAll(
        \\zarc extract - Extract archive
        \\
        \\USAGE:
        \\    zarc extract [options] <archive> [destination]
        \\    zarc x [options] <archive> [destination]
        \\
        \\ARGUMENTS:
        \\    <archive>       Archive file to extract
        \\    [destination]   Destination directory (default: current directory)
        \\
        \\OPTIONS:
        \\    -C, --output <dir>          Destination directory
        \\    -f, --overwrite             Overwrite existing files
        \\    -k, --keep-existing         Skip existing files (default)
        \\    -v, --verbose               Verbose output
        \\    -q, --quiet                 Minimal output
        \\    -p, --preserve-permissions  Preserve permissions
        \\    --no-preserve-permissions   Ignore permissions (default)
        \\    --continue-on-error         Continue extraction even if some entries fail
        \\    --no-color                  Disable color output
        \\    -h, --help                  Show this help
        \\
        \\EXAMPLES:
        \\    # Basic extraction
        \\    zarc extract archive.tar.gz
        \\
        \\    # Extract to specific directory
        \\    zarc extract archive.tar.gz /tmp/output
        \\    zarc extract archive.tar.gz --output /tmp/output
        \\    zarc x archive.tar.gz -C /tmp/output
        \\
        \\    # Overwrite existing files
        \\    zarc extract archive.tar.gz --overwrite
        \\    zarc extract archive.tar.gz -f
        \\
        \\    # Verbose output
        \\    zarc extract archive.tar.gz --verbose
        \\    zarc extract archive.tar.gz -v
        \\
        \\    # Continue on errors
        \\    zarc extract archive.tar.gz --continue-on-error
        \\
    );
}

/// Print version information
pub fn printVersion(file: std.fs.File) !void {
    var buf: [256]u8 = undefined;
    const msg = try std.fmt.bufPrint(&buf, "zarc version {s}\n", .{version});
    try file.writeAll(msg);
    try file.writeAll("Zig Archive Tool - A modern archive utility written in Zig\n");
}

// Tests - Skipped for now as they would output to actual stdout
// These tests should be run manually or with proper test harness
