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

/// Core layer errors
pub const CoreError = error{
    /// Out of memory
    OutOfMemory,
    /// Invalid argument
    InvalidArgument,
    /// Overflow
    Overflow,
    /// Buffer size is too small
    BufferTooSmall,
};

/// I/O layer errors
pub const IOError = error{
    /// File not found
    FileNotFound,
    /// Permission denied
    PermissionDenied,
    /// Disk full
    DiskFull,
    /// Read error
    ReadError,
    /// Write error
    WriteError,
    /// Seek error
    SeekError,
};

/// Compression layer errors
pub const CompressionError = error{
    /// Invalid data
    InvalidData,
    /// Unsupported compression method
    UnsupportedMethod,
    /// Corrupted stream
    CorruptedStream,
    /// Decompression failed
    DecompressionFailed,
    /// Compression failed
    CompressionFailed,
    /// Checksum mismatch (data integrity check failed)
    ChecksumMismatch,
};

/// Format layer errors
pub const FormatError = error{
    /// Invalid format
    InvalidFormat,
    /// Unsupported version
    UnsupportedVersion,
    /// Corrupted header
    CorruptedHeader,
    /// Incomplete archive
    IncompleteArchive,
};

/// Application layer errors
pub const AppError = error{
    /// Path traversal attack detected
    PathTraversalAttempt,
    /// Absolute path not allowed
    AbsolutePathNotAllowed,
    /// Symlink escape attempt detected
    SymlinkEscapeAttempt,
    /// File size exceeds limit
    FileSizeExceedsLimit,
    /// Suspicious compression ratio (possible Zip Bomb)
    SuspiciousCompressionRatio,
    /// Total extracted size exceeds limit
    TotalSizeExceedsLimit,
    /// Empty path provided
    EmptyPath,
    /// Path contains NULL byte
    NullByteInPath,
    /// Path exceeds maximum length
    PathTooLong,
    /// Path contains invalid character
    InvalidCharacterInPath,
    /// Symlinks are not allowed by policy
    SymlinkNotAllowed,
    /// Absolute symlinks are not allowed
    AbsoluteSymlinkNotAllowed,
    /// Filename contains NULL byte
    NullByteInFilename,
};

/// Unified error type for all zarc errors
pub const ZarcError = CoreError || IOError || CompressionError || FormatError || AppError;

/// Context information for where an error occurred
pub const ErrorContext = struct {
    /// File path where the error occurred
    path: []const u8 = "",

    /// Offset position where the error occurred
    offset: u64 = 0,

    /// Additional detail information
    detail: []const u8 = "",

    /// System error code (for OS errors)
    system_error: ?anyerror = null,
};

/// Error with context information
pub const ContextualError = struct {
    err: ZarcError,
    context: ErrorContext,

    /// Format the error message for output
    pub fn format(
        self: ContextualError,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("Error: {s}", .{@errorName(self.err)});

        if (self.context.path.len > 0) {
            try writer.print("\nFile: {s}", .{self.context.path});
        }

        if (self.context.offset > 0) {
            try writer.print("\nOffset: 0x{x}", .{self.context.offset});
        }

        if (self.context.detail.len > 0) {
            try writer.print("\nDetail: {s}", .{self.context.detail});
        }

        if (self.context.system_error) |sys_err| {
            try writer.print("\nSystem Error: {s}", .{@errorName(sys_err)});
        }
    }
};

