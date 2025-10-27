#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2025 itsakeyfut
#
# Test fixture generation script for tar.gz integration tests
# Issue #56: Integration Test Framework
#
# This script generates various test archives using GNU tar to ensure
# compatibility testing with real-world archives.
#
# Usage: ./scripts/generate_test_fixtures.sh

set -e
set -u
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Base directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures"
GNU_TAR_DIR="$FIXTURES_DIR/gnu_tar"
TEMP_DATA_DIR="$FIXTURES_DIR/temp_test_data"

echo -e "${GREEN}=== Test Fixture Generation ===${NC}"
echo "Project root: $PROJECT_ROOT"
echo "Fixtures dir: $FIXTURES_DIR"
echo ""

# Check for required tools
echo -e "${YELLOW}Checking required tools...${NC}"

if ! command -v tar &> /dev/null; then
    echo -e "${RED}Error: tar command not found${NC}"
    exit 1
fi

if ! command -v gzip &> /dev/null; then
    echo -e "${RED}Error: gzip command not found${NC}"
    exit 1
fi

TAR_VERSION=$(tar --version | head -n1)
echo "Found: $TAR_VERSION"
echo ""

# Create directories if they don't exist
echo -e "${YELLOW}Setting up directories...${NC}"
mkdir -p "$GNU_TAR_DIR"
mkdir -p "$TEMP_DATA_DIR"
echo "Created $GNU_TAR_DIR"
echo "Created $TEMP_DATA_DIR"
echo ""

