# C Compatibility Layer

This directory contains Zig wrappers around C library dependencies used temporarily during early development phases.

## Purpose

The `c_compat/` layer provides:
1. **Clean separation** of C dependencies from pure Zig code
2. **Zig-friendly APIs** around C libraries (error handling, memory management)
3. **Clear migration path** to pure Zig implementations

## Design Principles

### Isolation
All C library integrations are confined to this directory. The rest of the codebase should not directly call C functions.

### Safety
Wrappers must:
- Handle C errors and convert them to Zig errors
- Use Zig allocators (not C malloc/free directly)
- Provide memory safety guarantees where possible

### Documentation
Each wrapper module must document:
- Which C library it wraps
- Why the C library is used (rationale)
- Migration plan to pure Zig
- Related ADR (Architecture Decision Record)

## Current Modules

### `zlib.zig`
- **C Library**: zlib 1.3.1+
- **Purpose**: Deflate/Gzip compression
- **Rationale**: See [ADR-004](../../docs/adr/ADR-004-zlib-integration.md)
- **Migration Target**: Phase 3 (Pure Zig Deflate encoder)

## Planned Modules

Future C integrations will follow the same pattern:

### `lzma_sdk.zig` (Phase 3)
- **C Library**: LZMA SDK (Public Domain)
- **Purpose**: LZMA/LZMA2 compression
- **Migration Target**: Phase 5+

## Usage Guidelines

### For Contributors

**DO:**
- Use wrappers from this directory (e.g., `@import("../c_compat/zlib.zig")`)
- Keep C-specific code confined here
- Write comprehensive tests for wrappers
- Document migration plans in ADRs

**DON'T:**
- Call C libraries directly from other modules
- Add new C dependencies without ADR approval
- Mix Zig and C memory management

### Adding New C Dependencies

Before adding a new module:

1. **Check if necessary**: Can this be implemented in pure Zig within reasonable time?
2. **Create ADR**: Document the decision in `docs/adr/ADR-XXX-*.md`
3. **Implement wrapper**: Follow existing patterns in this directory
4. **Write tests**: Ensure wrapper provides safety guarantees
5. **Document migration**: Define clear path to pure Zig

## Migration Strategy

Each C dependency follows a 3-stage migration:

```
Stage 1: C Integration (Phase 1-2)
  ↓
  Wrapper in c_compat/
  Battle-tested implementation
  Fast time-to-market

Stage 2: Zig Wrapper (Phase 3-4)
  ↓
  Enhanced error handling
  Memory safety improvements
  Still uses C underneath

Stage 3: Pure Zig (Phase 5+)
  ↓
  No C dependencies
  Full memory safety
  Easy cross-compilation
```

## Architecture Example

```
User Code
    ↓
High-Level API (src/compress/zlib.zig)
    ↓
C Compat Wrapper (src/c_compat/zlib.zig)
    ↓
C Code (src/c/zlib_compress.c)
    ↓
External C Library (zlib)
```

## License Compliance

All C libraries integrated must have permissive licenses compatible with Apache-2.0:
- ✅ MIT, BSD, Apache 2.0, Public Domain
- ❌ GPL, LGPL, proprietary

License information is documented in:
- `NOTICE.txt` (root directory)
- Module-level comments
- Related ADRs

## Questions?

See:
- [DESIGN_PHILOSOPHY.md](../../docs/DESIGN_PHILOSOPHY.md)
- [ADR Index](../../docs/adr/)