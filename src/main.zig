const std = @import("std");

// Core modules
pub const core = struct {
    pub const errors = @import("core/errors.zig");
    pub const types = @import("core/types.zig");
    pub const util = @import("core/util.zig");
};

// I/O modules
pub const io = struct {
    pub const reader = @import("io/reader.zig");
    pub const writer = @import("io/writer.zig");
    pub const filesystem = @import("io/filesystem.zig");
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
    std.debug.print("Hello, world!\n", .{});
}

// Test references to include all module tests
test {
    std.testing.refAllDecls(@This());
    _ = core.errors;
    _ = core.types;
    _ = core.util;
    _ = io.reader;
    _ = io.writer;
    _ = io.filesystem;
    _ = platform.common;
    _ = platform.linux;
    _ = platform.windows;
    _ = platform.macos;
    _ = platform.bsd;
}
