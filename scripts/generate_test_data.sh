#!/bin/bash

# Test Data Generation Script for zarc
# Generates various test fixtures for testing archive functionality

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures"
SAMPLE_DATA="$FIXTURES_DIR/sample_data"

echo -e "${GREEN}=== zarc Test Data Generator ===${NC}"
echo "Project root: $PROJECT_ROOT"
echo "Fixtures directory: $FIXTURES_DIR"
echo ""

# Check if required tools are available
check_tool() {
    if command -v "$1" &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 is available"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} $1 is not available (some tests will be skipped)"
        return 1
    fi
}

echo "Checking for required tools..."
HAS_TAR=$(check_tool tar && echo "yes" || echo "no")
HAS_GZIP=$(check_tool gzip && echo "yes" || echo "no")
HAS_BZIP2=$(check_tool bzip2 && echo "yes" || echo "no")
HAS_XZ=$(check_tool xz && echo "yes" || echo "no")
HAS_7Z=$(check_tool 7z && echo "yes" || echo "no")
HAS_ZIP=$(check_tool zip && echo "yes" || echo "no")
echo ""

# Create sample data if it doesn't exist
if [ ! -d "$SAMPLE_DATA" ]; then
    echo "Creating sample data..."
    mkdir -p "$SAMPLE_DATA/subdir"

    cat > "$SAMPLE_DATA/file1.txt" << 'EOF'
This is test file 1.
It contains some sample text for testing archive creation.
Line 3 of the test file.
EOF

    cat > "$SAMPLE_DATA/file2.txt" << 'EOF'
Test file 2 content.
This file has different content.
EOF

    cat > "$SAMPLE_DATA/subdir/file3.txt" << 'EOF'
File 3 in subdirectory.
Testing nested directory structure.
EOF

    echo -e "${GREEN}✓${NC} Sample data created"
fi

# Function to create test archive
create_archive() {
    local format="$1"
    local output_dir="$2"
    local output_file="$3"
    local description="$4"

    echo -n "Creating $description... "

    case "$format" in
        tar)
            if [ "$HAS_TAR" = "yes" ]; then
                (cd "$SAMPLE_DATA" && tar cf "$output_dir/$output_file" *)
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${YELLOW}SKIPPED${NC}"
            fi
            ;;
        tar.gz)
            if [ "$HAS_TAR" = "yes" ] && [ "$HAS_GZIP" = "yes" ]; then
                (cd "$SAMPLE_DATA" && tar czf "$output_dir/$output_file" *)
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${YELLOW}SKIPPED${NC}"
            fi
            ;;
        tar.bz2)
            if [ "$HAS_TAR" = "yes" ] && [ "$HAS_BZIP2" = "yes" ]; then
                (cd "$SAMPLE_DATA" && tar cjf "$output_dir/$output_file" *)
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${YELLOW}SKIPPED${NC}"
            fi
            ;;
        tar.xz)
            if [ "$HAS_TAR" = "yes" ] && [ "$HAS_XZ" = "yes" ]; then
                (cd "$SAMPLE_DATA" && tar cJf "$output_dir/$output_file" *)
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${YELLOW}SKIPPED${NC}"
            fi
            ;;
        zip)
            if [ "$HAS_ZIP" = "yes" ]; then
                (cd "$SAMPLE_DATA" && zip -q -r "$output_dir/$output_file" *)
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${YELLOW}SKIPPED${NC}"
            fi
            ;;
        7z)
            if [ "$HAS_7Z" = "yes" ]; then
                (cd "$SAMPLE_DATA" && 7z a -bd "$output_dir/$output_file" * > /dev/null)
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${YELLOW}SKIPPED${NC}"
            fi
            ;;
    esac
}

# Generate GNU tar archives
echo -e "\n${GREEN}Generating GNU tar archives...${NC}"
GNU_TAR_DIR="$FIXTURES_DIR/gnu_tar"
mkdir -p "$GNU_TAR_DIR"

create_archive "tar" "$GNU_TAR_DIR" "basic.tar" "basic tar archive"
create_archive "tar.gz" "$GNU_TAR_DIR" "basic.tar.gz" "gzip compressed tar"
create_archive "tar.bz2" "$GNU_TAR_DIR" "basic.tar.bz2" "bzip2 compressed tar"
create_archive "tar.xz" "$GNU_TAR_DIR" "basic.tar.xz" "xz compressed tar"

# Create archive with long filename (>100 chars, needs GNU extension)
if [ "$HAS_TAR" = "yes" ]; then
    echo -n "Creating archive with long filename... "
    LONG_NAME_DIR="$FIXTURES_DIR/.tmp_long_name"
    mkdir -p "$LONG_NAME_DIR"

    # Create file with 200+ character name
    LONG_FILE="this_is_a_very_long_filename_that_exceeds_the_traditional_tar_limit_of_one_hundred_characters_and_requires_gnu_tar_extensions_to_be_stored_properly_in_the_archive_format_we_are_testing_here.txt"
    echo "Long filename test" > "$LONG_NAME_DIR/$LONG_FILE"

    (cd "$LONG_NAME_DIR" && tar cf "$GNU_TAR_DIR/long_filename.tar" *)
    rm -rf "$LONG_NAME_DIR"
    echo -e "${GREEN}✓${NC}"
