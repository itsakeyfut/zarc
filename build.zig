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

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // zlib dependency (Phase 1-2 temporary C integration)
    // See ADR-004-zlib-integration.md for rationale and migration plan
    // Migration target: Phase 3 (Pure Zig implementation)
    const zlib_dep = b.dependency("zlib", .{
        .target = target,
        .optimize = optimize,
    });

    // Main executable
    const exe = b.addExecutable(.{
        .name = "zarc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link C dependencies (temporary, Phase 1-2 only)
    exe.linkLibC();
    exe.linkLibrary(zlib_dep.artifact("z")); // zlib for compression
    exe.addCSourceFile(.{
        .file = b.path("src/c/zlib_compress.c"), // C wrapper for zlib
        .flags = &.{"-std=c99"},
    });
    exe.addIncludePath(b.path("src/c"));
    b.installArtifact(exe);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    unit_tests.linkLibC();
    unit_tests.linkLibrary(zlib_dep.artifact("z"));
    unit_tests.addCSourceFile(.{
        .file = b.path("src/c/zlib_compress.c"),
        .flags = &.{"-std=c99"},
    });
    unit_tests.addIncludePath(b.path("src/c"));

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Shared source module for test imports
    const src_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Unit tests (tests/unit directory)
    const unit_only_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zarc", .module = src_module },
            },
        }),
    });
    unit_only_tests.linkLibC();
    unit_only_tests.linkLibrary(zlib_dep.artifact("z"));
    unit_only_tests.addCSourceFile(.{
        .file = b.path("src/c/zlib_compress.c"),
        .flags = &.{"-std=c99"},
    });
    unit_only_tests.addIncludePath(b.path("src/c"));

    const run_unit_only_tests = b.addRunArtifact(unit_only_tests);
    run_unit_only_tests.setCwd(b.path(".")); // Set working directory to project root
    const unit_only_step = b.step("test-unit", "Run unit tests only");
    unit_only_step.dependOn(&run_unit_only_tests.step);

    // Integration tests (tests/integration directory)
    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zarc", .module = src_module },
            },
        }),
    });
    integration_tests.linkLibC();
    integration_tests.linkLibrary(zlib_dep.artifact("z"));
    integration_tests.addCSourceFile(.{
        .file = b.path("src/c/zlib_compress.c"),
        .flags = &.{"-std=c99"},
    });
    integration_tests.addIncludePath(b.path("src/c"));

    const run_integration_tests = b.addRunArtifact(integration_tests);
    run_integration_tests.setCwd(b.path(".")); // Set working directory to project root
    const integration_step = b.step("test-integration", "Run integration tests");
    integration_step.dependOn(&run_integration_tests.step);

    // All tests
    const test_all_step = b.step("test-all", "Run all tests");
    test_all_step.dependOn(&run_unit_tests.step);
    test_all_step.dependOn(&run_unit_only_tests.step);
    test_all_step.dependOn(&run_integration_tests.step);

    // Cross-compilation targets
    addCrossCompileTargets(b, optimize);

    // Documentation generation
    const docs = b.addInstallDirectory(.{
        .source_dir = exe.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&docs.step);
}

fn addCrossCompileTargets(b: *std.Build, optimize: std.builtin.OptimizeMode) void {
    const targets = [_]struct {
        name: []const u8,
        query: std.Target.Query,
    }{
        .{
            .name = "linux-x86_64",
            .query = .{
                .cpu_arch = .x86_64,
                .os_tag = .linux,
                .abi = .musl,
            },
        },
        .{
            .name = "linux-aarch64",
            .query = .{
                .cpu_arch = .aarch64,
                .os_tag = .linux,
                .abi = .musl,
            },
        },
        .{
            .name = "windows-x86_64",
            .query = .{
                .cpu_arch = .x86_64,
                .os_tag = .windows,
            },
        },
        .{
            .name = "macos-x86_64",
            .query = .{
                .cpu_arch = .x86_64,
                .os_tag = .macos,
            },
        },
        .{
            .name = "macos-aarch64",
            .query = .{
                .cpu_arch = .aarch64,
                .os_tag = .macos,
            },
        },
    };

    // Build all targets
    const build_all_step = b.step("build-all", "Build for all targets");

    for (targets) |t| {
        const resolved_target = b.resolveTargetQuery(t.query);

        // Get zlib dependency for this target
        const target_zlib_dep = b.dependency("zlib", .{
            .target = resolved_target,
            .optimize = optimize,
        });

        const exe = b.addExecutable(.{
            .name = b.fmt("zarc-{s}", .{t.name}),
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = resolved_target,
                .optimize = optimize,
            }),
        });

        exe.linkLibC();
        exe.linkLibrary(target_zlib_dep.artifact("z"));
        exe.addCSourceFile(.{
            .file = b.path("src/c/zlib_compress.c"),
            .flags = &.{"-std=c99"},
        });
        exe.addIncludePath(b.path("src/c"));

        const install = b.addInstallArtifact(exe, .{});

        const step = b.step(
            b.fmt("build-{s}", .{t.name}),
            b.fmt("Build for {s}", .{t.name}),
        );
        step.dependOn(&install.step);

        // Add to build-all
        build_all_step.dependOn(&install.step);
    }
}
