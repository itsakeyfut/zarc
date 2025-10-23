# Design Philosophy

**Last Updated**: 2025-10-18

---

## Project Vision

**zarc (Zig Archive)** is a reliable archive tool that provides unified behavior across cross-platform environments.

### Problems We Solve

- **Platform-specific behavior differences**: GNU tar vs BSD tar, Windows vs UNIX
- **Complex dependencies**: Multiple library dependencies like libarchive, zlib, liblzma
- **Compatibility issues**: Inconsistent handling of metadata (permissions, timestamps)
- **Security risks**: Inadequate protection against Zip Bombs and path traversal attacks

### What zarc Aims For

**"Same command, same result, on any platform"**

---

## Core Principles

### 1. Cross-platform First

All features are designed with cross-platform compatibility from the start.

**Implementation Guidelines**:
- Use platform-independent `std.fs.path` for file paths
- Store timestamps in UTC (Coordinated Universal Time)
- Use POSIX permissions as the base format, store Windows attributes in extended fields
- Run all feature tests on the big three OSes (Windows/Linux/macOS)

```zig
// ✅ Good: Platform-independent
const path = try std.fs.path.join(allocator, &[_][]const u8{"folder", "file.txt"});

// ❌ Bad: Platform-dependent
const path = "folder/file.txt";
```

### 2. Keep It Simple

Complexity breeds bugs. Before adding features, consider if existing code can achieve it.

**Guidelines**:
- External library dependencies are a last resort
- Function signatures should be self-explanatory
- Focus on the 20% of features used by 80% of users
- Prioritize working minimum functionality (MVP) over perfect complete features

```zig
// ✅ Good: Clear
pub fn extractArchive(
    archive_path: []const u8,
    destination: []const u8,
    options: ExtractOptions,
) !void

// ❌ Bad: Ambiguous
pub fn process(path: []const u8, mode: u32) !void
```

**Code Readability**:
- Keep functions under 50 lines (except complex algorithms)
- Comments explain "why" (the code explains "what")
- Replace magic numbers with constants

### 3. Maintain Compatibility

Aim for 100% compatibility with existing tools (GNU tar, Info-ZIP, 7-Zip).

**Compatibility Definition**:
- **Command-line compatibility**: Existing scripts work without modification
- **Format compatibility**: Mutual compression and extraction
- **Metadata preservation**: Complete preservation of permissions and timestamps

**Backward Compatibility**:
- Strict adherence to Semantic Versioning (SemVer)
- 6-month grace period for deprecations
- Breaking changes only in major version updates

### 4. Security by Default

Safe operation by default. Dangerous operations require explicit flags.

**Security Mechanisms**:

```zig
// Path traversal attack prevention
pub fn sanitizePath(path: []const u8) ![]const u8 {
    if (std.fs.path.isAbsolute(path)) return error.AbsolutePathNotAllowed;
    // Normalize and check paths containing ".."
}

// Zip Bomb detection
pub fn checkZipBomb(compressed: u64, uncompressed: u64) !void {
    const ratio = @intToFloat(f64, uncompressed) / @intToFloat(f64, compressed);
    if (ratio > 1000.0) return error.SuspiciousCompressionRatio;
}
```

**Symbolic Link Handling**:
- Default: Deny
- `--allow-relative-symlinks`: Allow relative links only
- `--allow-symlink-escape`: Allow all (dangerous)

### 5. Predictability

Behave as users expect. Principle of least astonishment.

**Error Message Structure**:
1. **What** failed
2. **Why** it failed
3. **How** to resolve it

```
Error: Cannot open archive file 'archive.zip'
Reason: Permission denied (EACCES)
Suggestion: Check file permissions with 'ls -l archive.zip'
```

---

## Decision-Making Criteria

### New Feature Decision Flow

```
New Feature Proposal
  ↓
[Q1] Is it useful for 80%+ of users?
  No → Reject or make it a plugin
  Yes ↓
[Q2] Can it be achieved with existing features?
  Yes → Document usage examples
  No ↓
[Q3] Does it significantly increase code complexity?
  Yes → Consider separate module
  No ↓
[Q4] Does it break existing behavior?
  Yes → Add as new subcommand
  No ↓
[Q5] Is it maintainable long-term?
  No → Reject
  Yes ↓
Approve!
```

### Performance vs Readability

1. **Start with readability-focused** implementation
2. **Profile** to identify bottlenecks
3. Consider optimization only if bottleneck consumes **10%+ of total time**
4. Implement only if optimization provides **10%+ performance improvement**

