const std = @import("std");
const app = @import("../app/extract.zig");
const security = @import("../app/security.zig");
const output = @import("output.zig");

/// Subcommand type
pub const Subcommand = enum {
    extract,
    compress,
    list,
    test_archive,
    info,
    help,
    version,

    /// Parse subcommand from string
    pub fn fromString(str: []const u8) ?Subcommand {
        if (std.mem.eql(u8, str, "extract") or std.mem.eql(u8, str, "x")) {
            return .extract;
        } else if (std.mem.eql(u8, str, "compress") or
            std.mem.eql(u8, str, "c") or
            std.mem.eql(u8, str, "create"))
        {
            return .compress;
        } else if (std.mem.eql(u8, str, "list") or
            std.mem.eql(u8, str, "l") or
            std.mem.eql(u8, str, "ls"))
        {
            return .list;
        } else if (std.mem.eql(u8, str, "test") or std.mem.eql(u8, str, "t")) {
            return .test_archive;
        } else if (std.mem.eql(u8, str, "info") or std.mem.eql(u8, str, "i")) {
            return .info;
        } else if (std.mem.eql(u8, str, "help") or
            std.mem.eql(u8, str, "h") or
            std.mem.eql(u8, str, "--help") or
            std.mem.eql(u8, str, "-h"))
        {
            return .help;
        } else if (std.mem.eql(u8, str, "version") or
            std.mem.eql(u8, str, "v") or
            std.mem.eql(u8, str, "--version") or
            std.mem.eql(u8, str, "-V"))
        {
            return .version;
        }
        return null;
    }
};

/// Global options applicable to all commands
pub const GlobalOptions = struct {
    verbose: bool = false,
    quiet: bool = false,
    color_mode: output.ColorMode = .auto,
    output_level: output.OutputLevel = .normal,

    /// Update output level based on verbosity flags
    pub fn updateOutputLevel(self: *GlobalOptions) void {
        if (self.quiet) {
            self.output_level = .quiet;
        } else if (self.verbose) {
            self.output_level = .verbose;
        } else {
            self.output_level = .normal;
        }
    }
};

/// Extract command arguments
pub const ExtractArgs = struct {
    archive_path: []const u8,
    destination: []const u8 = ".",
    options: app.ExtractOptions = .{},
    global: GlobalOptions = .{},

    /// Convert to ExtractOptions
    pub fn toExtractOptions(self: ExtractArgs) app.ExtractOptions {
        var opts = self.options;
        opts.verbose = self.global.verbose;
        return opts;
    }
};

/// Compress command arguments (placeholder for future implementation)
pub const CompressArgs = struct {
    archive_path: []const u8,
    sources: []const []const u8,
    global: GlobalOptions = .{},
};

/// List command arguments (placeholder for future implementation)
pub const ListArgs = struct {
    archive_path: []const u8,
    global: GlobalOptions = .{},
};

/// Parsed command-line arguments
pub const ParsedArgs = union(enum) {
    extract: ExtractArgs,
    compress: CompressArgs,
    list: ListArgs,
    help: ?[]const u8, // Optional subcommand to show help for
    version: void,
    invalid: []const u8, // Error message

    pub fn deinit(self: ParsedArgs, allocator: std.mem.Allocator) void {
        switch (self) {
            .invalid => |msg| allocator.free(msg),
            else => {},
        }
    }
};

/// Parse command-line arguments
pub fn parseArgs(allocator: std.mem.Allocator, args: []const []const u8) !ParsedArgs {
    if (args.len == 0) {
        return .{ .help = null };
    }

    // First argument is the subcommand
    const subcommand_str = args[0];
    const subcommand = Subcommand.fromString(subcommand_str) orelse {
        const msg = try std.fmt.allocPrint(
            allocator,
            "Unknown subcommand: '{s}'",
            .{subcommand_str},
        );
        return .{ .invalid = msg };
    };

    return switch (subcommand) {
        .extract => try parseExtractArgs(allocator, args[1..]),
        .help => .{ .help = if (args.len > 1) args[1] else null },
        .version => .version,
        else => {
            const msg = try std.fmt.allocPrint(
                allocator,
                "Subcommand '{s}' is not yet implemented",
                .{subcommand_str},
            );
            return .{ .invalid = msg };
        },
    };
}

