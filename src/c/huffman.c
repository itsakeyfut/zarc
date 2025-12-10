// SPDX-License-Identifier: Apache-2.0
// Copyright 2025 itsakeyfut
//
// Huffman coding implementation in C for dynamic Deflate blocks
// Based on RFC 1951 and reference implementations (zlib, libdeflate)

#include "huffman.h"
#include <stdlib.h>
#include <string.h>
#include <assert.h>

// Helper structure for building Huffman tree
typedef struct {
    uint32_t freq;
    int symbol;
    int parent;
    int left;
    int right;
} HuffmanNode;

// Compare function for qsort (sort by frequency, then by symbol)
static int compare_nodes(const void *a, const void *b) {
    const HuffmanNode *na = (const HuffmanNode *)a;
    const HuffmanNode *nb = (const HuffmanNode *)b;

    if (na->freq != nb->freq) {
        return (na->freq > nb->freq) - (na->freq < nb->freq);
    }
    return (na->symbol > nb->symbol) - (na->symbol < nb->symbol);
}

// Bit reverse a value of given bit width
static uint16_t bit_reverse(uint16_t value, int bits) {
    uint16_t result = 0;
    for (int i = 0; i < bits; i++) {
        result = (result << 1) | (value & 1);
        value >>= 1;
    }
    return result;
}

