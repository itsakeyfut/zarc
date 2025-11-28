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

//! Deflate compression implementation (RFC 1951)
//!
//! This module provides pure Zig Deflate compression supporting:
//! - Uncompressed blocks (BTYPE=00)
//! - Fixed Huffman blocks (BTYPE=01)
//! - Dynamic Huffman blocks (BTYPE=10)
//!
//! Features:
//! - LZ77 sliding window compression
//! - Huffman tree generation for optimal encoding
//! - Compression levels 1-9
//! - Compatible with standard gzip/zlib decompressors
//!
//! Implementation note:
//! This is the Phase 3+ pure Zig implementation that replaces the C zlib dependency.

const std = @import("std");

/// Deflate compression constants (RFC 1951)
pub const constants = struct {
    /// Maximum sliding window size (32KB)
    pub const window_size: u32 = 32768;
    /// Window mask for efficient modulo operations
    pub const window_mask: u32 = window_size - 1;

    /// Minimum match length
    pub const min_match: u32 = 3;
    /// Maximum match length
    pub const max_match: u32 = 258;

    /// Maximum distance for back-references
    pub const max_distance: u32 = 32768;

    /// Hash table size (power of 2 for efficient hashing)
    pub const hash_size: u32 = 32768;
    pub const hash_mask: u32 = hash_size - 1;
    /// Hash chain limit (to prevent excessive searches)
    pub const max_chain_length: u32 = 4096;

    /// Number of literal/length codes
    pub const num_lit_len_codes: u32 = 286;
    /// Number of distance codes
    pub const num_dist_codes: u32 = 30;
    /// End of block marker
    pub const end_of_block: u32 = 256;

    /// Maximum code length for Huffman codes
    pub const max_code_length: u32 = 15;
    /// Maximum code length for code length alphabet
    pub const max_cl_code_length: u32 = 7;
};

/// Compression level configuration
pub const CompressionLevel = enum(u4) {
    /// No compression (store only)
    none = 0,
    /// Fastest compression (level 1)
    fastest = 1,
    level_2 = 2,
    level_3 = 3,
    level_4 = 4,
    /// Balanced compression (level 5)
    level_5 = 5,
    /// Default compression (level 6)
    default = 6,
    level_7 = 7,
    level_8 = 8,
    /// Maximum compression (level 9)
    best = 9,

    /// Get the maximum hash chain length for this compression level
    pub fn getMaxChainLength(self: CompressionLevel) u32 {
        return switch (self) {
            .none => 0,
            .fastest => 4,
            .level_2 => 8,
            .level_3 => 16,
            .level_4 => 32,
            .level_5 => 64,
            .default => 128,
            .level_7 => 256,
            .level_8 => 512,
            .best => constants.max_chain_length,
        };
    }

    /// Get the lazy match evaluation threshold
    pub fn getLazyMatchThreshold(self: CompressionLevel) u32 {
        return switch (self) {
            .none => 0,
            .fastest => 4,
            .level_2 => 8,
            .level_3 => 16,
            .level_4 => 32,
            .level_5 => 64,
            .default => 128,
            .level_7 => 128,
            .level_8 => 258,
            .best => 258,
        };
    }

    /// Whether to use lazy matching for this level
    pub fn useLazyMatching(self: CompressionLevel) bool {
        return @intFromEnum(self) >= 4;
    }
};

/// LZ77 token representing either a literal byte or a length/distance pair
pub const Token = union(enum) {
    /// Literal byte value
    literal: u8,
    /// Match: length and distance back
    match: struct {
        length: u16,
        distance: u16,
    },
};

/// Huffman code entry
pub const HuffmanCode = struct {
    /// The encoded bits
    code: u16 = 0,
    /// Number of bits in the code
    length: u4 = 0,
};

/// Fixed Huffman tables (RFC 1951 Section 3.2.6)
pub const fixed_huffman = struct {
    /// Number of fixed literal/length codes (288 per RFC 1951)
    const num_fixed_codes: u32 = 288;

    /// Fixed literal/length codes
    pub const lit_len_codes: [num_fixed_codes]HuffmanCode = blk: {
        var codes: [num_fixed_codes]HuffmanCode = undefined;
        // 0-143: 8 bits, codes 00110000-10111111
        for (0..144) |i| {
            codes[i] = .{
                .code = @intCast(bitReverse(u9, 0b00110000 + i) >> 1),
                .length = 8,
            };
        }
        // 144-255: 9 bits, codes 110010000-111111111
        for (144..256) |i| {
            codes[i] = .{
                .code = @intCast(bitReverse(u9, 0b110010000 + (i - 144))),
                .length = 9,
            };
        }
        // 256-279: 7 bits, codes 0000000-0010111
        for (256..280) |i| {
            codes[i] = .{
                .code = @intCast(bitReverse(u9, i - 256) >> 2),
                .length = 7,
            };
        }
        // 280-287: 8 bits, codes 11000000-11000111
        for (280..288) |i| {
            codes[i] = .{
                .code = @intCast(bitReverse(u9, 0b11000000 + (i - 280)) >> 1),
                .length = 8,
            };
        }
        break :blk codes;
    };

    /// Fixed distance codes (all 5-bit codes 0-31)
    pub const dist_codes: [constants.num_dist_codes]HuffmanCode = blk: {
        var codes: [constants.num_dist_codes]HuffmanCode = undefined;
        for (0..constants.num_dist_codes) |i| {
            codes[i] = .{
                .code = @intCast(bitReverse(u5, @intCast(i))),
                .length = 5,
            };
        }
        break :blk codes;
    };
};

