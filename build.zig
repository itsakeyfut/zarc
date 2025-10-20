const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main executable
    const exe = b.addExecutable(.{
        .name = "zarc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.linkLibC();
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

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Integration tests (when tests/integration directory exists)
    const src_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

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

    const run_integration_tests = b.addRunArtifact(integration_tests);
    run_integration_tests.setCwd(b.path(".")); // Set working directory to project root
    const integration_step = b.step("test-integration", "Run integration tests");
    integration_step.dependOn(&run_integration_tests.step);

    // All tests
    const test_all_step = b.step("test-all", "Run all tests");
    test_all_step.dependOn(&run_unit_tests.step);
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

        const exe = b.addExecutable(.{
            .name = b.fmt("zarc-{s}", .{t.name}),
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = resolved_target,
                .optimize = optimize,
            }),
        });

        exe.linkLibC();

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
