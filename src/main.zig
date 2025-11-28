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

// Core modules
pub const core = struct {
    pub const errors = @import("core/errors.zig");
    pub const types = @import("core/types.zig");
    pub const util = @import("core/util.zig");
};

// Format modules
pub const formats = struct {
    pub const archive = @import("formats/archive.zig");
    pub const tar = struct {
        pub const header = @import("formats/tar/header.zig");
        pub const reader = @import("formats/tar/reader.zig");
    };
};

// I/O modules
pub const io = struct {
    pub const reader = @import("io/reader.zig");
    pub const writer = @import("io/writer.zig");
    pub const filesystem = @import("io/filesystem.zig");
    pub const streaming = @import("io/streaming.zig");
};

// Compression modules
pub const compress = struct {
    pub const zlib = @import("compress/zlib.zig");
    pub const gzip = @import("compress/gzip.zig");
    pub const deflate = struct {
        pub const decode = @import("compress/deflate/decode.zig");
        pub const encode = @import("compress/deflate/encode.zig");
    };
};

// Application modules
pub const app = struct {
    pub const security = @import("app/security.zig");
    pub const extract = @import("app/extract.zig");
};

// CLI modules
pub const cli = struct {
    pub const args = @import("cli/args.zig");
    pub const commands = @import("cli/commands.zig");
    pub const output = @import("cli/output.zig");
    pub const progress = @import("cli/progress.zig");
};

// Platform abstraction
pub const platform = struct {
    pub const common = @import("platform/common.zig");
    pub const linux = @import("platform/linux.zig");
    pub const windows = @import("platform/windows.zig");
    pub const macos = @import("platform/macos.zig");
    pub const bsd = @import("platform/bsd.zig");
};

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.log.err("Memory leak detected", .{});
        }
    }
    const allocator = gpa.allocator();

    // Get command-line arguments (skip program name)
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const cli_args = if (args.len > 1) args[1..] else &[_][]const u8{};

    // Parse arguments
    const parsed = cli.args.parseArgs(allocator, cli_args) catch |err| {
        const stderr_file = std.io.getStdErr();
        var err_out = cli.output.OutputWriter.init(stderr_file, .normal, .auto);
        err_out.printError("Failed to parse arguments: {s}", .{@errorName(err)}) catch {};
        stderr_file.writeAll("Use 'zarc help' for usage.\n") catch {};
        std.process.exit(2);
    };
    defer parsed.deinit(allocator);

    // Execute command
    var exit_code: u8 = 1; // default to failure unless proven otherwise
    defer std.process.exit(exit_code);
    exit_code = executeCommand(allocator, parsed) catch |err| blk: {
        // Common CLI behavior: ignore SIGPIPE/BrokenPipe as success
        if (err == error.BrokenPipe) break :blk 0;
        const stderr_file = std.io.getStdErr();
        var err_out = cli.output.OutputWriter.init(stderr_file, .normal, .auto);
        err_out.printError("Unexpected error: {s}", .{@errorName(err)}) catch {};
        break :blk 1;
    };
}

fn executeCommand(allocator: std.mem.Allocator, parsed: cli.args.ParsedArgs) !u8 {
    const stdout_file = std.io.getStdOut();
    const stderr_file = std.io.getStdErr();

    return switch (parsed) {
        .extract => |extract_args| {
            return cli.commands.runExtract(allocator, extract_args);
        },
        .help => |subcommand| {
            try cli.commands.printHelp(stdout_file, subcommand);
            return 0;
        },
        .version => {
            try cli.commands.printVersion(stdout_file);
            return 0;
        },
        .invalid => |msg| {
            var err_out = cli.output.OutputWriter.init(stderr_file, .normal, .auto);
            try err_out.printError("{s}", .{msg});
            try stderr_file.writeAll("\nUse 'zarc help' for usage information.\n");
            return 2;
        },
        else => {
            var err_out = cli.output.OutputWriter.init(stderr_file, .normal, .auto);
            try err_out.printError("Command not yet implemented", .{});
            return 1;
        },
    };
}

// Test references to include all module tests
test {
    std.testing.refAllDecls(@This());
    _ = core.errors;
    _ = core.types;
    _ = core.util;
    _ = formats.archive;
    _ = formats.tar.header;
    _ = formats.tar.reader;
    _ = io.reader;
    _ = io.writer;
    _ = io.filesystem;
    _ = compress.zlib;
    _ = compress.gzip;
    _ = compress.deflate.decode;
    _ = compress.deflate.encode;
    _ = app.security;
    _ = app.extract;
    _ = platform.common;
    _ = platform.linux;
    _ = platform.windows;
    _ = platform.macos;
    _ = platform.bsd;
}