/// Parse extract command arguments
fn parseExtractArgs(allocator: std.mem.Allocator, args: []const []const u8) !ParsedArgs {
    var extract_args = ExtractArgs{
        .archive_path = undefined,
    };

    var positional_index: usize = 0;
    var i: usize = 0;

    while (i < args.len) : (i += 1) {
        const arg = args[i];

        // Check for options
        if (std.mem.startsWith(u8, arg, "-")) {
            if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
                extract_args.global.verbose = true;
            } else if (std.mem.eql(u8, arg, "-q") or std.mem.eql(u8, arg, "--quiet")) {
                extract_args.global.quiet = true;
            } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--overwrite")) {
                extract_args.options.overwrite = true;
            } else if (std.mem.eql(u8, arg, "-k") or std.mem.eql(u8, arg, "--keep-existing")) {
                extract_args.options.overwrite = false;
            } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--preserve-permissions")) {
                extract_args.options.preserve_permissions = true;
            } else if (std.mem.eql(u8, arg, "--no-preserve-permissions")) {
                extract_args.options.preserve_permissions = false;
            } else if (std.mem.eql(u8, arg, "--continue-on-error")) {
                extract_args.options.continue_on_error = true;
            } else if (std.mem.eql(u8, arg, "--no-color")) {
                extract_args.global.color_mode = .never;
            } else if (std.mem.eql(u8, arg, "-C") or std.mem.eql(u8, arg, "--output")) {
                // Next argument is the destination
                i += 1;
                if (i >= args.len) {
                    const msg = try std.fmt.allocPrint(
                        allocator,
                        "Option '{s}' requires an argument",
                        .{arg},
                    );
                    return .{ .invalid = msg };
                }
                extract_args.destination = args[i];
            } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                return .{ .help = "extract" };
            } else {
                const msg = try std.fmt.allocPrint(
                    allocator,
                    "Unknown option: '{s}'",
                    .{arg},
                );
                return .{ .invalid = msg };
            }
        } else {
            // Positional argument
            if (positional_index == 0) {
                extract_args.archive_path = arg;
                positional_index += 1;
            } else if (positional_index == 1) {
                extract_args.destination = arg;
                positional_index += 1;
            } else {
                const msg = try std.fmt.allocPrint(
                    allocator,
                    "Too many arguments. Expected archive path and optional destination, got extra: '{s}'",
                    .{arg},
                );
                return .{ .invalid = msg };
            }
        }
    }

    // Validate required arguments
    if (positional_index == 0) {
        const msg = try std.fmt.allocPrint(
            allocator,
            "Missing required argument: <archive>",
            .{},
        );
        return .{ .invalid = msg };
    }

    // Update output level based on flags
    extract_args.global.updateOutputLevel();

    return .{ .extract = extract_args };
}

// Tests
test "Subcommand: fromString with primary names" {
    try std.testing.expectEqual(Subcommand.extract, Subcommand.fromString("extract").?);
    try std.testing.expectEqual(Subcommand.compress, Subcommand.fromString("compress").?);
    try std.testing.expectEqual(Subcommand.list, Subcommand.fromString("list").?);
    try std.testing.expectEqual(Subcommand.help, Subcommand.fromString("help").?);
    try std.testing.expectEqual(Subcommand.version, Subcommand.fromString("version").?);
}