```zig
// Always document optimizations with comments
// OPTIMIZATION NOTE (2025-10-18):
// Bottleneck: 35% of extraction time (measured with perf)
// Improvement: memcpy instead of byte-by-byte: 45% faster
// Tradeoff: Slightly more complex error handling
```

### Zig Implementation vs C Integration

**Decision Flow**:
1. Is there a mature C implementation? → Yes: Start with C integration
2. Is it memory-safe? → No: Reimplement in Zig
3. Is it cross-platform? → No: Reimplement in Zig

**Gradual Zig Migration**:
1. Wrap C implementation in `src/c_compat/`
2. Reimplement decoder in Zig
3. Reimplement encoder in Zig
4. Remove C implementation completely

---

## Non-Goals (Intentionally Out of Scope)

### Out of Scope

**1. GUI Provision**
- Reason: Focus on CLI, high maintenance cost
- Alternative: Provide C API (`libzarc`)

**2. Cloud Storage Integration**
- Reason: Limit responsibilities, burden of API changes
- Alternative: Integration via stdin/stdout

**3. Encryption (Initial Phase)**
- Reason: Prioritize basic features
- Future: Consider 7-Zip compatible encryption in Phase 3+

**4. All Format Support**
- In scope: tar, gzip, zip, 7z, bzip2, xz
- Out of scope: rar (proprietary), lha (obsolete)

### Complexity to Avoid

**1. Excessive Abstraction**
- Only abstract when 2+ implementations actually exist
- YAGNI principle (You Aren't Gonna Need It)

**2. Configuration Files**
- Minimize behavior changes via `~/.zarcrc` or environment variables
- Exception: `ZARC_NO_COLOR` (widely accepted convention)

**3. Magic Behavior**
- Don't guess user intent
- All behavior controlled by explicit options

---

## Quality Standards

### Definition of Release-Ready

- ✅ All declared features implemented and working
- ✅ 80%+ test coverage in core logic
- ✅ Complete README, CLI help, API documentation
- ✅ Tests pass on the big three OSes (Windows/Linux/macOS)
- ✅ Performance equal to or better than existing tools
- ✅ No memory leaks

### Performance Benchmarks

| Operation | Target |
|-----------|--------|
| tar.gz compression | 90%+ of GNU tar |
| tar.gz extraction | 90%+ of GNU tar |
| zip extraction | 90%+ of Info-ZIP |
| 7z extraction | 80%+ of 7-Zip |
| Memory | ≤128MB (normal files) |

---

## Long-term Vision

### 3-Year Goals (2028)

**1. De Facto Standard**
- 10,000+ GitHub Stars
- Default package in major Linux distributions
- Recommended tool in official Zig documentation

**2. Multi-language Usage**
- C API, Python, Rust, Node.js bindings

**3. Educational Value**
- Reference implementation for learning compression algorithms and Zig

### Milestones

| Timeline | Version | Key Features |
|----------|---------|--------------|
| 2025 Q4 | v0.1.0 | tar + gzip support |
| 2026 Q1 | v0.2.0 | zip support, compression |
| 2026 Q2 | v0.3.0 | 7z reading |
| 2026 Q3 | v0.4.0 | 7z writing |
| 2026 Q4 | v1.0.0 | Stable release, C API |
| 2027 | v1.1.0 | Language bindings |
| 2028+ | v2.0.0 | Plugin system |

### Monetization Direction (Under Consideration)

**Core Principle**: Core tool remains free and open source forever

**Models Under Consideration**:
- Enterprise support contracts
- Cloud-optimized version
- Special features for large datasets
- Training and consulting

**Decision Criteria**: Consider only if it doesn't harm community health

---

## Contribution Policy

### Welcome Contributions

**1. Bug Fixes** - Always top priority for merge
**2. Documentation Improvements** - Especially welcome
**3. New Format Support** - If aligned with Phase plan
**4. Performance Improvements** - With benchmark results

### Contributions Requiring Careful Review

**1. New Features** - Discuss in Issue first
**2. Large Refactoring** - Gradual proposals recommended
**3. Adding Dependencies** - Requires strong justification

### Process

1. Read `CONTRIBUTING.md`
2. Choose from [Good First Issue] labels
3. Fork → Branch → Implement → Pull Request
4. Initial review typically within 48 hours

---

## Document Update Policy

- **Important Technical Choices**: Record as ADR (Architecture Decision Record)
- **Principle Changes**: Require core team consensus (3+ people)
- **Regular Review**: At major version updates (approximately annually)

---

**This design philosophy is the foundation of all decision-making in the zarc project.**
When in doubt, return to this document.
