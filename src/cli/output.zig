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

/// Output verbosity level
pub const OutputLevel = enum {
    /// Only errors
    quiet,
    /// Normal output
    normal,
    /// Detailed output
    verbose,
};

/// Color support configuration
pub const ColorMode = enum {
    /// Automatic detection based on environment
    auto,
    /// Always use colors
    always,
    /// Never use colors
    never,
};

/// ANSI color codes
pub const Color = enum {
    reset,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    bold,

    pub fn code(self: Color) []const u8 {
        return switch (self) {
            .reset => "\x1b[0m",
            .red => "\x1b[31m",
            .green => "\x1b[32m",
            .yellow => "\x1b[33m",
            .blue => "\x1b[34m",
            .magenta => "\x1b[35m",
            .cyan => "\x1b[36m",
            .white => "\x1b[37m",
            .bold => "\x1b[1m",
        };
    }
};

/// Output writer with color support
pub const OutputWriter = struct {
    file: std.fs.File,
    level: OutputLevel,
    use_color: bool,

    /// Initialize output writer
    pub fn init(file: std.fs.File, level: OutputLevel, color_mode: ColorMode) OutputWriter {
        return .{
            .file = file,
            .level = level,
            .use_color = shouldUseColor(color_mode, file),
        };
    }

    /// Determine if colors should be used
    fn shouldUseColor(mode: ColorMode, file: std.fs.File) bool {
        return switch (mode) {
            .always => true,
            .never => false,
            .auto => blk: {
                // NO_COLOR and ZARC_NO_COLOR: presence disables color (any OS)
                if (std.process.hasEnvVar(std.heap.page_allocator, "NO_COLOR") catch false) {
                    break :blk false;
                }
                if (std.process.hasEnvVar(std.heap.page_allocator, "ZARC_NO_COLOR") catch false) {
                    break :blk false;
                }

                // Check if the target file is a TTY
                break :blk file.isTty();
            },
        };
    }

    /// Write with color
    pub fn writeColor(self: OutputWriter, color: Color, text: []const u8) !void {
        if (self.use_color) {
            try self.file.writeAll(color.code());
        }
        try self.file.writeAll(text);
        if (self.use_color) {
            try self.file.writeAll(Color.reset.code());
        }
    }

    /// Print success message (green checkmark)
    pub fn printSuccess(self: OutputWriter, comptime fmt: []const u8, args: anytype) !void {
        if (self.level == .quiet) return;

        if (self.use_color) {
            try self.file.writeAll(Color.green.code());
            try self.file.writeAll("✓ ");
            try self.file.writeAll(Color.reset.code());
        } else {
            try self.file.writeAll("✓ ");
        }
        var buf: [1024]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, fmt ++ "\n", args);
        try self.file.writeAll(msg);
    }

    /// Print warning message (yellow warning sign)
    pub fn printWarning(self: OutputWriter, comptime fmt: []const u8, args: anytype) !void {
        if (self.level == .quiet) return;

        if (self.use_color) {
            try self.file.writeAll(Color.yellow.code());
            try self.file.writeAll("⚠ ");
            try self.file.writeAll(Color.reset.code());
        } else {
            try self.file.writeAll("⚠ ");
        }
        var buf: [1024]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, fmt ++ "\n", args);
        try self.file.writeAll(msg);
    }

    /// Print error message (red X)
    pub fn printError(self: OutputWriter, comptime fmt: []const u8, args: anytype) !void {
        if (self.use_color) {
            try self.file.writeAll(Color.red.code());
            try self.file.writeAll("✗ ");
            try self.file.writeAll(Color.reset.code());
        } else {
            try self.file.writeAll("✗ ");
        }
        var buf: [1024]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, fmt ++ "\n", args);
        try self.file.writeAll(msg);
    }

    /// Print info message
    pub fn printInfo(self: OutputWriter, comptime fmt: []const u8, args: anytype) !void {
        if (self.level == .quiet) return;

        var buf: [1024]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, fmt ++ "\n", args);
        try self.file.writeAll(msg);
    }

    /// Print verbose message (only in verbose mode)
    pub fn printVerbose(self: OutputWriter, comptime fmt: []const u8, args: anytype) !void {
        if (self.level != .verbose) return;

        var buf: [1024]u8 = undefined;
        const msg = try std.fmt.bufPrint(&buf, fmt ++ "\n", args);
        try self.file.writeAll(msg);
    }

    /// Print progress message (for extraction, compression, etc.)
    pub fn printProgress(self: OutputWriter, current: usize, total: usize, item: []const u8) !void {
        if (self.level == .quiet) return;

        if (self.level == .verbose) {
            var buf: [1024]u8 = undefined;
            const msg = try std.fmt.bufPrint(&buf, "  [{d}/{d}] {s}\n", .{ current, total, item });
            try self.file.writeAll(msg);
        }
    }
};

