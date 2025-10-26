#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Copyright 2025 itsakeyfut
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Test Fixture Generation Script
#
# This script generates test archive files for compatibility testing.
# It creates archives using both GNU tar and BSD tar (when available).

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures"
SAMPLE_DATA="$FIXTURES_DIR/sample_data"

echo "==================================="
echo "Test Fixture Generation"
echo "==================================="
echo ""

# Detect tar implementation
TAR_VERSION=$(tar --version 2>&1 | head -1)
if echo "$TAR_VERSION" | grep -q "GNU tar"; then
    TAR_TYPE="GNU"
    echo -e "${GREEN}✓${NC} Detected GNU tar"
elif echo "$TAR_VERSION" | grep -q "bsdtar"; then
    TAR_TYPE="BSD"
    echo -e "${GREEN}✓${NC} Detected BSD tar"
else
    TAR_TYPE="UNKNOWN"
    echo -e "${YELLOW}⚠${NC} Unknown tar implementation: $TAR_VERSION"
fi

# Check for compression tools
HAS_GZIP=false
HAS_BZIP2=false
HAS_XZ=false

if command -v gzip &> /dev/null; then
    HAS_GZIP=true
    GZIP_VERSION=$(gzip --version 2>&1 | head -1)
    echo -e "${GREEN}✓${NC} Found gzip: $GZIP_VERSION"
fi

if command -v bzip2 &> /dev/null; then
    HAS_BZIP2=true
    BZIP2_VERSION=$(bzip2 --version 2>&1 | head -1)
    echo -e "${GREEN}✓${NC} Found bzip2: $BZIP2_VERSION"
fi

if command -v xz &> /dev/null; then
    HAS_XZ=true
    XZ_VERSION=$(xz --version 2>&1 | head -1)
    echo -e "${GREEN}✓${NC} Found xz: $XZ_VERSION"
fi

echo ""

# Create output directories
mkdir -p "$FIXTURES_DIR/gnu_tar"
mkdir -p "$FIXTURES_DIR/bsd_tar"
mkdir -p "$FIXTURES_DIR/malicious"

echo "Generating test archives..."
echo ""

# ============================================================================
# GNU tar archives
# ============================================================================

if [ "$TAR_TYPE" = "GNU" ]; then
    echo "--- GNU tar archives ---"

    # Basic uncompressed tar
    echo -n "Creating basic archive (GNU tar)... "
    (cd "$SAMPLE_DATA" && tar cf "$FIXTURES_DIR/gnu_tar/basic.tar" .)
    echo -e "${GREEN}✓${NC} ($(stat -c%s "$FIXTURES_DIR/gnu_tar/basic.tar" 2>/dev/null || stat -f%z "$FIXTURES_DIR/gnu_tar/basic.tar" 2>/dev/null) bytes)"

    # Gzip compressed
    if [ "$HAS_GZIP" = true ]; then
        echo -n "Creating gzip compressed (GNU tar)... "
        (cd "$SAMPLE_DATA" && tar czf "$FIXTURES_DIR/gnu_tar/basic.tar.gz" .)
        echo -e "${GREEN}✓${NC} ($(stat -c%s "$FIXTURES_DIR/gnu_tar/basic.tar.gz" 2>/dev/null || stat -f%z "$FIXTURES_DIR/gnu_tar/basic.tar.gz" 2>/dev/null) bytes)"
    fi

    # Bzip2 compressed
    if [ "$HAS_BZIP2" = true ]; then
        echo -n "Creating bzip2 compressed (GNU tar)... "
        (cd "$SAMPLE_DATA" && tar cjf "$FIXTURES_DIR/gnu_tar/basic.tar.bz2" .)
        echo -e "${GREEN}✓${NC} ($(stat -c%s "$FIXTURES_DIR/gnu_tar/basic.tar.bz2" 2>/dev/null || stat -f%z "$FIXTURES_DIR/gnu_tar/basic.tar.bz2" 2>/dev/null) bytes)"
    fi

    # XZ compressed
    if [ "$HAS_XZ" = true ]; then
        echo -n "Creating xz compressed (GNU tar)... "
        (cd "$SAMPLE_DATA" && tar cJf "$FIXTURES_DIR/gnu_tar/basic.tar.xz" .)
        echo -e "${GREEN}✓${NC} ($(stat -c%s "$FIXTURES_DIR/gnu_tar/basic.tar.xz" 2>/dev/null || stat -f%z "$FIXTURES_DIR/gnu_tar/basic.tar.xz" 2>/dev/null) bytes)"
    fi

    # Long filename (GNU extension)
    echo -n "Creating long filename archive... "
    LONG_NAME=$(printf 'a%.0s' {1..200})".txt"
    TEMP_DIR=$(mktemp -d)
    echo "test content" > "$TEMP_DIR/$LONG_NAME"
    (cd "$TEMP_DIR" && tar cf "$FIXTURES_DIR/gnu_tar/long_filename.tar" "$LONG_NAME")
    rm -rf "$TEMP_DIR"
    echo -e "${GREEN}✓${NC}"

    # Unicode filenames
    echo -n "Creating unicode filename archive... "
    TEMP_DIR=$(mktemp -d)
    echo "UTF-8 content" > "$TEMP_DIR/日本語.txt"
    echo "UTF-8 content" > "$TEMP_DIR/emoji_🦀.txt"
    echo "UTF-8 content" > "$TEMP_DIR/Ψυχή.txt"
    (cd "$TEMP_DIR" && tar cf "$FIXTURES_DIR/gnu_tar/unicode.tar" .)
    rm -rf "$TEMP_DIR"
    echo -e "${GREEN}✓${NC}"

    # Archive with symlinks
    echo -n "Creating archive with symlinks... "
    TEMP_DIR=$(mktemp -d)
    echo "target content" > "$TEMP_DIR/target.txt"
    ln -s target.txt "$TEMP_DIR/link.txt"
    (cd "$TEMP_DIR" && tar cf "$FIXTURES_DIR/gnu_tar/with_symlinks.tar" .)
    rm -rf "$TEMP_DIR"
    echo -e "${GREEN}✓${NC}"

    echo ""
