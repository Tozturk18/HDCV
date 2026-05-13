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

uint32_t hdcv_analysis_phase_aligned_background_index(
    uint32_t raw_background_index,
    uint32_t scan_index,
    uint32_t scan_count,
    uint32_t phase_period
);

uint32_t hdcv_analysis_nearest_scan_index_for_phase(
    uint32_t scan_index,
    uint32_t scan_count,
    uint32_t phase_index,
    uint32_t phase_period
);

uint32_t hdcv_analysis_first_phase_scan_in_range(
    uint32_t min_scan,
    uint32_t max_scan,
    uint32_t phase_index,
    uint32_t phase_period
);

uint32_t hdcv_analysis_phase_sample_count_in_range(
    uint32_t min_scan,
    uint32_t max_scan,
    uint32_t phase_index,
    uint32_t phase_period
);

float hdcv_analysis_average_trace_in_phase_window(
    const float *trace,
    uint32_t scan_count,
    uint32_t center_scan,
    uint32_t phase_index,
    uint32_t phase_period,
    uint32_t half_window
);

void hdcv_analysis_apply_phase_aligned_background_to_trace(
    const float *source,
    float *destination,
    uint32_t scan_count,
    uint32_t raw_background_index,
    uint32_t phase_period
);

int hdcv_analysis_apply_butterworth_bandpass(
    float *values,
    size_t count,
    double sample_rate_hz
);

int hdcv_analysis_apply_butterworth_bandpass_by_phase(
    float *values,
    size_t count,
    uint32_t phase_period,
    double scan_rate_hz
);

void hdcv_analysis_background_subtracted_cv_denoise(
    float *values,
    const float *voltage,
    size_t count
);

#endif