/// Reverse bits in an integer (for Huffman code output)
fn bitReverse(comptime T: type, value: T) T {
    return @bitReverse(value);
}

/// Length code lookup table
/// Maps match lengths (3-258) to length codes (257-285)
pub const length_code_table: [259]u16 = blk: {
    var table: [259]u16 = undefined;
    // Invalid lengths 0-2
    table[0] = 0;
    table[1] = 0;
    table[2] = 0;
    // RFC 1951 length code table
    const bases = [_]u16{ 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 };
    var code: u16 = 257;
    for (bases, 0..) |base, idx| {
        const next_base = if (idx + 1 < bases.len) bases[idx + 1] else 259;
        for (base..next_base) |len| {
            if (len < 259) {
                table[len] = code;
            }
        }
        code += 1;
    }
    break :blk table;
};

/// Extra bits for length codes (257-285)
pub const length_extra_bits: [29]u4 = .{
    0, 0, 0, 0, 0, 0, 0, 0, // 257-264
    1, 1, 1, 1, // 265-268
    2, 2, 2, 2, // 269-272
    3, 3, 3, 3, // 273-276
    4, 4, 4, 4, // 277-280
    5, 5, 5, 5, // 281-284
    0, // 285
};

/// Base lengths for length codes (257-285)
pub const length_base: [29]u16 = .{
    3, 4, 5, 6, 7, 8, 9, 10, // 257-264
    11, 13, 15, 17, // 265-268
    19, 23, 27, 31, // 269-272
    35, 43, 51, 59, // 273-276
    67, 83, 99, 115, // 277-280
    131, 163, 195, 227, // 281-284
    258, // 285
};

/// Distance code lookup table
/// Maps distances (1-32768) to distance codes (0-29)
pub fn getDistanceCode(distance: u16) u5 {
    std.debug.assert(distance > 0 and distance <= constants.max_distance);
    if (distance <= 256) {
        return distance_code_small[distance];
    }
    // For distances > 256, search the distance_base table
    var code: u5 = 0;
    while (code < 29) : (code += 1) {
        if (distance >= distance_base[code] and distance < distance_base[code + 1]) {
            return code;
        }
    }
    return 29; // Maximum distance code
}

/// Small distance code table (0-256)
/// Maps distance to distance code based on RFC 1951 table
const distance_code_small: [257]u5 = blk: {
    @setEvalBranchQuota(10000);
    var table: [257]u5 = undefined;
    table[0] = 0; // Invalid, but set to 0

    // Build table from distance_base values
    for (1..257) |d| {
        // Find the correct distance code
        var code: u5 = 0;
        while (code < 29) : (code += 1) {
            const base = distance_base[code];
            const next_base = distance_base[code + 1];
            if (d >= base and d < next_base) {
                break;
            }
        }
        table[d] = code;
    }
    break :blk table;
};

/// Extra bits for distance codes (0-29)
pub const distance_extra_bits: [30]u4 = .{
    0, 0, 0, 0, // 0-3
    1, 1, // 4-5
    2, 2, // 6-7
    3, 3, // 8-9
    4, 4, // 10-11
    5, 5, // 12-13
    6, 6, // 14-15
    7, 7, // 16-17
    8, 8, // 18-19
    9, 9, // 20-21
    10, 10, // 22-23
    11, 11, // 24-25
    12, 12, // 26-27
    13, 13, // 28-29
};

/// Base distances for distance codes (0-29)
pub const distance_base: [30]u16 = .{
    1, 2, 3, 4, // 0-3
    5, 7, // 4-5
    9, 13, // 6-7
    17, 25, // 8-9
    33, 49, // 10-11
    65, 97, // 12-13
    129, 193, // 14-15
    257, 385, // 16-17
    513, 769, // 18-19
    1025, 1537, // 20-21
    2049, 3073, // 22-23
    4097, 6145, // 24-25
    8193, 12289, // 26-27
    16385, 24577, // 28-29
};