// Build Huffman codes using package-merge algorithm
int huffman_build_codes(
    const uint32_t *frequencies,
    size_t num_symbols,
    int max_bits,
    HuffmanCode *codes
) {
    if (!frequencies || !codes || num_symbols == 0 || max_bits < 1 || max_bits > 15) {
        return -1;
    }

    // Initialize output codes
    memset(codes, 0, num_symbols * sizeof(HuffmanCode));

    // Count non-zero frequencies
    size_t num_used = 0;
    for (size_t i = 0; i < num_symbols; i++) {
        if (frequencies[i] > 0) {
            num_used++;
        }
    }

    // Handle edge cases
    if (num_used == 0) {
        // No symbols: create two dummy codes for decoder compatibility
        if (num_symbols >= 2) {
            codes[0].length = 1;
            codes[0].code = 0;
            codes[1].length = 1;
            codes[1].code = 1;
        } else if (num_symbols == 1) {
            codes[0].length = 1;
            codes[0].code = 0;
        }
        return 0;
    }

    if (num_used == 1) {
        // Single symbol: need dummy symbol for valid tree
        size_t used_idx = 0;
        for (size_t i = 0; i < num_symbols; i++) {
            if (frequencies[i] > 0) {
                used_idx = i;
                break;
            }
        }
        codes[used_idx].length = 1;
        codes[used_idx].code = 0;

        // Add dummy symbol
        size_t dummy_idx = (used_idx == 0) ? 1 : 0;
        if (dummy_idx < num_symbols) {
            codes[dummy_idx].length = 1;
            codes[dummy_idx].code = 1;
        }
        return 0;
    }

    // Allocate nodes for tree construction
    HuffmanNode *nodes = (HuffmanNode *)calloc(num_used * 2, sizeof(HuffmanNode));
    if (!nodes) {
        return -1;
    }

    // Initialize leaf nodes
    size_t node_idx = 0;
    for (size_t i = 0; i < num_symbols; i++) {
        if (frequencies[i] > 0) {
            nodes[node_idx].freq = frequencies[i];
            nodes[node_idx].symbol = (int)i;
            nodes[node_idx].parent = -1;
            nodes[node_idx].left = -1;
            nodes[node_idx].right = -1;
            node_idx++;
        }
    }

    // Sort nodes by frequency
    qsort(nodes, num_used, sizeof(HuffmanNode), compare_nodes);

    // Build Huffman tree using greedy algorithm
    size_t num_nodes = num_used;
    for (size_t i = 0; i < num_used - 1; i++) {
        // Find two nodes with smallest frequency
        // (already sorted, so take first two unprocessed)
        int min1 = -1, min2 = -1;
        uint32_t min1_freq = UINT32_MAX, min2_freq = UINT32_MAX;

        for (size_t j = 0; j < num_nodes; j++) {
            if (nodes[j].parent == -1) {
                if (nodes[j].freq < min1_freq) {
                    min2 = min1;
                    min2_freq = min1_freq;
                    min1 = (int)j;
                    min1_freq = nodes[j].freq;
                } else if (nodes[j].freq < min2_freq) {
                    min2 = (int)j;
                    min2_freq = nodes[j].freq;
                }
            }
        }

        // Create internal node
        nodes[num_nodes].freq = min1_freq + min2_freq;
        nodes[num_nodes].symbol = -1; // Internal node
        nodes[num_nodes].parent = -1;
        nodes[num_nodes].left = min1;
        nodes[num_nodes].right = min2;

        nodes[min1].parent = (int)num_nodes;
        nodes[min2].parent = (int)num_nodes;

        num_nodes++;
    }

    // Calculate code lengths by traversing from leaves to root
    uint8_t *lengths = (uint8_t *)calloc(num_symbols, sizeof(uint8_t));
    if (!lengths) {
        free(nodes);
        return -1;
    }

    // Calculate initial code lengths by traversing from leaves to root
    for (size_t i = 0; i < num_used; i++) {
        int depth = 0;
        int node = (int)i;
        while (nodes[node].parent != -1) {
            depth++;
            node = nodes[node].parent;
        }
        // Cap at max_bits initially
        if (depth > max_bits) {
            depth = max_bits;
        }
        lengths[nodes[i].symbol] = (uint8_t)depth;
    }

    // Rebalance to satisfy Kraft inequality (RFC 1951 §3.2.2)
    // Build histogram of code lengths
    uint32_t counts[MAX_BITS + 1] = {0};
    for (size_t i = 0; i < num_symbols; i++) {
        if (lengths[i] > 0 && lengths[i] <= (uint8_t)max_bits) {
            counts[lengths[i]]++;
        }
    }

    // Calculate capacity: sum of 2^(max_bits - len) * count[len]
    // Target capacity is 2^max_bits (Kraft: sum(2^-len) <= 1)
    const uint32_t target = (uint32_t)1 << max_bits;
    uint32_t used = 0;
    for (int len = 1; len <= max_bits; len++) {
        used += counts[len] << (max_bits - len);
    }

    // Rebalance if oversubscribed
    while (used > target) {
        // Find shortest length with available codes (< max_bits)
        int shortest = -1;
        for (int len = 1; len < max_bits; len++) {
            if (counts[len] > 0) {
                shortest = len;
                break;
            }
        }

        if (shortest == -1) {
            // All codes at max_bits - tree is already valid (or invalid input)
            break;
        }

        // Move two codes from shortest to shortest+1 (package-merge style)
        // This reduces capacity: 2*2^(max-L) -> 2^(max-(L+1)) = net reduction of 2^(max-L)
        if (counts[shortest] >= 2) {
            counts[shortest] -= 2;
            counts[shortest + 1] += 1;
            used -= (uint32_t)1 << (max_bits - shortest);
        } else if (counts[shortest] == 1) {
            // Only one code at this length; move it
            counts[shortest] -= 1;
            counts[shortest + 1] += 1;
            used -= (uint32_t)1 << (max_bits - shortest - 1);
        }
    }

    // Regenerate lengths[] from adjusted counts
    // Assign shorter codes to more frequent symbols (higher indices in sorted nodes)
    memset(lengths, 0, num_symbols);

    // Assign codes in frequency order: iterate nodes from high to low frequency
    // (nodes are sorted by frequency, so reverse iteration gives high freq first)
    for (int i = (int)num_used - 1; i >= 0; i--) {
        int sym = nodes[i].symbol;
        // Find shortest available length for this symbol
        for (int len = 1; len <= max_bits; len++) {
            if (counts[len] > 0) {
                lengths[sym] = (uint8_t)len;
                counts[len]--;
                break;
            }
        }
    }

    free(nodes);

    // Generate canonical Huffman codes from lengths
    // Step 1: Count codes of each length
    uint16_t bl_count[MAX_BITS + 1] = {0};
    for (size_t i = 0; i < num_symbols; i++) {
        if (lengths[i] > 0) {
            bl_count[lengths[i]]++;
        }
    }

    // Step 2: Find the numerical value of the smallest code for each length
    uint16_t next_code[MAX_BITS + 1] = {0};
    uint16_t code = 0;
    for (int bits = 1; bits <= MAX_BITS; bits++) {
        code = (code + bl_count[bits - 1]) << 1;
        next_code[bits] = code;
    }

    // Step 3: Assign codes to symbols
    for (size_t i = 0; i < num_symbols; i++) {
        int len = lengths[i];
        if (len > 0) {
            codes[i].length = (uint8_t)len;
            codes[i].code = bit_reverse(next_code[len], len);
            next_code[len]++;
        }
    }

    free(lengths);
    return 0;
}