# Clean up any existing temp data
rm -rf "$TEMP_DATA_DIR"/*

# ============================================================================
# File Size Test Fixtures
# ============================================================================

echo -e "${GREEN}=== Generating File Size Test Fixtures ===${NC}"

# Tiny files (<1KB)
echo "Creating tiny file fixtures..."
mkdir -p "$TEMP_DATA_DIR/tiny"
echo "Hello, World! This is a tiny test file." > "$TEMP_DATA_DIR/tiny/tiny1.txt"
echo "Another tiny file." > "$TEMP_DATA_DIR/tiny/tiny2.txt"
tar -czf "$GNU_TAR_DIR/tiny_files.tar.gz" -C "$TEMP_DATA_DIR" tiny/
echo "✓ Created tiny_files.tar.gz"

# Small files (1KB-100KB)
echo "Creating small file fixtures..."
mkdir -p "$TEMP_DATA_DIR/small"
# Generate 5KB file
head -c 5120 /dev/urandom | base64 > "$TEMP_DATA_DIR/small/small1.txt"
# Generate 10KB file
head -c 10240 /dev/urandom | base64 > "$TEMP_DATA_DIR/small/small2.txt"
# Generate 50KB file
head -c 51200 /dev/urandom | base64 > "$TEMP_DATA_DIR/small/small3.txt"
tar -czf "$GNU_TAR_DIR/small_files.tar.gz" -C "$TEMP_DATA_DIR" small/
echo "✓ Created small_files.tar.gz"

# Medium files (1MB-10MB) - optional, commented out to avoid large test files
# echo "Creating medium file fixtures..."
# mkdir -p "$TEMP_DATA_DIR/medium"
# head -c 1048576 /dev/urandom | base64 > "$TEMP_DATA_DIR/medium/medium1.txt"  # 1MB
# tar -czf "$GNU_TAR_DIR/medium_files.tar.gz" -C "$TEMP_DATA_DIR" medium/
# echo "✓ Created medium_files.tar.gz"

# ============================================================================
# Content Type Test Fixtures
# ============================================================================

echo ""
echo -e "${GREEN}=== Generating Content Type Test Fixtures ===${NC}"

# Text files
echo "Creating text file fixtures..."
mkdir -p "$TEMP_DATA_DIR/text"
cat > "$TEMP_DATA_DIR/text/text1.txt" << 'EOF'
# Sample Text File
This is a sample text file for testing tar.gz extraction.
It contains multiple lines of text.

Line 1
Line 2
Line 3

The quick brown fox jumps over the lazy dog.
EOF

cat > "$TEMP_DATA_DIR/text/text2.txt" << 'EOF'
Another text file with different content.
Testing newlines and special characters: !@#$%^&*()
EOF

tar -czf "$GNU_TAR_DIR/text_files.tar.gz" -C "$TEMP_DATA_DIR" text/
echo "✓ Created text_files.tar.gz"

# Binary files
echo "Creating binary file fixtures..."
mkdir -p "$TEMP_DATA_DIR/binary"
# Generate random binary data
head -c 1024 /dev/urandom > "$TEMP_DATA_DIR/binary/binary1.bin"
head -c 2048 /dev/urandom > "$TEMP_DATA_DIR/binary/binary2.bin"
tar -czf "$GNU_TAR_DIR/binary_files.tar.gz" -C "$TEMP_DATA_DIR" binary/
echo "✓ Created binary_files.tar.gz"

# Empty files
echo "Creating empty file fixtures..."
mkdir -p "$TEMP_DATA_DIR/empty"
touch "$TEMP_DATA_DIR/empty/empty1.txt"
touch "$TEMP_DATA_DIR/empty/empty2.txt"
touch "$TEMP_DATA_DIR/empty/empty3.txt"
tar -czf "$GNU_TAR_DIR/empty_files.tar.gz" -C "$TEMP_DATA_DIR" empty/
echo "✓ Created empty_files.tar.gz"

# ============================================================================
# Structure Test Fixtures
# ============================================================================

echo ""
echo -e "${GREEN}=== Generating Structure Test Fixtures ===${NC}"

# Flat structure (files only)
echo "Creating flat structure fixtures..."
mkdir -p "$TEMP_DATA_DIR/flat"
for i in {1..10}; do
    echo "File $i content" > "$TEMP_DATA_DIR/flat/file$i.txt"
done
tar -czf "$GNU_TAR_DIR/flat_structure.tar.gz" -C "$TEMP_DATA_DIR" flat/
echo "✓ Created flat_structure.tar.gz"

# Nested directories (depth 10+)
echo "Creating nested structure fixtures..."
mkdir -p "$TEMP_DATA_DIR/nested/level1/level2/level3/level4/level5/level6/level7/level8/level9/level10"
echo "Deep file content" > "$TEMP_DATA_DIR/nested/level1/level2/level3/level4/level5/level6/level7/level8/level9/level10/deep.txt"
echo "Another deep file" > "$TEMP_DATA_DIR/nested/level1/level2/level3/level4/level5/mid.txt"
tar -czf "$GNU_TAR_DIR/nested_structure.tar.gz" -C "$TEMP_DATA_DIR" nested/
echo "✓ Created nested_structure.tar.gz"

# Mixed (files + directories)
echo "Creating mixed structure fixtures..."
mkdir -p "$TEMP_DATA_DIR/mixed/subdir1/subdir2"
echo "Root file" > "$TEMP_DATA_DIR/mixed/root.txt"
echo "Subdir1 file" > "$TEMP_DATA_DIR/mixed/subdir1/file1.txt"
echo "Subdir2 file" > "$TEMP_DATA_DIR/mixed/subdir1/subdir2/file2.txt"
echo "Another root file" > "$TEMP_DATA_DIR/mixed/root2.txt"
tar -czf "$GNU_TAR_DIR/mixed_structure.tar.gz" -C "$TEMP_DATA_DIR" mixed/
echo "✓ Created mixed_structure.tar.gz"

# Empty directories
echo "Creating empty directory fixtures..."
mkdir -p "$TEMP_DATA_DIR/empty_dirs/dir1/dir2/dir3"
mkdir -p "$TEMP_DATA_DIR/empty_dirs/dir4"
# Create at least one file so tar doesn't complain
echo "placeholder" > "$TEMP_DATA_DIR/empty_dirs/placeholder.txt"
tar -czf "$GNU_TAR_DIR/empty_directories.tar.gz" -C "$TEMP_DATA_DIR" empty_dirs/
echo "✓ Created empty_directories.tar.gz"

# ============================================================================
# Special Case Test Fixtures
# ============================================================================

echo ""
echo -e "${GREEN}=== Generating Special Case Test Fixtures ===${NC}"

# Long filenames (already exists in tests/fixtures/gnu_tar/long_filename.tar)
echo "Verifying long filename fixture exists..."
if [ -f "$GNU_TAR_DIR/long_filename.tar" ]; then
    echo "✓ long_filename.tar already exists"
else
    echo "Creating long filename fixture..."
    mkdir -p "$TEMP_DATA_DIR/long"
    # Create a file with a very long name (200+ characters)
    LONG_NAME="this_is_a_very_long_filename_that_exceeds_the_traditional_100_character_limit_in_tar_archives_and_requires_GNU_tar_extensions_to_handle_properly_this_ensures_we_test_the_PAX_extended_header_support_correctly.txt"
    echo "Content of long filename file" > "$TEMP_DATA_DIR/long/$LONG_NAME"
    tar -cf "$GNU_TAR_DIR/long_filename.tar" -C "$TEMP_DATA_DIR" long/
    echo "✓ Created long_filename.tar"
fi

# Unicode filenames (already exists in tests/fixtures/gnu_tar/unicode.tar)
echo "Verifying unicode fixture exists..."
if [ -f "$GNU_TAR_DIR/unicode.tar" ]; then
    echo "✓ unicode.tar already exists"
else
    echo "Creating unicode filename fixture..."
    mkdir -p "$TEMP_DATA_DIR/unicode"
    echo "Japanese content" > "$TEMP_DATA_DIR/unicode/日本語ファイル.txt"
    echo "Emoji content" > "$TEMP_DATA_DIR/unicode/📁emoji_file📄.txt"
    echo "Mixed content" > "$TEMP_DATA_DIR/unicode/MixedUnicode_文字_😀.txt"
    tar -cf "$GNU_TAR_DIR/unicode.tar" -C "$TEMP_DATA_DIR" unicode/
    echo "✓ Created unicode.tar"
fi

# Special characters in names
echo "Creating special characters fixture..."
mkdir -p "$TEMP_DATA_DIR/special"
echo "Content" > "$TEMP_DATA_DIR/special/file with spaces.txt"
echo "Content" > "$TEMP_DATA_DIR/special/file-with-dashes.txt"
echo "Content" > "$TEMP_DATA_DIR/special/file_with_underscores.txt"
echo "Content" > "$TEMP_DATA_DIR/special/file.multiple.dots.txt"
tar -czf "$GNU_TAR_DIR/special_chars.tar.gz" -C "$TEMP_DATA_DIR" special/
echo "✓ Created special_chars.tar.gz"

# Symbolic links (already exists in tests/fixtures/gnu_tar/with_symlinks.tar)
echo "Verifying symlinks fixture exists..."
if [ -f "$GNU_TAR_DIR/with_symlinks.tar" ]; then
    echo "✓ with_symlinks.tar already exists"
else
    echo "Creating symlinks fixture..."
    mkdir -p "$TEMP_DATA_DIR/symlinks"
    echo "Target file content" > "$TEMP_DATA_DIR/symlinks/target.txt"
    (cd "$TEMP_DATA_DIR/symlinks" && ln -s target.txt link.txt)
    tar -chf "$GNU_TAR_DIR/with_symlinks.tar" -C "$TEMP_DATA_DIR" symlinks/
    echo "✓ Created with_symlinks.tar"
fi

# Hard links
echo "Creating hard links fixture..."
mkdir -p "$TEMP_DATA_DIR/hardlinks"
echo "Shared content" > "$TEMP_DATA_DIR/hardlinks/original.txt"
(cd "$TEMP_DATA_DIR/hardlinks" && ln original.txt hardlink.txt)
tar -cf "$GNU_TAR_DIR/hard_links.tar" -C "$TEMP_DATA_DIR" hardlinks/
echo "✓ Created hard_links.tar"

# ============================================================================
# Compression Level Test Fixtures
# ============================================================================

echo ""
echo -e "${GREEN}=== Generating Compression Level Test Fixtures ===${NC}"

# Create test data for compression level testing
mkdir -p "$TEMP_DATA_DIR/compression"
# Use text that compresses well
for i in {1..100}; do
    echo "This is line $i of repetitive text that should compress well." >> "$TEMP_DATA_DIR/compression/compressible.txt"
done

# Level 1 (fastest)
echo "Creating compression level 1 fixture..."
GZIP=-1 tar -czf "$GNU_TAR_DIR/compression_level1.tar.gz" -C "$TEMP_DATA_DIR" compression/
echo "✓ Created compression_level1.tar.gz (fastest)"

# Level 6 (default)
echo "Creating compression level 6 fixture..."
tar -czf "$GNU_TAR_DIR/compression_level6.tar.gz" -C "$TEMP_DATA_DIR" compression/
echo "✓ Created compression_level6.tar.gz (default)"

# Level 9 (best)
echo "Creating compression level 9 fixture..."
GZIP=-9 tar -czf "$GNU_TAR_DIR/compression_level9.tar.gz" -C "$TEMP_DATA_DIR" compression/
echo "✓ Created compression_level9.tar.gz (best)"

# Compare sizes
echo ""
echo "Compression level comparison:"
ls -lh "$GNU_TAR_DIR"/compression_level*.tar.gz | awk '{print $9, $5}'

# ============================================================================
# Sparse Files (if supported)
# ============================================================================

echo ""
echo -e "${GREEN}=== Generating Sparse File Fixtures ===${NC}"

echo "Creating sparse file fixture..."
mkdir -p "$TEMP_DATA_DIR/sparse"
# Create a sparse file using dd
dd if=/dev/zero of="$TEMP_DATA_DIR/sparse/sparse_file.bin" bs=1 count=0 seek=10M 2>/dev/null
echo "Data at the end" >> "$TEMP_DATA_DIR/sparse/sparse_file.bin"
tar -czSf "$GNU_TAR_DIR/sparse_files.tar.gz" -C "$TEMP_DATA_DIR" sparse/
echo "✓ Created sparse_files.tar.gz"

# ============================================================================
# Clean up
# ============================================================================

echo ""
echo -e "${YELLOW}Cleaning up temporary files...${NC}"
rm -rf "$TEMP_DATA_DIR"
echo "✓ Removed $TEMP_DATA_DIR"

# ============================================================================
# Summary
# ============================================================================

echo ""
echo -e "${GREEN}=== Test Fixture Generation Complete ===${NC}"
echo ""
echo "Generated fixtures in: $GNU_TAR_DIR"
echo ""
echo "Fixture summary:"
echo "  - File size tests: tiny, small"
echo "  - Content type tests: text, binary, empty"
echo "  - Structure tests: flat, nested, mixed, empty directories"
echo "  - Special cases: long filenames, unicode, special chars, symlinks, hard links"
echo "  - Compression levels: 1 (fast), 6 (default), 9 (best)"
echo "  - Sparse files: sparse file support"
echo ""
echo "Total fixtures:"
ls -1 "$GNU_TAR_DIR"/*.tar.gz "$GNU_TAR_DIR"/*.tar 2>/dev/null | wc -l
echo ""
echo -e "${GREEN}Test fixtures are ready for integration testing!${NC}"
