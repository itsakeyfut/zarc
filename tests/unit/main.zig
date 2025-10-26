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

// Unit test entry point
// This file aggregates all unit tests for the zarc project

test "unit tests: placeholder" {
    // Placeholder test to ensure the test framework works
    try std.testing.expect(true);
}

// Import all unit test modules
test {
    // TAR format tests
    // Temporarily disabled due to compilation errors (separate issue)
    // _ = @import("tar_test.zig");

    // Platform abstraction tests
    _ = @import("platform_test.zig");

    // Compression tests
    _ = @import("compress_test.zig");

    // Deflate decompression tests
    _ = @import("deflate_test.zig");

    // Add more unit test modules here as they are created
    // Example:
    // _ = @import("util_test.zig");
    // _ = @import("errors_test.zig");
}