/// Bit writer for outputting deflate stream
pub const BitWriter = struct {
    buffer: std.ArrayList(u8),
    bit_buffer: u32 = 0,
    bit_count: u5 = 0,

    pub fn init(allocator: std.mem.Allocator) BitWriter {
        return .{
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *BitWriter) void {
        self.buffer.deinit();
    }

    /// Write bits to the output (LSB first, as per Deflate spec)
    pub fn writeBits(self: *BitWriter, value: u32, count: u5) !void {
        self.bit_buffer |= value << self.bit_count;
        self.bit_count += count;

        while (self.bit_count >= 8) {
            try self.buffer.append(@truncate(self.bit_buffer));
            self.bit_buffer >>= 8;
            self.bit_count -= 8;
        }
    }

    /// Write a Huffman code (already reversed for LSB-first output)
    pub fn writeCode(self: *BitWriter, code: HuffmanCode) !void {
        try self.writeBits(code.code, code.length);
    }

    /// Flush remaining bits (pad with zeros to byte boundary)
    pub fn flush(self: *BitWriter) !void {
        if (self.bit_count > 0) {
            try self.buffer.append(@truncate(self.bit_buffer));
            self.bit_buffer = 0;
            self.bit_count = 0;
        }
    }

    /// Align to byte boundary (for uncompressed blocks)
    pub fn alignToByte(self: *BitWriter) !void {
        if (self.bit_count > 0) {
            try self.buffer.append(@truncate(self.bit_buffer));
            self.bit_buffer = 0;
            self.bit_count = 0;
        }
    }

    /// Get the output data
    pub fn getData(self: *BitWriter) []u8 {
        return self.buffer.items;
    }

    /// Transfer ownership of data to caller
    pub fn toOwnedSlice(self: *BitWriter) ![]u8 {
        // Ensure all bits are flushed
        try self.flush();
        return self.buffer.toOwnedSlice();
    }
};

/// LZ77 compressor with hash-based matching
pub const LZ77Compressor = struct {
    allocator: std.mem.Allocator,
    /// Hash table: maps hash -> position in window
    hash_table: []u32,
    /// Hash chain: previous position with same hash
    hash_chain: []u32,
    /// Current window position
    window_pos: u32 = 0,
    /// Compression level settings
    level: CompressionLevel,

    const Self = @This();
    const nil_pos: u32 = 0xFFFFFFFF;

    pub fn init(allocator: std.mem.Allocator, level: CompressionLevel) !Self {
        const hash_table = try allocator.alloc(u32, constants.hash_size);
        @memset(hash_table, nil_pos);

        const hash_chain = try allocator.alloc(u32, constants.window_size);
        @memset(hash_chain, nil_pos);

        return .{
            .allocator = allocator,
            .hash_table = hash_table,
            .hash_chain = hash_chain,
            .level = level,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.hash_table);
        self.allocator.free(self.hash_chain);
    }

    /// Calculate hash for 3 bytes
    fn hash(data: []const u8, pos: usize) u32 {
        if (pos + 2 >= data.len) return 0;
        const h: u32 = (@as(u32, data[pos]) << 10) ^
            (@as(u32, data[pos + 1]) << 5) ^
            @as(u32, data[pos + 2]);
        return h & constants.hash_mask;
    }

    /// Update hash table with new position
    fn updateHash(self: *Self, data: []const u8, pos: u32) void {
        if (pos + 2 >= data.len) return;
        const h = hash(data, pos);
        // Link current position into chain
        self.hash_chain[pos & constants.window_mask] = self.hash_table[h];
        // Update head of chain
        self.hash_table[h] = pos;
    }

    /// Find longest match at current position
    fn findMatch(self: *Self, data: []const u8, pos: u32, prev_length: u32) ?Token {
        if (pos + constants.min_match > data.len) return null;

        const h = hash(data, pos);
        var match_pos = self.hash_table[h];
        var best_length: u32 = prev_length;
        var best_distance: u32 = 0;

        const max_chain = self.level.getMaxChainLength();
        var chain_count: u32 = 0;

        const max_distance = @min(pos, constants.max_distance);
        const max_length = @min(constants.max_match, @as(u32, @intCast(data.len)) - pos);

        while (match_pos != nil_pos and chain_count < max_chain) : (chain_count += 1) {
            const distance = pos - match_pos;
            if (distance > max_distance) break;

            // Quick check: compare last character of best match first
            if (best_length >= constants.min_match and best_length < max_length and
                data[match_pos + best_length] != data[pos + best_length])
            {
                match_pos = self.hash_chain[match_pos & constants.window_mask];
                continue;
            }

            // Count matching bytes
            var length: u32 = 0;
            while (length < max_length and
                data[match_pos + length] == data[pos + length])
            {
                length += 1;
            }

            if (length > best_length) {
                best_length = length;
                best_distance = distance;

                if (length >= max_length) break; // Can't do better
            }

            match_pos = self.hash_chain[match_pos & constants.window_mask];
        }

        if (best_length >= constants.min_match and best_distance > 0) {
            return Token{ .match = .{
                .length = @intCast(best_length),
                .distance = @intCast(best_distance),
            } };
        }

        return null;
    }

    /// Compress data into LZ77 tokens
    pub fn compress(self: *Self, data: []const u8) !std.ArrayList(Token) {
        var tokens = std.ArrayList(Token).init(self.allocator);
        errdefer tokens.deinit();

        if (data.len == 0) return tokens;

        var pos: u32 = 0;
        var prev_match: ?Token = null;
        const use_lazy = self.level.useLazyMatching();
        const lazy_threshold = self.level.getLazyMatchThreshold();

        while (pos < data.len) {
            const current_match = self.findMatch(data, pos, constants.min_match - 1);

            if (use_lazy and prev_match != null) {
                // Lazy matching: check if next position has better match
                const pm = prev_match.?.match;
                if (current_match) |cm| {
                    if (cm.match.length > pm.length + 1 or
                        (cm.match.length == pm.length and cm.match.distance < pm.distance))
                    {
                        // Current match is better, emit previous position as literal
                        try tokens.append(Token{ .literal = data[pos - 1] });
                        prev_match = current_match;
                        self.updateHash(data, pos);
                        pos += 1;
                        continue;
                    }
                }

                // Use previous match
                try tokens.append(prev_match.?);
                // Update hash for all positions in the match
                const match_end = pos - 1 + pm.length;
                for (pos..@min(match_end, @as(u32, @intCast(data.len)) -| 2)) |p| {
                    self.updateHash(data, @intCast(p));
                }
                pos = pos - 1 + pm.length;
                prev_match = null;
                continue;
            }

            if (current_match) |match| {
                if (use_lazy and match.match.length < lazy_threshold) {
                    // Store for lazy evaluation
                    prev_match = match;
                    self.updateHash(data, pos);
                    pos += 1;
                    continue;
                }

                // Emit match directly
                try tokens.append(match);
                const match_end = pos + match.match.length;
                for (pos..@min(match_end, @as(u32, @intCast(data.len)) -| 2)) |p| {
                    self.updateHash(data, @intCast(p));
                }
                pos += match.match.length;
            } else {
                // No match found, emit literal
                if (prev_match) |pm| {
                    try tokens.append(pm);
                    pos = pos - 1 + pm.match.length;
                    prev_match = null;
                } else {
                    try tokens.append(Token{ .literal = data[pos] });
                    self.updateHash(data, pos);
                    pos += 1;
                }
            }
        }

        // Handle any remaining pending match
        if (prev_match) |pm| {
            try tokens.append(pm);
        }

        return tokens;
    }

    /// Reset compressor state for new data
    pub fn reset(self: *Self) void {
        @memset(self.hash_table, nil_pos);
        @memset(self.hash_chain, nil_pos);
        self.window_pos = 0;
    }
};

/// Huffman tree builder for dynamic blocks
pub const HuffmanTreeBuilder = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) HuffmanTreeBuilder {
        return .{ .allocator = allocator };
    }

    /// Build Huffman codes from symbol frequencies
    pub fn buildCodes(
        self: *HuffmanTreeBuilder,
        frequencies: []const u32,
        max_code_length: u32,
    ) ![]HuffmanCode {
        const n = frequencies.len;
        const codes = try self.allocator.alloc(HuffmanCode, n);
        @memset(codes, HuffmanCode{});

        // Count non-zero frequencies
        var num_symbols: usize = 0;
        for (frequencies) |f| {
            if (f > 0) num_symbols += 1;
        }

        if (num_symbols == 0) {
            // For decoder compatibility (RFC 1951, zlib, libdeflate),
            // ensure at least two symbols have non-zero code lengths
            // even when no symbols are used. Many decoders reject
            // all-zero code lengths as invalid.
            if (n >= 2) {
                codes[0].length = 1;
                codes[0].code = 0;
                codes[1].length = 1;
                codes[1].code = 1;
            } else if (n == 1) {
                codes[0].length = 1;
                codes[0].code = 0;
            }
            return codes;
        }

        // Build code lengths using package-merge algorithm (simplified)
        const code_lengths = try self.computeCodeLengths(frequencies, max_code_length);
        defer self.allocator.free(code_lengths);

        // Generate canonical Huffman codes from lengths
        try self.generateCanonicalCodes(codes, code_lengths);

        return codes;
    }

    /// Compute code lengths using canonical Huffman construction
    /// This algorithm ensures the Kraft inequality is always satisfied.
    fn computeCodeLengths(
        self: *HuffmanTreeBuilder,
        frequencies: []const u32,
        max_length: u32,
    ) ![]u4 {
        const n = frequencies.len;
        const lengths = try self.allocator.alloc(u4, n);
        @memset(lengths, 0);

        // Create sorted list of symbols by frequency
        const symbols = try self.allocator.alloc(usize, n);
        defer self.allocator.free(symbols);
        for (0..n) |i| symbols[i] = i;

        // Sort by frequency (ascending for Huffman tree construction)
        std.mem.sort(usize, symbols, frequencies, struct {
            fn lessThan(freqs: []const u32, a: usize, b: usize) bool {
                if (freqs[a] != freqs[b]) return freqs[a] < freqs[b];
                return a < b;
            }
        }.lessThan);

        // Count symbols with non-zero frequency
        var num_symbols: usize = 0;
        for (symbols) |s| {
            if (frequencies[s] > 0) num_symbols += 1;
        }

        if (num_symbols == 0) return lengths;
        if (num_symbols == 1) {
            // Single symbol gets code length 1
            lengths[symbols[n - 1]] = 1;
            return lengths;
        }

        // Find the start of non-zero frequency symbols
        const start_idx = n - num_symbols;

        // Allocate arrays for tree construction
        // We need to track parent pointers to calculate depths
        const tree_size = 2 * num_symbols - 1;
        const parent = try self.allocator.alloc(usize, tree_size);
        defer self.allocator.free(parent);
        const depth = try self.allocator.alloc(u32, tree_size);
        defer self.allocator.free(depth);
        @memset(parent, 0);
        @memset(depth, 0);

        // Copy frequencies for the leaves (sorted ascending)
        const node_freq = try self.allocator.alloc(u64, tree_size);
        defer self.allocator.free(node_freq);
        for (0..num_symbols) |i| {
            node_freq[i] = frequencies[symbols[start_idx + i]];
        }

        // Build Huffman tree using two-queue algorithm
        // Queue 1: leaf nodes (already sorted by frequency)
        // Queue 2: internal nodes (added in order of increasing frequency)
        var leaf_idx: usize = 0;
        var internal_start: usize = num_symbols;
        var next_internal: usize = num_symbols;

        while (leaf_idx + (next_internal - num_symbols) < tree_size - 1) {
            // Select two nodes with smallest frequencies
            var node1: usize = undefined;
            var node2: usize = undefined;

            // Get first minimum
            const leaf_avail1 = leaf_idx < num_symbols;
            const internal_avail1 = internal_start < next_internal;

            if (leaf_avail1 and (!internal_avail1 or node_freq[leaf_idx] <= node_freq[internal_start])) {
                node1 = leaf_idx;
                leaf_idx += 1;
            } else {
                node1 = internal_start;
                internal_start += 1;
            }

            // Get second minimum
            const leaf_avail2 = leaf_idx < num_symbols;
            const internal_avail2 = internal_start < next_internal;

            if (leaf_avail2 and (!internal_avail2 or node_freq[leaf_idx] <= node_freq[internal_start])) {
                node2 = leaf_idx;
                leaf_idx += 1;
            } else {
                node2 = internal_start;
                internal_start += 1;
            }

            // Create new internal node
            node_freq[next_internal] = node_freq[node1] + node_freq[node2];
            parent[node1] = next_internal;
            parent[node2] = next_internal;
            next_internal += 1;
        }

        // Calculate depths by walking up to root
        const root = tree_size - 1;
        depth[root] = 0;

        // Process nodes from root down (internal nodes are at indices num_symbols..tree_size)
        var i: usize = tree_size - 1;
        while (i > 0) : (i -= 1) {
            if (parent[i - 1] != 0 or i - 1 < num_symbols) {
                depth[i - 1] = depth[parent[i - 1]] + 1;
            }
        }
        // Handle the case where node 0's parent might actually be 0 (shouldn't happen in valid tree)
        if (num_symbols > 0) {
            depth[0] = depth[parent[0]] + 1;
        }

        // Extract code lengths from leaf depths, applying max_length limit
        var needs_limiting = false;
        for (0..num_symbols) |j| {
            var len = depth[j];
            if (len > max_length) {
                len = max_length;
                needs_limiting = true;
            }
            lengths[symbols[start_idx + j]] = @intCast(len);
        }

        // If any code exceeded max_length, use length-limiting algorithm
        if (needs_limiting) {
            try self.limitCodeLengths(lengths, symbols[start_idx..], max_length);
        }

        return lengths;
    }

    /// Limit code lengths to max_length while maintaining Kraft inequality
    fn limitCodeLengths(
        self: *HuffmanTreeBuilder,
        lengths: []u4,
        symbols: []const usize,
        max_length: u32,
    ) !void {
        _ = self;

        // Calculate the overflow from codes that exceeded max_length
        // Using Kraft inequality: sum of 2^(max_length - len) must equal 2^max_length
        const capacity: u32 = @as(u32, 1) << @intCast(max_length);
        var used: u32 = 0;

        for (symbols) |s| {
            const len = lengths[s];
            if (len > 0) {
                used += @as(u32, 1) << @intCast(max_length - len);
            }
        }

        // If oversubscribed, we need to increase some code lengths
        while (used > capacity) {
            // Find a code that can be lengthened (not already at max_length)
            // Prefer lengthening shorter codes as they contribute more to overflow
            var best_idx: ?usize = null;
            var best_len: u4 = @intCast(max_length);

            for (symbols, 0..) |s, idx| {
                const len = lengths[s];
                if (len > 0 and len < max_length and len < best_len) {
                    best_len = len;
                    best_idx = idx;
                }
            }

            if (best_idx) |idx| {
                const s = symbols[idx];
                const old_len = lengths[s];
                lengths[s] = old_len + 1;
                // Recalculate: removing 2^(max-old) and adding 2^(max-new)
                const old_contribution = @as(u32, 1) << @intCast(max_length - old_len);
                const new_contribution = @as(u32, 1) << @intCast(max_length - old_len - 1);
                used = used - old_contribution + new_contribution;
            } else {
                // All codes are at max_length, tree is valid
                break;
            }
        }
    }

    /// Generate canonical Huffman codes from code lengths
    fn generateCanonicalCodes(self: *HuffmanTreeBuilder, codes: []HuffmanCode, lengths: []const u4) !void {
        _ = self;
        const n = codes.len;

        // Count codes of each length
        var bl_count: [16]u16 = .{0} ** 16;
        for (lengths) |len| {
            if (len > 0) bl_count[len] += 1;
        }

        // Calculate starting code for each length
        var next_code: [16]u16 = .{0} ** 16;
        var code: u16 = 0;
        for (1..16) |bits| {
            code = (code + bl_count[bits - 1]) << 1;
            next_code[bits] = code;
        }

        // Assign codes to symbols
        for (0..n) |i| {
            const len = lengths[i];
            if (len > 0) {
                const shift_amount: u4 = @intCast(16 - @as(u5, len));
                codes[i] = .{
                    .code = bitReverse(u16, next_code[len]) >> shift_amount,
                    .length = len,
                };
                next_code[len] += 1;
            }
        }
    }
};

