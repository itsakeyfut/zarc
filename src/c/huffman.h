// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 itsakeyfut
//
// Huffman coding implementation in C for dynamic Deflate blocks
// This provides a reference implementation that's known to work correctly

#ifndef ZARC_HUFFMAN_H
#define ZARC_HUFFMAN_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Maximum code lengths
#define MAX_BITS 15
#define MAX_CL_BITS 7

// Huffman code structure
typedef struct {
    uint16_t code;   // The Huffman code (bit-reversed for LSB-first output)
    uint8_t length;  // Number of bits in the code
} HuffmanCode;

// Build canonical Huffman codes from symbol frequencies
//
// Parameters:
//   frequencies: Array of symbol frequencies (input)
//   num_symbols: Number of symbols in the alphabet
//   max_bits: Maximum code length allowed
//   codes: Output array of Huffman codes (must be pre-allocated)
//
// Returns: 0 on success, -1 on error
int huffman_build_codes(
    const uint32_t *frequencies,
    size_t num_symbols,
    int max_bits,
    HuffmanCode *codes
);

// Encode dynamic Huffman block header
//
// This encodes the code length tables according to RFC 1951 Section 3.2.7
//
// Parameters:
//   lit_len_codes: Literal/length Huffman codes (array of 286)
//   dist_codes: Distance Huffman codes (array of 30)
//   output: Output buffer for encoded data
//   output_size: Size of output buffer
//   bytes_written: Number of bytes written to output
//   bits_in_last_byte: Number of valid bits in the last byte (0-7)
//
// Returns: 0 on success, -1 on error
int huffman_encode_dynamic_header(
    const HuffmanCode *lit_len_codes,
    const HuffmanCode *dist_codes,
    uint8_t *output,
    size_t output_size,
    size_t *bytes_written,
    int *bits_in_last_byte
);

#ifdef __cplusplus
}
#endif

#endif // ZARC_HUFFMAN_H
