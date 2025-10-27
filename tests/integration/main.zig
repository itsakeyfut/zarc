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

    // Compatibility integration tests (Issue #13)
    _ = @import("compatibility_test.zig");

    // Comprehensive tar.gz integration tests (Issue #56)
    _ = @import("targz_test.zig");

    // Add more integration test modules here as they are created
    // Example:
    // _ = @import("compression_test.zig");
    // _ = @import("roundtrip_test.zig");
}