test "Subcommand: fromString with aliases" {
    try std.testing.expectEqual(Subcommand.extract, Subcommand.fromString("x").?);
    try std.testing.expectEqual(Subcommand.compress, Subcommand.fromString("c").?);
    try std.testing.expectEqual(Subcommand.compress, Subcommand.fromString("create").?);
    try std.testing.expectEqual(Subcommand.list, Subcommand.fromString("l").?);
    try std.testing.expectEqual(Subcommand.list, Subcommand.fromString("ls").?);
    try std.testing.expectEqual(Subcommand.help, Subcommand.fromString("--help").?);
    try std.testing.expectEqual(Subcommand.version, Subcommand.fromString("--version").?);
}

test "Subcommand: fromString with invalid input" {
    try std.testing.expectEqual(@as(?Subcommand, null), Subcommand.fromString("invalid"));
    try std.testing.expectEqual(@as(?Subcommand, null), Subcommand.fromString(""));
}

test "parseArgs: extract with minimal args" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "extract", "archive.tar.gz" };

    const parsed = try parseArgs(allocator, &args);
    defer parsed.deinit(allocator);

    switch (parsed) {
        .extract => |extract_args| {
            try std.testing.expectEqualStrings("archive.tar.gz", extract_args.archive_path);
            try std.testing.expectEqualStrings(".", extract_args.destination);
            try std.testing.expectEqual(false, extract_args.options.overwrite);
            try std.testing.expectEqual(false, extract_args.global.verbose);
        },
        else => try std.testing.expect(false),
    }
}

test "parseArgs: extract with all options" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{
        "extract",
        "-v",
        "-f",
        "-C",
        "/tmp/output",
        "archive.tar.gz",
    };

    const parsed = try parseArgs(allocator, &args);
    defer parsed.deinit(allocator);

    switch (parsed) {
        .extract => |extract_args| {
            try std.testing.expectEqualStrings("archive.tar.gz", extract_args.archive_path);
            try std.testing.expectEqualStrings("/tmp/output", extract_args.destination);
            try std.testing.expectEqual(true, extract_args.options.overwrite);
            try std.testing.expectEqual(true, extract_args.global.verbose);
            try std.testing.expectEqual(output.OutputLevel.verbose, extract_args.global.output_level);
        },
        else => try std.testing.expect(false),
    }
}

test "parseArgs: extract with positional destination" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "extract", "archive.tar.gz", "/dest" };

    const parsed = try parseArgs(allocator, &args);
    defer parsed.deinit(allocator);

    switch (parsed) {
        .extract => |extract_args| {
            try std.testing.expectEqualStrings("archive.tar.gz", extract_args.archive_path);
            try std.testing.expectEqualStrings("/dest", extract_args.destination);
        },
        else => try std.testing.expect(false),
    }
}

test "parseArgs: help" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{"help"};

    const parsed = try parseArgs(allocator, &args);
    defer parsed.deinit(allocator);

    switch (parsed) {
        .help => |subcommand| {
            try std.testing.expectEqual(@as(?[]const u8, null), subcommand);
        },
        else => try std.testing.expect(false),
    }
}

test "parseArgs: help for subcommand" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{ "help", "extract" };

    const parsed = try parseArgs(allocator, &args);
    defer parsed.deinit(allocator);

    switch (parsed) {
        .help => |subcommand| {
            try std.testing.expectEqualStrings("extract", subcommand.?);
        },
        else => try std.testing.expect(false),
    }
}

test "parseArgs: version" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{"version"};

    const parsed = try parseArgs(allocator, &args);
    defer parsed.deinit(allocator);

    switch (parsed) {
        .version => {},
        else => try std.testing.expect(false),
    }
}

test "parseArgs: invalid subcommand" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{"invalid_command"};

    const parsed = try parseArgs(allocator, &args);
    defer parsed.deinit(allocator);

    switch (parsed) {
        .invalid => {},
        else => try std.testing.expect(false),
    }
}

test "parseArgs: missing archive path" {
    const allocator = std.testing.allocator;
    const args = [_][]const u8{"extract"};

    const parsed = try parseArgs(allocator, &args);
    defer parsed.deinit(allocator);

    switch (parsed) {
        .invalid => {},
        else => try std.testing.expect(false),
    }
}