// Bit writer helper
typedef struct {
    uint8_t *buffer;
    size_t size;
    size_t pos;
    uint32_t bit_buffer;
    int bit_count;
} BitWriter;

static void bit_writer_init(BitWriter *bw, uint8_t *buffer, size_t size) {
    bw->buffer = buffer;
    bw->size = size;
    bw->pos = 0;
    bw->bit_buffer = 0;
    bw->bit_count = 0;
}

static int bit_writer_write(BitWriter *bw, uint32_t value, int bits) {
    bw->bit_buffer |= value << bw->bit_count;
    bw->bit_count += bits;

    while (bw->bit_count >= 8) {
        if (bw->pos >= bw->size) {
            return -1; // Buffer overflow
        }
        bw->buffer[bw->pos++] = (uint8_t)(bw->bit_buffer & 0xFF);
        bw->bit_buffer >>= 8;
        bw->bit_count -= 8;
    }

    return 0;
}

static void bit_writer_finish(BitWriter *bw) {
    if (bw->bit_count > 0 && bw->pos < bw->size) {
        bw->buffer[bw->pos++] = (uint8_t)(bw->bit_buffer & 0xFF);
    }
}

// Run-length encode code lengths
static int rle_encode_lengths(
    const uint8_t *lengths,
    size_t num_lengths,
    uint8_t *symbols,
    uint8_t *extra,
    size_t *num_symbols
) {
    size_t out_idx = 0;
    size_t i = 0;

    while (i < num_lengths) {
        uint8_t len = lengths[i];

        if (len == 0) {
            // Count consecutive zeros
            size_t count = 1;
            while (i + count < num_lengths && lengths[i + count] == 0) {
                count++;
            }

            // Encode zeros using codes 17 or 18
            while (count > 0) {
                if (count >= 11) {
                    // Code 18: 11-138 zeros
                    size_t n = (count > 138) ? 138 : count;
                    symbols[out_idx] = 18;
                    extra[out_idx] = (uint8_t)(n - 11);
                    out_idx++;
                    count -= n;
                } else if (count >= 3) {
                    // Code 17: 3-10 zeros
                    size_t n = (count > 10) ? 10 : count;
                    symbols[out_idx] = 17;
                    extra[out_idx] = (uint8_t)(n - 3);
                    out_idx++;
                    count -= n;
                } else {
                    // Literal zeros
                    symbols[out_idx] = 0;
                    extra[out_idx] = 0;
                    out_idx++;
                    count--;
                }
            }
            i += (i + 1 < num_lengths && lengths[i] == 0) ? 1 : 1;
            while (i < num_lengths && lengths[i] == 0) i++;
        } else {
            // Non-zero length
            symbols[out_idx] = len;
            extra[out_idx] = 0;
            out_idx++;
            i++;

            // Check for repetitions
            size_t count = 0;
            while (i + count < num_lengths && lengths[i + count] == len) {
                count++;
            }

            // Encode repetitions using code 16
            while (count >= 3) {
                size_t n = (count > 6) ? 6 : count;
                symbols[out_idx] = 16;
                extra[out_idx] = (uint8_t)(n - 3);
                out_idx++;
                count -= n;
                i += n;
            }

            // Emit remaining as literals
            while (count > 0) {
                symbols[out_idx] = len;
                extra[out_idx] = 0;
                out_idx++;
                count--;
                i++;
            }
        }
    }

    *num_symbols = out_idx;
    return 0;
}