/// Deflate encoder
pub const DeflateEncoder = struct {
    allocator: std.mem.Allocator,
    level: CompressionLevel,
    lz77: LZ77Compressor,
    tree_builder: HuffmanTreeBuilder,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, level: CompressionLevel) !Self {
        return .{
            .allocator = allocator,
            .level = level,
            .lz77 = try LZ77Compressor.init(allocator, level),
            .tree_builder = HuffmanTreeBuilder.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.lz77.deinit();
    }

    /// Compress data using Deflate algorithm
    pub fn compress(self: *Self, data: []const u8) ![]u8 {
        var writer = BitWriter.init(self.allocator);
        defer writer.deinit();

        if (data.len == 0) {
            // Empty data: single final block with end marker
            try self.writeEmptyBlock(&writer);
        } else if (self.level == .none) {
            // No compression: use stored blocks
            try self.writeStoredBlocks(&writer, data);
        } else {
            // Compress with LZ77 and Huffman coding
            try self.writeCompressedBlocks(&writer, data);
        }

        return writer.toOwnedSlice();
    }

    /// Write an empty final block
    fn writeEmptyBlock(self: *Self, writer: *BitWriter) !void {
        _ = self;
        // BFINAL=1, BTYPE=01 (fixed Huffman)
        try writer.writeBits(1, 1); // BFINAL
        try writer.writeBits(1, 2); // BTYPE = 01

        // Write end-of-block symbol (256) with fixed Huffman code
        try writer.writeCode(fixed_huffman.lit_len_codes[constants.end_of_block]);
    }

    /// Write stored (uncompressed) blocks
    fn writeStoredBlocks(self: *Self, writer: *BitWriter, data: []const u8) !void {
        _ = self;
        const max_block_size: usize = 65535;
        var offset: usize = 0;

        while (offset < data.len) {
            const remaining = data.len - offset;
            const block_size: u16 = @intCast(@min(remaining, max_block_size));
            const is_final = offset + block_size >= data.len;

            // Block header
            try writer.writeBits(@intFromBool(is_final), 1); // BFINAL
            try writer.writeBits(0, 2); // BTYPE = 00 (no compression)

            // Align to byte boundary
            try writer.alignToByte();

            // LEN and NLEN
            try writer.writeBits(block_size, 16);
            try writer.writeBits(~block_size, 16);

            // Raw data
            for (data[offset .. offset + block_size]) |byte| {
                try writer.buffer.append(byte);
            }

            offset += block_size;
        }
    }

    /// Write compressed blocks using fixed or dynamic Huffman codes
    fn writeCompressedBlocks(self: *Self, writer: *BitWriter, data: []const u8) !void {
        // LZ77 compression
        var tokens = try self.lz77.compress(data);
        defer tokens.deinit();

        // Calculate frequencies for dynamic Huffman
        var lit_len_freq: [constants.num_lit_len_codes]u32 = .{0} ** constants.num_lit_len_codes;
        var dist_freq: [constants.num_dist_codes]u32 = .{0} ** constants.num_dist_codes;

        for (tokens.items) |token| {
            switch (token) {
                .literal => |lit| {
                    lit_len_freq[lit] += 1;
                },
                .match => |m| {
                    const len_code = length_code_table[m.length];
                    lit_len_freq[len_code] += 1;
                    const dist_code = getDistanceCode(m.distance);
                    dist_freq[dist_code] += 1;
                },
            }
        }
        // End of block marker
        lit_len_freq[constants.end_of_block] += 1;

        // Choose between fixed and dynamic Huffman based on estimated size
        const use_dynamic = self.shouldUseDynamic(&lit_len_freq, &dist_freq);

        // Write block header
        try writer.writeBits(1, 1); // BFINAL = 1 (single block for now)

        if (use_dynamic) {
            try writer.writeBits(2, 2); // BTYPE = 10 (dynamic Huffman)
            try self.writeDynamicBlock(writer, tokens.items, &lit_len_freq, &dist_freq);
        } else {
            try writer.writeBits(1, 2); // BTYPE = 01 (fixed Huffman)
            try self.writeFixedBlock(writer, tokens.items);
        }
    }

    /// Determine if dynamic Huffman would be more efficient
    fn shouldUseDynamic(self: *Self, lit_len_freq: *const [constants.num_lit_len_codes]u32, dist_freq: *const [constants.num_dist_codes]u32) bool {
        _ = self;
        // Simple heuristic: use dynamic if there's significant frequency variation
        var max_lit: u32 = 0;
        var sum_lit: u32 = 0;
        for (lit_len_freq) |f| {
            max_lit = @max(max_lit, f);
            sum_lit += f;
        }

        var max_dist: u32 = 0;
        var sum_dist: u32 = 0;
        for (dist_freq) |f| {
            max_dist = @max(max_dist, f);
            sum_dist += f;
        }

        // If frequencies are highly skewed, dynamic might help
        if (sum_lit > 0 and max_lit * 4 > sum_lit) return true;
        if (sum_dist > 0 and max_dist * 4 > sum_dist) return true;

        // For small data, fixed is usually better (less overhead)
        if (sum_lit < 100) return false;

        return false;
    }

    /// Write a block using fixed Huffman codes
    fn writeFixedBlock(self: *Self, writer: *BitWriter, tokens: []const Token) !void {
        _ = self;
        for (tokens) |token| {
            switch (token) {
                .literal => |lit| {
                    try writer.writeCode(fixed_huffman.lit_len_codes[lit]);
                },
                .match => |m| {
                    // Length code
                    const len_code = length_code_table[m.length];
                    try writer.writeCode(fixed_huffman.lit_len_codes[len_code]);

                    // Length extra bits
                    const len_idx = len_code - 257;
                    const extra_bits = length_extra_bits[len_idx];
                    if (extra_bits > 0) {
                        const extra_value = m.length - length_base[len_idx];
                        try writer.writeBits(extra_value, extra_bits);
                    }

                    // Distance code
                    const dist_code = getDistanceCode(m.distance);
                    try writer.writeCode(fixed_huffman.dist_codes[dist_code]);

                    // Distance extra bits
                    const dist_extra = distance_extra_bits[dist_code];
                    if (dist_extra > 0) {
                        const dist_value = m.distance - distance_base[dist_code];
                        try writer.writeBits(dist_value, dist_extra);
                    }
                },
            }
        }

        // End of block
        try writer.writeCode(fixed_huffman.lit_len_codes[constants.end_of_block]);
    }

    /// Write a block using dynamic Huffman codes
    fn writeDynamicBlock(
        self: *Self,
        writer: *BitWriter,
        tokens: []const Token,
        lit_len_freq: *const [constants.num_lit_len_codes]u32,
        dist_freq: *const [constants.num_dist_codes]u32,
    ) !void {
        // Build Huffman codes
        const lit_len_codes = try self.tree_builder.buildCodes(lit_len_freq, constants.max_code_length);
        defer self.allocator.free(lit_len_codes);

        const dist_codes = try self.tree_builder.buildCodes(dist_freq, constants.max_code_length);
        defer self.allocator.free(dist_codes);

        // Determine HLIT and HDIST
        var hlit: u32 = constants.num_lit_len_codes;
        while (hlit > 257 and lit_len_codes[hlit - 1].length == 0) {
            hlit -= 1;
        }

        var hdist: u32 = constants.num_dist_codes;
        while (hdist > 1 and dist_codes[hdist - 1].length == 0) {
            hdist -= 1;
        }

        // Encode code lengths
        const code_length_order = [_]u8{ 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 };

        // Collect all code lengths
        const total_codes = hlit + hdist;
        const all_lengths = try self.allocator.alloc(u4, total_codes);
        defer self.allocator.free(all_lengths);

        for (0..hlit) |i| all_lengths[i] = lit_len_codes[i].length;
        for (0..hdist) |i| all_lengths[hlit + i] = dist_codes[i].length;

        // Run-length encode the lengths
        const encoded = try self.runLengthEncode(all_lengths);
        defer self.allocator.free(encoded.symbols);
        defer self.allocator.free(encoded.extra);

        // Build code length Huffman codes
        var cl_freq: [19]u32 = .{0} ** 19;
        for (encoded.symbols) |sym| cl_freq[sym] += 1;

        const cl_codes = try self.tree_builder.buildCodes(&cl_freq, constants.max_cl_code_length);
        defer self.allocator.free(cl_codes);

        // Determine HCLEN
        var hclen: u32 = 19;
        while (hclen > 4 and cl_codes[code_length_order[hclen - 1]].length == 0) {
            hclen -= 1;
        }

        // Write header
        try writer.writeBits(hlit - 257, 5); // HLIT
        try writer.writeBits(hdist - 1, 5); // HDIST
        try writer.writeBits(hclen - 4, 4); // HCLEN

        // Write code length code lengths
        for (0..hclen) |i| {
            try writer.writeBits(cl_codes[code_length_order[i]].length, 3);
        }

        // Write encoded lengths
        for (encoded.symbols, 0..) |sym, i| {
            try writer.writeCode(cl_codes[sym]);
            // Write extra bits if needed
            const extra = encoded.extra[i];
            if (sym == 16) {
                try writer.writeBits(extra, 2); // 3-6 repetitions
            } else if (sym == 17) {
                try writer.writeBits(extra, 3); // 3-10 zeros
            } else if (sym == 18) {
                try writer.writeBits(extra, 7); // 11-138 zeros
            }
        }

        // Write compressed data
        for (tokens) |token| {
            switch (token) {
                .literal => |lit| {
                    try writer.writeCode(lit_len_codes[lit]);
                },
                .match => |m| {
                    const len_code = length_code_table[m.length];
                    try writer.writeCode(lit_len_codes[len_code]);

                    const len_idx = len_code - 257;
                    const extra_bits = length_extra_bits[len_idx];
                    if (extra_bits > 0) {
                        const extra_value = m.length - length_base[len_idx];
                        try writer.writeBits(extra_value, extra_bits);
                    }

                    const dist_code = getDistanceCode(m.distance);
                    try writer.writeCode(dist_codes[dist_code]);

                    const dist_extra = distance_extra_bits[dist_code];
                    if (dist_extra > 0) {
                        const dist_value = m.distance - distance_base[dist_code];
                        try writer.writeBits(dist_value, dist_extra);
                    }
                },
            }
        }

        // End of block
        try writer.writeCode(lit_len_codes[constants.end_of_block]);
    }

    /// Run-length encoding result
    const RLEResult = struct {
        symbols: []u8,
        extra: []u8,
    };

    /// Run-length encode code lengths
    fn runLengthEncode(self: *Self, lengths: []const u4) !RLEResult {
        var symbols = std.ArrayList(u8).init(self.allocator);
        var extra = std.ArrayList(u8).init(self.allocator);
        errdefer symbols.deinit();
        errdefer extra.deinit();

        var i: usize = 0;
        while (i < lengths.len) {
            const len = lengths[i];

            if (len == 0) {
                // Count consecutive zeros
                var count: usize = 1;
                while (i + count < lengths.len and lengths[i + count] == 0) {
                    count += 1;
                }
                const initial_count = count;

                while (count > 0) {
                    if (count >= 11) {
                        // Use code 18: 11-138 zeros
                        const n = @min(count, 138);
                        try symbols.append(18);
                        try extra.append(@intCast(n - 11));
                        count -= n;
                    } else if (count >= 3) {
                        // Use code 17: 3-10 zeros
                        const n = @min(count, 10);
                        try symbols.append(17);
                        try extra.append(@intCast(n - 3));
                        count -= n;
                    } else {
                        // Emit literal zeros
                        try symbols.append(0);
                        try extra.append(0);
                        count -= 1;
                    }
                }
                i += initial_count;
            } else {
                // Emit the length value
                try symbols.append(len);
                try extra.append(0);
                i += 1;

                // Check for repetitions
                var count: usize = 0;
                while (i + count < lengths.len and lengths[i + count] == len) {
                    count += 1;
                }

                while (count >= 3) {
                    // Use code 16: repeat 3-6 times
                    const n = @min(count, 6);
                    try symbols.append(16);
                    try extra.append(@intCast(n - 3));
                    count -= n;
                    i += n;
                }

                // Emit remaining as literals
                while (count > 0) {
                    try symbols.append(len);
                    try extra.append(0);
                    count -= 1;
                    i += 1;
                }
            }
        }

        return .{
            .symbols = try symbols.toOwnedSlice(),
            .extra = try extra.toOwnedSlice(),
        };
    }
};

