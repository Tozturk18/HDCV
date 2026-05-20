#ifndef HDCV_TYPES_H
#define HDCV_TYPES_H

#include <stddef.h>
#include <stdint.h>

#define HDCV_ERROR_MAX 256
#define HDCV_MAX_WAVEFORMS 64
#define HDCV_MAX_CHANNEL_NAME 64
#define HDCV_MAX_HEADER_TAIL 128

typedef struct {
    char *section;
    char *key;
    char *value;
} hdcv_metadata_entry;

typedef struct {
    char *raw_text;
    size_t raw_length;
    hdcv_metadata_entry *entries;
    size_t count;
    size_t capacity;
} hdcv_metadata;

typedef struct {
    int fd;
    const uint8_t *data;
    size_t size;
} hdcv_mmap;

typedef struct {
    uint64_t metadata_start_offset;
    uint64_t metadata_end_offset;
    uint64_t wave_data_offsets[HDCV_MAX_WAVEFORMS];
    uint64_t first_wave_data_offset;
    uint64_t waveform_block_bytes;
    uint64_t current_header_offset;
    uint64_t current_header_size_bytes;
    uint64_t current_matrix_offset;
    uint64_t current_matrix_bytes;
    uint32_t waveform_full_points;
    /* Physical full-cycle waveform-template blocks used to locate the matrix. */
    uint32_t waveform_count;
    uint32_t declared_channel_count;
    uint32_t numbered_wavespec_count;
    uint32_t channel_count;
    uint32_t samples_per_channel;
    uint32_t current_matrix_row_count;
    uint32_t points_per_scan;
    /* Compatibility alias for current_matrix_row_count. Matrix rows are interleaved by channel. */
    uint32_t scan_count;
    uint32_t scans_per_run;
    uint32_t run_count;
    double sample_rate_hz;
    double cvf_hz;
    double sample_period_s;
    double scan_interval_s;
    double scan_duration_s;
    double run_duration_s;
    double delay_between_runs_s;
    double v1_v;
    double v2_v;
    int has_voltage_bounds;
    int has_run_structure;
    int has_experiment_timing;
    char channel_names[HDCV_MAX_WAVEFORMS][HDCV_MAX_CHANNEL_NAME];
    unsigned char current_header_tail[HDCV_MAX_HEADER_TAIL];
    size_t current_header_tail_len;
} hdcv_layout;

typedef struct {
    char *path;
    hdcv_mmap mapped;
    hdcv_metadata metadata;
    hdcv_layout layout;
    char error[HDCV_ERROR_MAX];
} hdcv_reader;

#endif