// Encode dynamic Huffman block header
int huffman_encode_dynamic_header(
    const HuffmanCode *lit_len_codes,
    const HuffmanCode *dist_codes,
    uint8_t *output,
    size_t output_size,
    size_t *bytes_written,
    int *bits_in_last_byte
) {
    if (!lit_len_codes || !dist_codes || !output || !bytes_written || !bits_in_last_byte) {
        return -1;
    }

    BitWriter bw;
    bit_writer_init(&bw, output, output_size);

    // Determine HLIT and HDIST (find last non-zero code length)
    int hlit = 286;
    while (hlit > 257 && lit_len_codes[hlit - 1].length == 0) {
        hlit--;
    }

    int hdist = 30;
    while (hdist > 1 && dist_codes[hdist - 1].length == 0) {
        hdist--;
    }

    // Collect all code lengths
    uint8_t *all_lengths = (uint8_t *)malloc((hlit + hdist) * sizeof(uint8_t));
    if (!all_lengths) {
        return -1;
    }

    for (int i = 0; i < hlit; i++) {
        all_lengths[i] = lit_len_codes[i].length;
    }
    for (int i = 0; i < hdist; i++) {
        all_lengths[hlit + i] = dist_codes[i].length;
    }

    // Run-length encode the lengths
    uint8_t *rle_symbols = (uint8_t *)malloc((hlit + hdist) * 2 * sizeof(uint8_t));
    uint8_t *rle_extra = (uint8_t *)malloc((hlit + hdist) * 2 * sizeof(uint8_t));
    size_t num_rle;

    if (!rle_symbols || !rle_extra) {
        free(all_lengths);
        free(rle_symbols);
        free(rle_extra);
        return -1;
    }

    rle_encode_lengths(all_lengths, hlit + hdist, rle_symbols, rle_extra, &num_rle);
    free(all_lengths);

    // Build Huffman codes for code length alphabet
    uint32_t cl_freq[19] = {0};
    for (size_t i = 0; i < num_rle; i++) {
        cl_freq[rle_symbols[i]]++;
    }

    HuffmanCode cl_codes[19];
    if (huffman_build_codes(cl_freq, 19, MAX_CL_BITS, cl_codes) != 0) {
        free(rle_symbols);
        free(rle_extra);
        return -1;
    }

    // Determine HCLEN
    const int code_length_order[19] = {
        16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15
    };

    int hclen = 19;
    while (hclen > 4 && cl_codes[code_length_order[hclen - 1]].length == 0) {
        hclen--;
    }

    // Write header
    if (bit_writer_write(&bw, hlit - 257, 5) != 0 ||
        bit_writer_write(&bw, hdist - 1, 5) != 0 ||
        bit_writer_write(&bw, hclen - 4, 4) != 0) {
        free(rle_symbols);
        free(rle_extra);
        return -1;
    }

    // Write code length code lengths
    for (int i = 0; i < hclen; i++) {
        if (bit_writer_write(&bw, cl_codes[code_length_order[i]].length, 3) != 0) {
            free(rle_symbols);
            free(rle_extra);
            return -1;
        }
    }

    // Write encoded lengths
    for (size_t i = 0; i < num_rle; i++) {
        uint8_t sym = rle_symbols[i];
        HuffmanCode code = cl_codes[sym];

        if (bit_writer_write(&bw, code.code, code.length) != 0) {
            free(rle_symbols);
            free(rle_extra);
            return -1;
        }

        // Write extra bits
        if (sym == 16) {
            if (bit_writer_write(&bw, rle_extra[i], 2) != 0) {
                free(rle_symbols);
                free(rle_extra);
                return -1;
            }
        } else if (sym == 17) {
            if (bit_writer_write(&bw, rle_extra[i], 3) != 0) {
                free(rle_symbols);
                free(rle_extra);
                return -1;
            }
        } else if (sym == 18) {
            if (bit_writer_write(&bw, rle_extra[i], 7) != 0) {
                free(rle_symbols);
                free(rle_extra);
                return -1;
            }
        }
    }

    free(rle_symbols);
    free(rle_extra);

    // Finish writing
    *bytes_written = bw.pos;
    *bits_in_last_byte = bw.bit_count;

    if (bw.bit_count > 0) {
        bit_writer_finish(&bw);
        *bytes_written = bw.pos;
    }

    return 0;
}