// =============================================================================
// Public API
// =============================================================================

/// Compress data using Deflate algorithm
///
/// Parameters:
///   - allocator: Memory allocator for output buffer
///   - data: Input data to compress
///   - level: Compression level (1-9, or 0 for no compression)
///
/// Returns:
///   - Compressed deflate stream (caller owns memory)
///
/// Errors:
///   - error.OutOfMemory: Memory allocation failed
pub fn compress(
    allocator: std.mem.Allocator,
    data: []const u8,
    level: CompressionLevel,
) ![]u8 {
    var encoder = try DeflateEncoder.init(allocator, level);
    defer encoder.deinit();
    return encoder.compress(data);
}

/// Compress data with default compression level (6)
pub fn compressDefault(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    return compress(allocator, data, .default);
}

// =============================================================================
// Tests
// =============================================================================

test "compress empty data" {
    const allocator = std.testing.allocator;

    const compressed = try compress(allocator, "", .default);
    defer allocator.free(compressed);

    // Should produce a valid deflate stream (at minimum: block header + end marker)
    try std.testing.expect(compressed.len > 0);
}

test "compress simple data with fixed Huffman" {
    const allocator = std.testing.allocator;

    const data = "Hello, World!";
    const compressed = try compress(allocator, data, .default);
    defer allocator.free(compressed);

    // Compressed data should exist
    try std.testing.expect(compressed.len > 0);
}

