# Command-Line Interface Specification

**Last Updated**: 2025-10-18

---

## Table of Contents

1. [CLI Design Principles](#cli-design-principles)
2. [Basic Syntax](#basic-syntax)
3. [Subcommands](#subcommands)
4. [Global Options](#global-options)
5. [Output Format](#output-format)
6. [Error Handling](#error-handling)
7. [Usage Examples](#usage-examples)

---

## CLI Design Principles

### Core Philosophy

1. **Follow UNIX Philosophy**
   - Do one thing well
   - Handle text streams
   - Composable in pipelines

2. **Compatibility with Existing Tools**
   - Reference `tar` options
   - Incorporate `7z` usability
   - Intuitive subcommands

3. **Consistency**
   - Unified naming conventions
   - Predictable behavior
   - Clear error messages

4. **User-Friendly**
   - Colored output (can be disabled)
   - Progress display
   - Detailed help

---

## Basic Syntax

### Command Format

```
zarc <subcommand> [options] <arguments>
```

### Subcommand List

| Subcommand | Description | Aliases |
|------------|-------------|---------|
| `extract` | Extract archive | `x` |
| `compress` | Create archive | `c`, `create` |
| `list` | List contents | `l`, `ls` |
| `test` | Verify integrity | `t` |
| `info` | Show archive info | `i` |
| `help` | Show help | `h`, `-h`, `--help` |
| `version` | Show version | `v`, `-v`, `--version` |

---

## Subcommands

### extract (Extraction)

Extract archive files.

#### Syntax

```bash
zarc extract [options] <archive> [destination]
zarc x [options] <archive> [destination]
```

#### Arguments

- `<archive>`: Path to archive file (required)
- `[destination]`: Destination directory (default: current directory)

#### Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--output <dir>` | `-C <dir>` | Destination directory | `.` |
| `--overwrite` | `-f` | Overwrite existing files | false |
| `--keep-existing` | `-k` | Skip existing files | false |
| `--verbose` | `-v` | Verbose output | false |
| `--quiet` | `-q` | Minimal output | false |
| `--preserve-permissions` | `-p` | Preserve permissions | true |
| `--no-preserve-permissions` | | Ignore permissions | |
| `--include <pattern>` | | Extract only matching pattern | |
| `--exclude <pattern>` | | Exclude matching pattern | |
| `--strip-components <n>` | | Strip n leading path components | 0 |

#### Usage Examples

```bash
# Basic extraction
zarc extract archive.tar.gz

# Specify destination
zarc extract archive.tar.gz /tmp/output
zarc extract archive.tar.gz --output /tmp/output
zarc x archive.tar.gz -C /tmp/output

# Overwrite
zarc extract archive.tar.gz --overwrite
zarc extract archive.tar.gz -f

# Extract specific files only
zarc extract archive.tar.gz --include "*.txt"
zarc extract archive.tar.gz --exclude "*.log"

# Adjust paths
zarc extract archive.tar.gz --strip-components 1

# Verbose output
zarc extract archive.tar.gz --verbose
zarc extract archive.tar.gz -v
```

---

### compress (Compression)

Compress files or directories into an archive.

#### Syntax

```bash
zarc compress [options] <archive> <source>...
zarc c [options] <archive> <source>...
zarc create [options] <archive> <source>...
```

#### Arguments

- `<archive>`: Path to archive file to create (required)
- `<source>...`: Files/directories to compress (one or more required)

#### Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--format <fmt>` | `-f <fmt>` | Specify format | Auto-detect from extension |
| `--level <n>` | `-<n>` | Compression level (1-9) | 6 |
| `--fast` | `-1` | Fast compression (level 1) | |
| `--best` | `-9` | Maximum compression (level 9) | |
| `--verbose` | `-v` | Verbose output | false |
| `--exclude <pattern>` | | Exclude matching pattern | |
| `--follow-symlinks` | `-L` | Follow symbolic links | false |

#### Formats

| Format | Description | Extensions |
|--------|-------------|------------|
| `tar` | Uncompressed tar | `.tar` |
| `tar.gz` | gzip compressed tar | `.tar.gz`, `.tgz` |
| `tar.bz2` | bzip2 compressed tar | `.tar.bz2`, `.tbz2` |
| `tar.xz` | xz compressed tar | `.tar.xz`, `.txz` |
| `zip` | ZIP | `.zip` |
| `7z` | 7-Zip | `.7z` |

#### Usage Examples

```bash
# Basic compression
zarc compress archive.tar.gz folder/

# Explicit format specification
zarc compress --format tar.gz archive.tgz folder/

# Compression level
zarc compress --level 9 archive.tar.gz folder/
zarc compress -9 archive.tar.gz folder/
zarc compress --best archive.tar.gz folder/

# Multiple sources
zarc compress archive.tar.gz file1.txt file2.txt folder/

# Exclude patterns
zarc compress archive.tar.gz folder/ --exclude "*.log"
zarc compress archive.tar.gz folder/ --exclude ".git"

# Verbose output
zarc compress archive.tar.gz folder/ --verbose
zarc compress archive.tar.gz folder/ -v
```

---

### list (List Contents)

List archive contents.

#### Syntax

```bash
zarc list [options] <archive>
zarc l [options] <archive>
zarc ls [options] <archive>
```

#### Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--verbose` | `-v` | Show detailed information | false |
| `--long` | `-l` | Long format display | false |
| `--human-readable` | `-h` | Human-readable sizes | false |

#### Usage Examples

```bash
# Basic listing
zarc list archive.tar.gz

# Output example:
# file1.txt
# file2.txt
# folder/
# folder/file3.txt

# Detailed information
zarc list archive.tar.gz --verbose
zarc list archive.tar.gz -v

# Output example:
# -rw-r--r--  user  group    1024  2025-10-18 12:34  file1.txt
# -rw-r--r--  user  group    2048  2025-10-18 12:35  file2.txt
# drwxr-xr-x  user  group       0  2025-10-18 12:36  folder/
# -rw-r--r--  user  group     512  2025-10-18 12:37  folder/file3.txt

# Long format
zarc list archive.tar.gz --long
zarc list archive.tar.gz -l

# Human-readable sizes
zarc list archive.tar.gz -lh

# Output example:
# -rw-r--r--  user  group   1.0K  2025-10-18 12:34  file1.txt
# -rw-r--r--  user  group   2.0K  2025-10-18 12:35  file2.txt
```

---

### test (Integrity Verification)

Verify archive integrity.

#### Syntax

```bash
zarc test [options] <archive>
zarc t [options] <archive>
```

#### Options

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--verbose` | `-v` | Verbose output | false |

#### Usage Examples

```bash
# Basic verification
zarc test archive.tar.gz

# Success output:
# All OK

# Failure output:
# Error: Checksum mismatch at entry 'file1.txt'
# Error: Archive is corrupted

# Verbose output
zarc test archive.tar.gz --verbose
zarc test archive.tar.gz -v

# Output example:
# Testing file1.txt ... OK
# Testing file2.txt ... OK
# Testing folder/file3.txt ... OK
# All OK
```

---

### info (Show Information)

Display detailed archive information.

#### Syntax

```bash
zarc info [options] <archive>
zarc i [options] <archive>
```

#### Usage Examples

```bash
zarc info archive.tar.gz

# Output example:
# Archive: archive.tar.gz
# Format: tar.gz (gzip compressed tar)
# Compression: gzip (level 6)
# Files: 42
# Directories: 5
# Total size (uncompressed): 10.5 MB
# Archive size: 2.3 MB
# Compression ratio: 21.9%
# Created: 2025-10-18 12:34:56
```

---

## Global Options

Options available for all subcommands.

| Option | Short | Description |
|--------|-------|-------------|
| `--help` | `-h` | Show help |
| `--version` | `-V` | Show version |
| `--verbose` | `-v` | Verbose output |
| `--quiet` | `-q` | Minimal output |
| `--no-color` | | Disable colored output |

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ZARC_NO_COLOR` | Disable colored output | - |
| `NO_COLOR` | Disable colored output (standard) | - |

### Usage Examples

```bash
# Show help
zarc --help
zarc extract --help

# Show version
zarc --version
zarc -V

# Verbose output
zarc extract archive.tar.gz --verbose
zarc extract archive.tar.gz -v

# Quiet execution
zarc extract archive.tar.gz --quiet
zarc extract archive.tar.gz -q

# Disable colors
zarc list archive.tar.gz --no-color
ZARC_NO_COLOR=1 zarc list archive.tar.gz
NO_COLOR=1 zarc list archive.tar.gz
```

---

## Output Format

### Standard Output

#### On Success

```bash
$ zarc extract archive.tar.gz
Extracting archive.tar.gz...
Extracted 42 files (10.5 MB) in 2.3s
```

#### Progress Display

```bash
$ zarc extract large.tar.gz
Extracting large.tar.gz...
[████████████████████████████████] 100% (1000/1000 files)
Extracted 1000 files (1.2 GB) in 15.7s
```

### Colored Output

```bash
# Success (green)
✓ Extracted 42 files

# Warning (yellow)
⚠ File 'test.txt' already exists, skipping

# Error (red)
✗ Error: Archive is corrupted
```

### Verbose Output (--verbose)

```bash
$ zarc extract archive.tar.gz --verbose
Opening archive: archive.tar.gz
Format detected: tar.gz (gzip compressed tar)
Extracting to: ./
  [1/42] file1.txt (1.0 KB) ... OK
  [2/42] file2.txt (2.0 KB) ... OK
  [3/42] folder/ ... OK
  [4/42] folder/file3.txt (512 B) ... OK
  ...
Extracted 42 files (10.5 MB) in 2.3s
Average speed: 4.6 MB/s
```

---

## Error Handling

### Exit Codes

| Code | Description |
|------|-------------|
| `0` | Success |
| `1` | General error |
| `2` | Command-line argument error |
| `3` | File not found |
| `4` | Permission error |
| `5` | Corrupted archive |
| `6` | Unsupported format |

### Error Messages

```bash
# File not found
$ zarc extract missing.tar.gz
Error: Cannot open archive file 'missing.tar.gz'
Reason: File not found (ENOENT)
Suggestion: Check if the file path is correct
Exit code: 3

# Permission error
$ zarc extract protected.tar.gz
Error: Cannot open archive file 'protected.tar.gz'
Reason: Permission denied (EACCES)
Suggestion: Check file permissions with 'ls -l protected.tar.gz'
            or try running with appropriate privileges
Exit code: 4

# Corrupted archive
$ zarc extract corrupted.tar.gz
Error: Archive is corrupted
File: corrupted.tar.gz
Offset: 0x1234
Reason: Invalid header format
Suggestion: The archive may be incomplete or damaged
            Try downloading it again or use 'zarc test' to verify
Exit code: 5
```

---

## Usage Examples

### Basic Usage

```bash
# Extract archive
zarc extract archive.tar.gz

# Compress directory
zarc compress backup.tar.gz ~/Documents/

# Check contents
zarc list archive.tar.gz

# Verify integrity
zarc test archive.tar.gz
```

### Advanced Examples

#### 1. Extract Specific Files Only

```bash
# Text files only
zarc extract archive.tar.gz --include "*.txt"

# Exclude log files
zarc extract archive.tar.gz --exclude "*.log"

# Multiple patterns
zarc extract archive.tar.gz --include "*.txt" --include "*.md"
```

#### 2. Creating Backups

```bash
# Backup with date
zarc compress backup-$(date +%Y%m%d).tar.gz ~/Documents/

# Maximum compression
zarc compress --best backup.tar.gz ~/Documents/

# Exclude log files
zarc compress backup.tar.gz ~/Documents/ --exclude "*.log"
```

#### 3. Pipeline Usage

```bash
# Extract directly from remote server
ssh server "cat archive.tar.gz" | zarc extract --stdin

# Compress and send to remote
zarc compress --stdout folder/ | ssh server "cat > archive.tar.gz"

# Extract from URL
curl https://example.com/archive.tar.gz | zarc extract --stdin
```

#### 4. Progress Monitoring

```bash
# Extract large archive
zarc extract large.tar.gz --verbose

# Detailed logging
zarc extract archive.tar.gz -vv > extract.log 2>&1
```

---

## Migration from tar Command

### Command Mapping

| tar command | zarc command |
|-------------|--------------|
| `tar xzf archive.tar.gz` | `zarc extract archive.tar.gz` |
| `tar czf archive.tar.gz dir/` | `zarc compress archive.tar.gz dir/` |
| `tar tzf archive.tar.gz` | `zarc list archive.tar.gz` |
| `tar xzf archive.tar.gz -C /dest` | `zarc extract archive.tar.gz -C /dest` |
| `tar czf archive.tar.gz --exclude="*.log" dir/` | `zarc compress archive.tar.gz dir/ --exclude="*.log"` |

---

## Help Text

### Main Help

```
zarc - Zig Archive Tool

USAGE:
    zarc <subcommand> [options] <arguments>

SUBCOMMANDS:
    extract, x      Extract archive
    compress, c     Create archive
    list, l         List contents
    test, t         Test integrity
    info, i         Show information
    help, h         Show help
    version, v      Show version

OPTIONS:
    -h, --help      Show help
    -V, --version   Show version
    -v, --verbose   Verbose output
    -q, --quiet     Minimal output
    --no-color      Disable color output

EXAMPLES:
    zarc extract archive.tar.gz
    zarc compress backup.tar.gz ~/Documents/
    zarc list archive.tar.gz
    zarc test archive.tar.gz

For more information, see: https://zarc.dev
```

### extract Subcommand Help

```
zarc extract - Extract archive

USAGE:
    zarc extract [options] <archive> [destination]

ARGUMENTS:
    <archive>       Archive file to extract
    [destination]   Destination directory (default: current directory)

OPTIONS:
    -C, --output <dir>          Destination directory
    -f, --overwrite             Overwrite existing files
    -k, --keep-existing         Skip existing files
    -v, --verbose               Verbose output
    -q, --quiet                 Minimal output
    -p, --preserve-permissions  Preserve permissions (default)
    --no-preserve-permissions   Ignore permissions
    --include <pattern>         Extract only matching files
    --exclude <pattern>         Skip matching files
    --strip-components <n>      Strip n leading components from paths

EXAMPLES:
    zarc extract archive.tar.gz
    zarc extract archive.tar.gz /tmp/output
    zarc extract archive.tar.gz --include "*.txt"
    zarc extract archive.tar.gz --strip-components 1
```

---

Following this specification, zarc provides a consistent and user-friendly CLI.
