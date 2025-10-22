const std = @import("std");

// Unit test entry point
// This file aggregates all unit tests for the zarc project

test "unit tests: placeholder" {
    // Placeholder test to ensure the test framework works
    try std.testing.expect(true);
}

// Import all unit test modules
test {
    // TAR format tests
    _ = @import("tar_test.zig");

    // Platform abstraction tests
    _ = @import("platform_test.zig");

    // Add more unit test modules here as they are created
    // Example:
    // _ = @import("util_test.zig");
    // _ = @import("errors_test.zig");
}
