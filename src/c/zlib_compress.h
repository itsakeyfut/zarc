#ifndef ZLIB_COMPRESS_H
#define ZLIB_COMPRESS_H

#include <stddef.h>
#include <stdint.h>

// Compression format types
typedef enum {
    COMPRESS_FORMAT_GZIP = 0,
    COMPRESS_FORMAT_ZLIB = 1,
} CompressFormat;

// Compression result
typedef struct {
    uint8_t *data;        // Compressed data (caller must free)
    size_t size;          // Size of compressed data
    int error;            // Error code (0 = success)
} CompressResult;

// Compress data using zlib
// format: COMPRESS_FORMAT_GZIP or COMPRESS_FORMAT_ZLIB
// src: source data to compress
// src_len: length of source data
// Returns CompressResult with compressed data or error
// Caller is responsible for freeing result.data using free()
CompressResult zlib_compress(CompressFormat format, const uint8_t *src, size_t src_len);

#endif // ZLIB_COMPRESS_H
