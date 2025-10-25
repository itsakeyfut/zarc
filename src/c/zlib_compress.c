#include "zlib_compress.h"
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

CompressResult zlib_compress(CompressFormat format, const uint8_t *src, size_t src_len) {
    CompressResult result = {0};

    // Allow empty data (will produce header + footer only)
    if (!src && src_len > 0) {
        result.error = -1; // Invalid: null pointer with non-zero length
        return result;
    }

    // For empty data, use a dummy pointer to avoid passing NULL to zlib
    const uint8_t *actual_src = (src_len == 0) ? (const uint8_t *)"" : src;

    // Estimate output size
    // For gzip: compressBound() + extra space for gzip header (10 bytes) + footer (8 bytes)
    // For zlib: compressBound() + extra space for zlib header (2 bytes) + footer (4 bytes)
    size_t max_size = compressBound(src_len) + 32; // Add extra buffer for headers/footers

    uint8_t *dest = (uint8_t *)malloc(max_size);
    if (!dest) {
        result.error = -2; // Memory allocation failed
        return result;
    }

    // Initialize zlib stream
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    stream.next_in = (Bytef *)actual_src;
    stream.avail_in = src_len;
    stream.next_out = dest;
    // zlib uses uInt for avail_out; bound to 32-bit.
    stream.avail_out = (uInt)((max_size > 0xFFFFFFFFu) ? 0xFFFFFFFFu : (uInt)max_size);

    // Initialize deflate
    // windowBits: 15 for zlib, 15+16 for gzip
    int window_bits = (format == COMPRESS_FORMAT_GZIP) ? (15 + 16) : 15;
    int ret = deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED,
                          window_bits, 8, Z_DEFAULT_STRATEGY);

    if (ret != Z_OK) {
        free(dest);
        result.error = ret;
        return result;
    }

    // Compress with growth to handle large outputs
    size_t cap = max_size;
    for (;;) {
        ret = deflate(&stream, Z_FINISH);
        if (ret == Z_STREAM_END) break;
        if (ret == Z_OK || ret == Z_BUF_ERROR) {
            // Grow output buffer and continue
            const size_t used = (size_t)stream.total_out;
            size_t new_cap = cap * 2;
            if (new_cap < used + 1) new_cap = used + 1;
            uint8_t *new_dest = (uint8_t *)realloc(dest, new_cap);
            if (!new_dest) {
                deflateEnd(&stream);
                free(dest);
                result.error = -2; // OOM
                return result;
            }
            dest = new_dest;
            cap = new_cap;
            stream.next_out = (Bytef *)(dest + used);
            size_t remaining = cap - used;
            stream.avail_out = (uInt)((remaining > 0xFFFFFFFFu) ? 0xFFFFFFFFu : (uInt)remaining);
            continue;
        }
        // Hard failure
        deflateEnd(&stream);
        free(dest);
        result.error = ret;
        return result;
    }

    // Get actual compressed size
    size_t compressed_size = stream.total_out;

    // Clean up
    deflateEnd(&stream);

    // Optionally shrink buffer to actual size
    uint8_t *final_dest = (uint8_t *)realloc(dest, compressed_size);
    if (final_dest) {
        dest = final_dest;
    }

    result.data = dest;
    result.size = compressed_size;
    result.error = 0;

    return result;
}

void zlib_free(void *ptr) {
    free(ptr);
}
