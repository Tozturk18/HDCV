#ifndef HDCV_ANALYSIS_H
#define HDCV_ANALYSIS_H

#include "hdcv_reader.h"

#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint32_t column_count;
    float min_value;
    float max_value;
} hdcv_overview_result;

int hdcv_analysis_copy_point_trace(
    const hdcv_reader *reader,
    uint32_t point_index,
    float *dst,
    size_t count,
    float *out_min,
    float *out_max
);

int hdcv_analysis_build_overview(
    const hdcv_reader *reader,
    uint32_t max_columns,
    float *dst,
    size_t dst_count,
    hdcv_overview_result *out_result
);

void hdcv_analysis_compute_min_max(
    const float *values,
    size_t count,
    float *out_min,
    float *out_max
);

#endif
