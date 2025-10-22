const std = @import("std");

// Integration test entry point
// This file aggregates all integration tests for multi-module scenarios

test "integration tests: placeholder" {
    // Placeholder test to ensure the test framework works
    try std.testing.expect(true);
}

// Import all integration test modules
test {
    // TAR reader integration tests
    _ = @import("tar_reader_test.zig");

    // Archive extraction integration tests
    _ = @import("extract_test.zig");

    // Security integration tests
    _ = @import("security_test.zig");

    // Add more integration test modules here as they are created
    // Example:
    // _ = @import("compression_test.zig");
    // _ = @import("roundtrip_test.zig");
}
