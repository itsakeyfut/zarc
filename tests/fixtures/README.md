# Test Fixtures

This directory contains test data used for testing zarc functionality.

## Directory Structure

```
fixtures/
├── gnu_tar/          # Archives created with GNU tar
│   ├── basic.tar           # Basic uncompressed tar
│   ├── basic.tar.gz        # Gzip compressed tar
│   ├── basic.tar.bz2       # Bzip2 compressed tar
│   ├── long_filename.tar   # Archive with >100 char filename (GNU extension)
│   └── unicode.tar         # Archive with Unicode filenames
├── bsd_tar/          # Archives created with BSD tar (macOS)
├── malicious/        # Security test archives
│   ├── path_traversal.tar  # Contains paths with ../
│   └── symlink_escape.tar  # Contains symlinks to /etc/passwd
├── sample_data/      # Sample data for creating test archives
│   ├── file1.txt
│   ├── file2.txt
│   └── subdir/
│       └── file3.txt
├── simple.tar        # Simple test archive used by integration tests
└── empty.tar         # Empty archive (just end markers)
```

## Generating Test Fixtures

Test fixtures can be regenerated using:

```bash
./scripts/generate_test_data.sh
```

Or manually created with:

```bash
cd tests/fixtures/sample_data
tar cf ../gnu_tar/basic.tar *
tar czf ../gnu_tar/basic.tar.gz *
tar cjf ../gnu_tar/basic.tar.bz2 *
```

## Tool Versions

Test archives were created with:
- GNU tar 1.35
- gzip 1.12
- bzip2 1.0.8
- xz 5.6.3

## Guidelines

- Keep individual test archives small (< 1MB when possible)
- Document the tool and version used to create each archive
- Include edge cases (long filenames, Unicode, symlinks, etc.)
- Never commit actual malicious files; use safe test patterns
- Security test archives use `--transform` to create dangerous paths without actually creating them

## Security Test Archives

The `malicious/` directory contains archives for testing security features:

- **path_traversal.tar**: Contains entries with `../../../etc/passwd` to test path sanitization
- **symlink_escape.tar**: Contains symlinks pointing to `/etc/passwd` to test symlink validation

These are safe test files that do not contain actual sensitive data.
