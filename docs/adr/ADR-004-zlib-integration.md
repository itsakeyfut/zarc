# ADR-004: zlib Integration

**Date**: 2025-10-26
**Status**: Accepted
**Phase**: Phase 1 - Basic Compression Support (v0.2.0)

---

## Context

The zarc project requires Deflate compression and decompression capabilities to support:
- Gzip format (RFC 1952)
- Zlib format (RFC 1950)
- Tar.gz archives (most common archive format)

Deflate is a complex compression algorithm (RFC 1951) that requires significant implementation effort. We need to decide between:
1. Integrating a mature C library (zlib)
2. Using an existing Zig implementation
3. Writing our own pure Zig implementation from scratch

## Decision

**We will integrate zlib as a temporary C dependency for Phase 1-2, with a clear migration path to pure Zig implementation in Phase 3+.**

The integration will follow this architecture:
```
src/c_compat/zlib.zig       ← C wrapper (compression only)
src/compress/zlib.zig       ← High-level API (uses Zig std for decompression)
src/c/zlib_compress.c       ← C implementation wrapper
```

## Rationale

### Why zlib?

**Advantages:**
1. **Battle-tested**: zlib has been in production for 30+ years with billions of deployments
2. **Performance**: Highly optimized implementation, meets our 90% GNU tar performance target
3. **Compatibility**: De facto standard, ensures interoperability with existing tools
4. **License**: zlib License is MIT-compatible (permissive)
5. **Time-to-market**: Enables Phase 1 release within planned timeline

**Disadvantages:**
1. **C dependency**: Complicates build system and cross-compilation
2. **Memory safety**: C code lacks Zig's safety guarantees
3. **Binary size**: Adds external dependency to final binary
4. **Technical debt**: Must be migrated to pure Zig eventually

### Why not alternatives?

#### Option 2: Existing Zig Deflate implementation
- **Pro**: No C dependency, memory safe
- **Con**: As of 2025-10-26, Zig's standard library flate implementation is read-only (decompression only)
- **Con**: Limited production testing compared to zlib

#### Option 3: Pure Zig from scratch
- **Pro**: Full control, no dependencies, Zig-idiomatic
- **Con**: Estimated 4-6 weeks of development + testing time
- **Con**: Delays Phase 1 release significantly
- **Con**: Risk of bugs in complex compression algorithm

### Hybrid Approach

We adopt a **hybrid strategy**:
- **Compression**: Use zlib (C implementation) via `src/c_compat/zlib.zig`
- **Decompression**: Use Zig standard library's `std.compress.flate`

This gives us:
- Fast compression with proven code
- Memory-safe decompression in pure Zig
- Foundation for full Zig migration later

## Implementation Details

### Architecture

```
┌─────────────────────────────────────┐
│  User Code (src/cli/commands.zig)  │
└──────────────┬──────────────────────┘
               │
               ↓
┌─────────────────────────────────────┐
│  High-level API                     │
│  (src/compress/zlib.zig)            │
│  - compress() → c_compat            │
│  - decompress() → std.compress      │
└─────────┬───────────────┬───────────┘
          │               │
          ↓               ↓
┌──────────────────┐  ┌────────────────┐
│  C Compat Layer  │  │  Zig Stdlib    │
│  (c_compat/      │  │  std.compress  │
│   zlib.zig)      │  │  .flate        │
└────────┬─────────┘  └────────────────┘
         │
         ↓
┌──────────────────┐
│  C Wrapper       │
│  (src/c/         │
│   zlib_compress) │
└────────┬─────────┘
         │
         ↓
┌──────────────────┐
│  zlib library    │
│  (via Zig pkg)   │
└──────────────────┘
```

### Build System Integration

Using Zig's package manager for zlib dependency:

```zig
// build.zig.zon
.{
    .dependencies = .{
        .zlib = .{
            .url = "...",
            .hash = "...",
        },
    },
}
```

```zig
// build.zig
const zlib_dep = b.dependency("zlib", .{
    .target = target,
    .optimize = optimize,
});

exe.linkLibC();
exe.linkLibrary(zlib_dep.artifact("z"));
exe.addCSourceFile(.{ .file = b.path("src/c/zlib_compress.c") });
```

### API Design

#### Compression (C-backed)
```zig
const c_zlib = @import("c_compat/zlib.zig");

pub fn compress(
    allocator: std.mem.Allocator,
    format: Format,
    data: []const u8,
) ![]u8 {
    return c_zlib.compress(allocator, format, data);
}
```

#### Decompression (Pure Zig)
```zig
pub fn decompress(
    allocator: std.mem.Allocator,
    format: Format,
    compressed_data: []const u8,
) ![]u8 {
    // Uses std.compress.flate
    const flate = std.compress.flate;
    // ... pure Zig implementation
}
```

## Migration Path

### Timeline