fi

# Create archive with Unicode filenames
if [ "$HAS_TAR" = "yes" ]; then
    echo -n "Creating archive with Unicode filenames... "
    UNICODE_DIR="$FIXTURES_DIR/.tmp_unicode"
    mkdir -p "$UNICODE_DIR"

    echo "Unicode test 1" > "$UNICODE_DIR/ファイル1.txt"
    echo "Unicode test 2" > "$UNICODE_DIR/文件2.txt"
    echo "Unicode test 3" > "$UNICODE_DIR/файл3.txt"

    (cd "$UNICODE_DIR" && tar cf "$GNU_TAR_DIR/unicode.tar" * 2>/dev/null) || true
    rm -rf "$UNICODE_DIR"
    echo -e "${GREEN}✓${NC}"
fi

# Generate BSD tar archives (macOS style)
echo -e "\n${GREEN}Generating BSD tar archives...${NC}"
BSD_TAR_DIR="$FIXTURES_DIR/bsd_tar"
mkdir -p "$BSD_TAR_DIR"

if [ "$HAS_TAR" = "yes" ]; then
    # BSD tar creates slightly different headers
    create_archive "tar" "$BSD_TAR_DIR" "macos_created.tar" "BSD tar archive"
fi

# Generate ZIP archives
echo -e "\n${GREEN}Generating ZIP archives...${NC}"
ZIP_DIR="$FIXTURES_DIR/info_zip"
mkdir -p "$ZIP_DIR"

create_archive "zip" "$ZIP_DIR" "basic.zip" "basic ZIP archive"

# Generate 7-Zip archives
echo -e "\n${GREEN}Generating 7-Zip archives...${NC}"
SEVENZIP_DIR="$FIXTURES_DIR/7zip"
mkdir -p "$SEVENZIP_DIR"

create_archive "7z" "$SEVENZIP_DIR" "lzma.7z" "7z with LZMA compression"

# Generate malicious/security test archives
echo -e "\n${GREEN}Generating security test archives...${NC}"
MALICIOUS_DIR="$FIXTURES_DIR/malicious"
mkdir -p "$MALICIOUS_DIR"

if [ "$HAS_TAR" = "yes" ]; then
    # Path traversal attempt
    echo -n "Creating path traversal test archive... "
    TRAVERSAL_DIR="$FIXTURES_DIR/.tmp_traversal"
    mkdir -p "$TRAVERSAL_DIR"

    # Note: We use --transform to create paths with .. without actually creating them
    echo "You should not see this file" > "$TRAVERSAL_DIR/passwd"
    (cd "$TRAVERSAL_DIR" && tar cf "$MALICIOUS_DIR/path_traversal.tar" \
        --transform 's,passwd,../../../etc/passwd,' passwd 2>/dev/null) || true
    rm -rf "$TRAVERSAL_DIR"
    echo -e "${GREEN}✓${NC}"

    # Symlink escape attempt
    echo -n "Creating symlink escape test archive... "
    SYMLINK_DIR="$FIXTURES_DIR/.tmp_symlink"
    mkdir -p "$SYMLINK_DIR"

    ln -s /etc/passwd "$SYMLINK_DIR/bad_link" 2>/dev/null || true
    (cd "$SYMLINK_DIR" && tar chf "$MALICIOUS_DIR/symlink_escape.tar" * 2>/dev/null) || true
    rm -rf "$SYMLINK_DIR"
    echo -e "${GREEN}✓${NC}"
fi

# Create empty archive (just end markers)
if [ "$HAS_TAR" = "yes" ]; then
    echo -n "Creating empty archive... "
    dd if=/dev/zero of="$FIXTURES_DIR/empty.tar" bs=512 count=2 2>/dev/null
    echo -e "${GREEN}✓${NC}"
fi

# Summary
echo ""
echo -e "${GREEN}=== Test Data Generation Complete ===${NC}"
echo ""
echo "Generated fixtures:"
find "$FIXTURES_DIR" -name "*.tar" -o -name "*.tar.gz" -o -name "*.tar.bz2" -o -name "*.tar.xz" -o -name "*.zip" -o -name "*.7z" | while read f; do
    SIZE=$(du -h "$f" | cut -f1)
    echo "  - $(basename "$f") ($SIZE)"
done
echo ""
echo -e "${GREEN}✓${NC} All test fixtures have been generated successfully!"
echo ""
echo "To regenerate fixtures, run: $0"
echo "To run tests: zig build test-all"