fi

# ============================================================================
# BSD tar archives
# ============================================================================

if [ "$TAR_TYPE" = "BSD" ]; then
    echo "--- BSD tar archives ---"

    # Basic uncompressed tar
    echo -n "Creating basic archive (BSD tar)... "
    (cd "$SAMPLE_DATA" && tar cf "$FIXTURES_DIR/bsd_tar/basic.tar" .)
    echo -e "${GREEN}✓${NC}"

    # Gzip compressed
    if [ "$HAS_GZIP" = true ]; then
        echo -n "Creating gzip compressed (BSD tar)... "
        (cd "$SAMPLE_DATA" && tar czf "$FIXTURES_DIR/bsd_tar/basic.tar.gz" .)
        echo -e "${GREEN}✓${NC}"
    fi

    # Bzip2 compressed
    if [ "$HAS_BZIP2" = true ]; then
        echo -n "Creating bzip2 compressed (BSD tar)... "
        (cd "$SAMPLE_DATA" && tar cjf "$FIXTURES_DIR/bsd_tar/basic.tar.bz2" .)
        echo -e "${GREEN}✓${NC}"
    fi

    # Archive created on macOS
    echo -n "Creating macOS-created archive... "
    (cd "$SAMPLE_DATA" && tar cf "$FIXTURES_DIR/bsd_tar/macos_created.tar" .)
    echo -e "${GREEN}✓${NC}"

    echo ""
fi

# ============================================================================
# Security test archives
# ============================================================================

if [ "$TAR_TYPE" = "GNU" ]; then
    echo "--- Security test archives ---"

    # Path traversal archive
    echo -n "Creating path traversal test archive... "
    TEMP_DIR=$(mktemp -d)
    mkdir -p "$TEMP_DIR/safe"
    echo "safe content" > "$TEMP_DIR/safe/file.txt"
    (cd "$TEMP_DIR" && tar cf "$FIXTURES_DIR/malicious/path_traversal.tar" \
        --transform='s,safe/,../../../etc/,' safe/file.txt)
    rm -rf "$TEMP_DIR"
    echo -e "${GREEN}✓${NC}"

    # Symlink escape archive
    echo -n "Creating symlink escape test archive... "
    TEMP_DIR=$(mktemp -d)
    ln -s /etc/passwd "$TEMP_DIR/escaped_link"
    (cd "$TEMP_DIR" && tar cf "$FIXTURES_DIR/malicious/symlink_escape.tar" escaped_link)
    rm -rf "$TEMP_DIR"
    echo -e "${GREEN}✓${NC}"

    echo ""
else
    echo "--- Security test archives ---"
    echo -e "${YELLOW}⚠${NC} Skipping: requires GNU tar for --transform support"
    echo ""
fi

# ============================================================================
# Summary
# ============================================================================

echo "==================================="
echo "Summary"
echo "==================================="
echo ""
echo "Test fixtures have been generated in:"
echo "  $FIXTURES_DIR"
echo ""
echo "GNU tar archives:"
ls -lh "$FIXTURES_DIR/gnu_tar/" 2>/dev/null | tail -n +2 | awk '{print "  " $9 " (" $5 ")"}'
echo ""

if [ -d "$FIXTURES_DIR/bsd_tar" ] && [ "$(ls -A "$FIXTURES_DIR/bsd_tar" 2>/dev/null)" ]; then
    echo "BSD tar archives:"
    ls -lh "$FIXTURES_DIR/bsd_tar/" 2>/dev/null | tail -n +2 | awk '{print "  " $9 " (" $5 ")"}'
    echo ""
fi

echo "Security test archives:"
ls -lh "$FIXTURES_DIR/malicious/" 2>/dev/null | tail -n +2 | awk '{print "  " $9 " (" $5 ")"}'
echo ""

echo -e "${GREEN}✓${NC} Test fixture generation complete!"