test "compress repetitive data" {
    const allocator = std.testing.allocator;

    // Highly compressible data
    const data = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
    const compressed = try compress(allocator, data, .default);
    defer allocator.free(compressed);

    // Should compress significantly
    try std.testing.expect(compressed.len < data.len);
}

test "compress with different levels" {
    const allocator = std.testing.allocator;
    const data = "The quick brown fox jumps over the lazy dog. " ** 10;

    // Test all compression levels
    const levels = [_]CompressionLevel{ .none, .fastest, .default, .best };

    for (levels) |level| {
        const compressed = try compress(allocator, data, level);
        defer allocator.free(compressed);
        try std.testing.expect(compressed.len > 0);
    }
}

test "LZ77Compressor: find matches" {
    const allocator = std.testing.allocator;

    var lz77 = try LZ77Compressor.init(allocator, .default);
    defer lz77.deinit();

    // Data with repetition
    const data = "abcabcabc";
    var tokens = try lz77.compress(data);
    defer tokens.deinit();

    // Should find matches
    var has_match = false;
    for (tokens.items) |token| {
        if (token == .match) has_match = true;
    }
    try std.testing.expect(has_match);
}

test "BitWriter: write bits" {
    const allocator = std.testing.allocator;

    var writer = BitWriter.init(allocator);
    defer writer.deinit();

    try writer.writeBits(0b101, 3);
    try writer.writeBits(0b11, 2);
    try writer.flush();

    // 0b101 followed by 0b11 = 0b11_101 = 0x1D (LSB first)
    try std.testing.expectEqual(@as(u8, 0b00011101), writer.getData()[0]);
}

