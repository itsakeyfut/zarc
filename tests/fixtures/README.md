# Test Fixtures

This directory contains test data used for testing zarc functionality.

## Directory Structure

```
fixtures/
├── gnu_tar/          # Archives created with GNU tar
├── bsd_tar/          # Archives created with BSD tar (macOS)
├── 7zip/             # Archives created with 7-Zip
├── info_zip/         # Archives created with Info-ZIP
├── malicious/        # Malicious archives for security testing
└── sample_data/      # Sample data for creating test archives
```

## Generating Test Fixtures

Test fixtures should be generated using the `scripts/generate_test_data.sh` script to ensure consistency across platforms.

## Guidelines

- Keep individual test archives small (< 1MB when possible)
- Document the tool and version used to create each archive
- Include edge cases (long filenames, Unicode, symlinks, etc.)
- Never commit actual malicious files; use safe test patterns
