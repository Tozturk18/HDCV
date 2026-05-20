#ifndef HDCV_READER_H
#define HDCV_READER_H

#include "hdcv_types.h"

#include <stddef.h>
#include <stdint.h>

int hdcv_reader_open(hdcv_reader *reader, const char *path);
void hdcv_reader_close(hdcv_reader *reader);
int hdcv_reader_copy_voltage(const hdcv_reader *reader, float *dst, size_t count);
int hdcv_reader_copy_voltage_for_channel(
    const hdcv_reader *reader,
    uint32_t channel_index,
    float *dst,
    size_t count
);
int hdcv_reader_copy_scan(const hdcv_reader *reader, uint32_t scan_index, float *dst, size_t count);
int hdcv_reader_copy_channel_sample(
    const hdcv_reader *reader,
    uint32_t channel_index,
    uint32_t sample_index,
    float *dst,
    size_t count
);
int hdcv_reader_copy_scan_points(
    const hdcv_reader *reader,
    uint32_t scan_index,
    uint32_t point_start,
    uint32_t point_count,
    float *dst,
    size_t dst_count
);
int hdcv_reader_copy_scan_range(
    const hdcv_reader *reader,
    uint32_t start_scan,
    uint32_t scan_count,
    float *dst,
    size_t dst_count
);
double hdcv_reader_within_scan_time_s(const hdcv_reader *reader, uint32_t point_index);
uint32_t hdcv_reader_row_index_for_channel_sample(
    const hdcv_reader *reader,
    uint32_t channel_index,
    uint32_t sample_index
);
uint32_t hdcv_reader_sample_index_for_row(const hdcv_reader *reader, uint32_t row_index);
uint32_t hdcv_reader_channel_index_for_row(const hdcv_reader *reader, uint32_t row_index);
uint32_t hdcv_reader_nearest_row_for_channel_time(
    const hdcv_reader *reader,
    uint32_t channel_index,
    double time_s
);
double hdcv_reader_sample_time_sequence_s(const hdcv_reader *reader, uint32_t sample_index);
double hdcv_reader_scan_time_sequence_s(const hdcv_reader *reader, uint32_t scan_index);
double hdcv_reader_scan_time_experiment_s(const hdcv_reader *reader, uint32_t scan_index);
const char *hdcv_reader_channel_name(const hdcv_reader *reader, uint32_t channel_index);

#endif
