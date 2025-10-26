# Dependency Policy

**Last Updated**: 2025-10-26

---

## Guiding Principles

1. **Minimize dependencies**: Dependencies are added only when absolutely necessary
2. **Progressive reduction**: Migrate from C dependencies to pure Zig implementations
3. **Clear separation**: All C dependencies isolated in `src/c_compat/`
4. **License compatibility**: Only MIT/BSD/Apache 2.0/Public Domain licenses
5. **Active maintenance**: Avoid abandoned libraries

---

## Dependency Tiers

### Tier 1: Required (Always Allowed)

**Zig Standard Library**
- Built into Zig compiler
- No additional installation required
- Usage: All modules

### Tier 2: Temporary (Phase-Limited)

**zlib** (Phase 1-2 only)
- **Version**: 1.3.1+
- **License**: zlib License (MIT-compatible)
- **Purpose**: Deflate/Gzip compression
- **Duration**: Phase 1-2, migrating to pure Zig in Phase 3
- **Rationale**: See [ADR-004](adr/ADR-004-zlib-integration.md)

**LZMA SDK** (Phase 3-4 only)
- **Version**: 23.01+
- **License**: Public Domain
- **Purpose**: LZMA/LZMA2 compression
- **Duration**: Phase 3-4, migrating to pure Zig in Phase 5+
- **Status**: Planned

### Tier 3: Prohibited

- GPL/AGPL/LGPL licensed libraries (license incompatibility)
- Unmaintained libraries (security risk)
- Proprietary libraries (e.g., unrar)
- Large dependencies (e.g., Boost) - conflicts with lightweight philosophy

---

## Migration Strategy

### 3-Stage Approach

```
Stage 1: C Integration (Phase 1-2)
  ↓
  Fast time-to-market
  Proven, battle-tested code
  Isolated in src/c_compat/

Stage 2: Zig Wrapper (Phase 3-4)
  ↓
  Improved error handling
  Memory safety enhancements
  Still uses C underneath

Stage 3: Pure Zig (Phase 5+)
  ↓
  No C dependencies
  Full memory safety
  Easy cross-compilation
```

### Current Status

| Component | Phase 1-2 | Phase 3 | Phase 4+ |
|-----------|-----------|---------|----------|
| **Deflate** | C (zlib) | Pure Zig | Pure Zig |
| **LZMA** | - | C (SDK) | Pure Zig |
| **Bzip2** | - | C (libbzip2) | Pure Zig |

---

## Adding New Dependencies

### Decision Checklist

Before adding a C dependency:

```
[ ] Implementation would take 2+ weeks in pure Zig
[ ] No existing quality Zig implementation available
[ ] Algorithm is complex/requires standardization
[ ] License is MIT/BSD/Apache 2.0/Public Domain
[ ] Library is actively maintained (commit within 1 year)
[ ] Security vulnerabilities are addressed promptly
[ ] Widely used (1000+ GitHub stars or equivalent)
[ ] Migration path to pure Zig documented
```

### Required Documentation

1. **Create ADR** (Architecture Decision Record)
   - Location: `docs/adr/ADR-XXX-<name>.md`
   - Template: See [ADR-004](adr/ADR-004-zlib-integration.md)

2. **Implement in `src/c_compat/`**
   - Zig wrapper with memory-safe API
   - Comprehensive tests
   - Migration plan documented

3. **Update this policy**
   - Add to dependency list
   - Document migration timeline

---

## License Management

### Allowed Licenses

| License | Status | Notes |
|---------|--------|-------|
| **Public Domain** | ✅ Fully compatible | LZMA SDK |
| **MIT** | ✅ Fully compatible | |
| **BSD (2/3-clause)** | ✅ Fully compatible | |
| **Apache 2.0** | ✅ Fully compatible | |
| **zlib License** | ✅ Compatible | zlib |

### License Attribution

All dependencies documented in:
- `NOTICE.txt` (root directory)
- Module-level comments in `src/c_compat/`
- Related ADRs

---

## C Compat Layer

### Architecture

```
src/c_compat/
├── README.md          # Documentation for C compat layer
├── zlib.zig           # zlib wrapper (Phase 1-2)
└── lzma_sdk.zig       # LZMA SDK wrapper (Phase 3-4, planned)
```

### Requirements

Each wrapper module must:
- Provide Zig-friendly error handling
- Use Zig allocators (not C malloc/free directly)
- Include comprehensive tests
- Document the C library it wraps
- Reference the related ADR
- Define clear migration path

---

## Build System Integration

Dependencies are managed via Zig's package manager:

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

Cross-compilation handled automatically by Zig build system.

---

## Migration Tracking

Track progress toward zero C dependencies:

```markdown
## Dependency Reduction Progress

- [x] Phase 1: zlib integration (compression)
- [x] Phase 1: Zig stdlib (decompression)
- [ ] Phase 3: Pure Zig Deflate encoder
- [ ] Phase 3: LZMA SDK integration
- [ ] Phase 5: Pure Zig LZMA implementation
- [ ] Phase 5: Zero C dependencies 🎯
```

Target: **Phase 5 - Complete Zig implementation, zero C dependencies**

---

## Questions?

See also:
- [ADR Index](adr/) - Architecture Decision Records
- [DESIGN_PHILOSOPHY.md](../plan/DESIGN_PHILOSOPHY.md) - Project design principles
- `src/c_compat/README.md` - C compatibility layer documentation
