/* SPDX-License-Identifier: Apache-2.0 */
/*
 * Copyright 2025 itsakeyfut
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifndef ZLIB_COMPRESS_H
#define ZLIB_COMPRESS_H

#ifdef __cplusplus
extern "C" {
#endif

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

// Decompress data using zlib
// format: COMPRESS_FORMAT_GZIP or COMPRESS_FORMAT_ZLIB
// src: compressed data to decompress
// src_len: length of compressed data
// Returns CompressResult with decompressed data or error
// Caller is responsible for freeing result.data using free()
CompressResult zlib_decompress(CompressFormat format, const uint8_t *src, size_t src_len);

// Free a buffer allocated by this library (FFI-safe).
void zlib_free(void *ptr);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // ZLIB_COMPRESS_H