| Phase | Timeframe | Status | Implementation |
|-------|-----------|--------|----------------|
| **Phase 1-2** | 2025 Q4 - 2026 Q1 | Current | C integration (this ADR) |
| **Phase 3** | 2026 Q2-Q3 | Planned | Pure Zig implementation |
| **Phase 4+** | 2026 Q4+ | Future | Remove C dependency |

### Phase 3 Migration Strategy

When Zig's ecosystem matures or we have resources:

1. **Implement pure Zig Deflate compression**
   - Create `src/compress/deflate/encode.zig`
   - Implement Deflate algorithm in pure Zig
   - Achieve parity with zlib performance (90%+)

2. **Switch implementation**
   ```zig
   // Old (Phase 1-2)
   const c_zlib = @import("../c_compat/zlib.zig");
   return c_zlib.compress(allocator, format, data);

   // New (Phase 3+)
   const deflate = @import("deflate/encode.zig");
   return deflate.compress(allocator, format, data);
   ```

3. **Remove C dependency**
   - Delete `src/c_compat/zlib.zig`
   - Delete `src/c/zlib_compress.c`
   - Remove zlib from `build.zig`

4. **Maintain compatibility**
   - Public API (`src/compress/zlib.zig`) remains unchanged
   - Only internal implementation changes
   - Semantic versioning: minor version bump (v0.3.0 → v0.4.0)

### Monitoring Migration Readiness

Track these metrics to decide when to migrate:

```markdown
## Deflate Pure Zig Readiness

- [ ] Performance: ≥90% of zlib compression speed
- [ ] Compatibility: Passes all interop tests with GNU tar, 7-Zip
- [ ] Stability: 6+ months in production without compression bugs
- [ ] Test coverage: ≥95% for Deflate encoder
- [ ] Community adoption: 100+ projects using Zig Deflate
```

## Consequences

### Positive

1. **Fast delivery**: Phase 1 can ship on schedule
2. **Proven reliability**: zlib's 30-year track record reduces risk
3. **Performance guarantee**: Meets our 90% GNU tar benchmark target
4. **Clear isolation**: C code confined to `src/c_compat/`, easy to replace
5. **Hybrid safety**: Decompression uses memory-safe Zig stdlib

### Negative

1. **Build complexity**: Cross-compilation requires zlib for each target
2. **Technical debt**: Must track C dependency until Phase 3 migration
3. **Binary size**: ~100KB added for zlib (though may be smaller with tree-shaking)
4. **Memory safety gap**: Compression path lacks Zig's safety features

### Neutral

1. **Dual implementation**: Compression (C) + Decompression (Zig) requires dual testing
2. **Documentation burden**: Must explain hybrid approach to contributors
3. **Performance baseline**: zlib sets the bar we must match in Phase 3

## Acceptance Criteria

- [x] zlib linked correctly on all platforms (Linux, macOS, Windows)
- [x] `src/c_compat/zlib.zig` provides clean Zig API
- [x] Tests verify compression functionality
- [x] ADR documents integration decision (this document)
- [x] Migration path clearly defined

## Testing Strategy

### Unit Tests
```zig
test "compress gzip format" {
    const compressed = try compress(allocator, .gzip, "Hello World");
    defer allocator.free(compressed);

    // Verify gzip magic number
    try std.testing.expectEqual(@as(u8, 0x1f), compressed[0]);
    try std.testing.expectEqual(@as(u8, 0x8b), compressed[1]);
}
```

### Integration Tests
- Compress with zarc, decompress with GNU tar → verify contents
- Compress with zlib, decompress with Zig stdlib → verify round-trip
- Test on all platforms (Linux, macOS, Windows ARM64/x64)

### Compatibility Tests
- Create tar.gz with zarc → extract with GNU tar
- Create tar.gz with GNU tar → extract with zarc
- Verify identical output

## References

### External
- [zlib Official Site](https://zlib.net/)
- [RFC 1950 - ZLIB Compressed Data Format](https://www.rfc-editor.org/rfc/rfc1950.html)
- [RFC 1951 - DEFLATE Compressed Data Format](https://www.rfc-editor.org/rfc/rfc1951.html)
- [RFC 1952 - GZIP File Format](https://www.rfc-editor.org/rfc/rfc1952.html)
- [Zig std.compress.flate](https://ziglang.org/documentation/master/std/#std.compress.flate)

### Internal
- [DEPENDENCY_POLICY.md](../implementation/DEPENDENCY_POLICY.md)
- [DESIGN_PHILOSOPHY.md](../DESIGN_PHILOSOPHY.md)
- [Issue #36: zlib Integration](https://github.com/itsakeyfut/zarc/issues/36)
- [Issue #35: Deflate Decompression Implementation](https://github.com/itsakeyfut/zarc/issues/35)

### License
- **zlib License**: [zlib.net/zlib_license.html](https://zlib.net/zlib_license.html)
- MIT-compatible, permissive license

---

**Decision Makers**: @itsakeyfut
**Last Reviewed**: 2025-10-26
**Next Review**: Phase 3 kickoff (2026 Q2)