/// Format file size in human-readable format
pub fn formatSize(allocator: std.mem.Allocator, bytes: u64) ![]const u8 {
    if (bytes < 1024) {
        return std.fmt.allocPrint(allocator, "{d} B", .{bytes});
    } else if (bytes < 1024 * 1024) {
        const kb = @as(f64, @floatFromInt(bytes)) / 1024.0;
        return std.fmt.allocPrint(allocator, "{d:.1} KB", .{kb});
    } else if (bytes < 1024 * 1024 * 1024) {
        const mb = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0);
        return std.fmt.allocPrint(allocator, "{d:.1} MB", .{mb});
    } else {
        const gb = @as(f64, @floatFromInt(bytes)) / (1024.0 * 1024.0 * 1024.0);
        return std.fmt.allocPrint(allocator, "{d:.1} GB", .{gb});
    }
}

/// Format duration in human-readable format
pub fn formatDuration(allocator: std.mem.Allocator, nanoseconds: u64) ![]const u8 {
    const seconds = @as(f64, @floatFromInt(nanoseconds)) / 1_000_000_000.0;

    if (seconds < 1.0) {
        const ms = seconds * 1000.0;
        return std.fmt.allocPrint(allocator, "{d:.0}ms", .{ms});
    } else if (seconds < 60.0) {
        return std.fmt.allocPrint(allocator, "{d:.1}s", .{seconds});
    } else {
        const minutes = @floor(seconds / 60.0);
        const remaining_seconds = seconds - (minutes * 60.0);
        return std.fmt.allocPrint(allocator, "{d:.0}m {d:.0}s", .{ minutes, remaining_seconds });
    }
}

// Tests
test "OutputWriter: init" {
    const stdout_file = std.fs.File.stdout();
    const writer = OutputWriter.init(stdout_file, .normal, .never);

    try std.testing.expectEqual(OutputLevel.normal, writer.level);
    try std.testing.expectEqual(false, writer.use_color);
}

test "formatSize: various sizes" {
    const allocator = std.testing.allocator;

    {
        const result = try formatSize(allocator, 512);
        defer allocator.free(result);
        try std.testing.expectEqualStrings("512 B", result);
    }

    {
        const result = try formatSize(allocator, 1536); // 1.5 KB
        defer allocator.free(result);
        try std.testing.expectEqualStrings("1.5 KB", result);
    }

    {
        const result = try formatSize(allocator, 2 * 1024 * 1024); // 2 MB
        defer allocator.free(result);
        try std.testing.expectEqualStrings("2.0 MB", result);
    }

    {
        const result = try formatSize(allocator, 3 * 1024 * 1024 * 1024); // 3 GB
        defer allocator.free(result);
        try std.testing.expectEqualStrings("3.0 GB", result);
    }
}

test "formatDuration: various durations" {
    const allocator = std.testing.allocator;

    {
        const result = try formatDuration(allocator, 500_000_000); // 500ms
        defer allocator.free(result);
        try std.testing.expectEqualStrings("500ms", result);
    }

    {
        const result = try formatDuration(allocator, 2_300_000_000); // 2.3s
        defer allocator.free(result);
        try std.testing.expectEqualStrings("2.3s", result);
    }

    {
        const result = try formatDuration(allocator, 125_000_000_000); // 125s = 2m 5s
        defer allocator.free(result);
        try std.testing.expectEqualStrings("2m 5s", result);
    }
}

test "Color: code values" {
    try std.testing.expectEqualStrings("\x1b[0m", Color.reset.code());
    try std.testing.expectEqualStrings("\x1b[31m", Color.red.code());
    try std.testing.expectEqualStrings("\x1b[32m", Color.green.code());
    try std.testing.expectEqualStrings("\x1b[33m", Color.yellow.code());
}