/// Format error message with context information
///
/// Parameters:
///   - allocator: Memory allocator
///   - err: Error to format
///   - context: Error context
///
/// Returns:
///   - Formatted error message (caller must free)
///
/// Errors:
///   - error.OutOfMemory: Failed to allocate memory for message
pub fn formatError(
    allocator: std.mem.Allocator,
    err: ZarcError,
    context: ErrorContext,
) ![]const u8 {
    return switch (err) {
        error.FileNotFound => try std.fmt.allocPrint(
            allocator,
            \\Error: Cannot open file
            \\File: {s}
            \\Reason: File not found
            \\Suggestion: Check if the file path is correct
        ,
            .{context.path},
        ),

        error.PermissionDenied => try std.fmt.allocPrint(
            allocator,
            \\Error: Permission denied
            \\File: {s}
            \\Reason: Insufficient permissions to access this file
            \\Suggestion: Check file permissions or run with appropriate privileges
        ,
            .{context.path},
        ),

        error.CorruptedHeader => try std.fmt.allocPrint(
            allocator,
            \\Error: Archive is corrupted
            \\File: {s}
            \\Offset: 0x{x}
            \\Reason: Invalid header format at this position
            \\Suggestion: The archive may be incomplete or damaged
            \\            Try re-downloading or use 'zarc test' to verify
        ,
            .{ context.path, context.offset },
        ),

        error.PathTraversalAttempt => try std.fmt.allocPrint(
            allocator,
            \\Error: Path traversal attack detected
            \\File: {s}
            \\Entry: {s}
            \\Reason: Archive contains paths with '..' that escape extraction directory
            \\Suggestion: This archive may be malicious
            \\            Use --allow-path-traversal to override (NOT RECOMMENDED)
        ,
            .{ context.path, context.detail },
        ),

        error.DiskFull => try std.fmt.allocPrint(
            allocator,
            \\Error: Cannot write to disk
            \\Destination: {s}
            \\Reason: No space left on device
            \\Suggestion: Free up disk space and try again
            \\            Check available space with 'df -h'
        ,
            .{context.path},
        ),

        error.InvalidFormat => try std.fmt.allocPrint(
            allocator,
            \\Error: Invalid archive format
            \\File: {s}
            \\Reason: The file does not appear to be a valid archive
            \\Suggestion: Check if the file is corrupted or in an unsupported format
        ,
            .{context.path},
        ),

        error.UnsupportedVersion => try std.fmt.allocPrint(
            allocator,
            \\Error: Unsupported archive version
            \\File: {s}
            \\Detail: {s}
            \\Suggestion: This archive version is not supported yet
        ,
            .{ context.path, context.detail },
        ),

        error.SuspiciousCompressionRatio => try std.fmt.allocPrint(
            allocator,
            \\Error: Suspicious compression ratio detected (possible Zip Bomb)
            \\File: {s}
            \\Detail: {s}
            \\Reason: Unusually high compression ratio may indicate a malicious archive
            \\Suggestion: Verify the archive source before proceeding
        ,
            .{ context.path, context.detail },
        ),

        else => try std.fmt.allocPrint(
            allocator,
            "Error: {s}",
            .{@errorName(err)},
        ),
    };
}

// Tests
test "ErrorContext: default values" {
    const ctx = ErrorContext{};
    try std.testing.expectEqualStrings("", ctx.path);
    try std.testing.expectEqual(@as(u64, 0), ctx.offset);
    try std.testing.expectEqualStrings("", ctx.detail);
    try std.testing.expectEqual(@as(?anyerror, null), ctx.system_error);
}

test "ContextualError: format output" {
    const ctx_err = ContextualError{
        .err = error.FileNotFound,
        .context = .{
            .path = "/path/to/file.tar.gz",
            .offset = 512,
            .detail = "test detail",
        },
    };

    var buffer = std.array_list.Aligned(u8, null).empty;
    defer buffer.deinit(std.testing.allocator);

    try ctx_err.format("", .{}, buffer.writer(std.testing.allocator));

    const output = buffer.items;
    try std.testing.expect(std.mem.indexOf(u8, output, "Error: FileNotFound") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "File: /path/to/file.tar.gz") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Offset: 0x200") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Detail: test detail") != null);
}

test "formatError: FileNotFound" {
    const allocator = std.testing.allocator;

    const msg = try formatError(
        allocator,
        error.FileNotFound,
        .{ .path = "archive.tar.gz" },
    );
    defer allocator.free(msg);

    try std.testing.expect(std.mem.indexOf(u8, msg, "Cannot open file") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "archive.tar.gz") != null);
}

test "formatError: PathTraversalAttempt" {
    const allocator = std.testing.allocator;

    const msg = try formatError(
        allocator,
        error.PathTraversalAttempt,
        .{
            .path = "malicious.tar",
            .detail = "../../etc/passwd",
        },
    );
    defer allocator.free(msg);

    try std.testing.expect(std.mem.indexOf(u8, msg, "Path traversal attack") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "malicious.tar") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "../../etc/passwd") != null);
}

test "formatError: CorruptedHeader" {
    const allocator = std.testing.allocator;

    const msg = try formatError(
        allocator,
        error.CorruptedHeader,
        .{
            .path = "corrupted.tar",
            .offset = 1024,
        },
    );
    defer allocator.free(msg);

    try std.testing.expect(std.mem.indexOf(u8, msg, "corrupted") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "0x400") != null);
}