test "length and distance code tables" {
    // Test length codes
    try std.testing.expectEqual(@as(u16, 257), length_code_table[3]);
    try std.testing.expectEqual(@as(u16, 258), length_code_table[4]);
    try std.testing.expectEqual(@as(u16, 285), length_code_table[258]);

    // Test distance codes
    try std.testing.expectEqual(@as(u5, 0), getDistanceCode(1));
    try std.testing.expectEqual(@as(u5, 1), getDistanceCode(2));
    try std.testing.expectEqual(@as(u5, 4), getDistanceCode(5));
}

test "HuffmanTreeBuilder: build codes" {
    const allocator = std.testing.allocator;

    var builder = HuffmanTreeBuilder.init(allocator);

    // Simple frequency distribution
    var freqs = [_]u32{ 10, 5, 3, 1, 0, 0, 0, 0 };

    const codes = try builder.buildCodes(&freqs, 15);
    defer allocator.free(codes);

    // Most frequent symbol should have shortest code
    try std.testing.expect(codes[0].length <= codes[1].length);
    try std.testing.expect(codes[1].length <= codes[2].length);
}

test "stored block (no compression) format" {
    const allocator = std.testing.allocator;

    const data = "Test data for stored block";
    const compressed = try compress(allocator, data, .none);
    defer allocator.free(compressed);

    // For stored blocks, size should be slightly larger than input
    // (due to block headers)
    try std.testing.expect(compressed.len >= data.len);
}

test "distance code lookup consistency" {
    // Verify that distance_code_small table matches getDistanceCode for all values
    for (1..257) |d| {
        const from_table = distance_code_small[d];
        const from_func = getDistanceCode(@intCast(d));
        try std.testing.expectEqual(from_table, from_func);
    }
}

test "length code lookup consistency" {
    // Test key length values from RFC 1951
    try std.testing.expectEqual(@as(u16, 257), length_code_table[3]); // Min length
    try std.testing.expectEqual(@as(u16, 264), length_code_table[10]); // Length 10
    try std.testing.expectEqual(@as(u16, 269), length_code_table[19]); // Length 19
    try std.testing.expectEqual(@as(u16, 285), length_code_table[258]); // Max length
}
