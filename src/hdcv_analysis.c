#include "hdcv_analysis.h"

#include "hdcv_utils.h"

#include <float.h>
#include <stdlib.h>

int hdcv_analysis_copy_point_trace(
    const hdcv_reader *reader,
    uint32_t point_index,
    float *dst,
    size_t count,
    float *out_min,
    float *out_max
)
{
    uint64_t row_bytes;
    const uint8_t *src;
    uint32_t scan_index;
    float min_value;
    float max_value;

    if (point_index >= reader->layout.points_per_scan || count < reader->layout.scan_count) {
        return 0;
    }

    row_bytes = (uint64_t)reader->layout.points_per_scan * 4U;
    src = reader->mapped.data + reader->layout.current_matrix_offset + ((uint64_t)point_index * 4U);

    min_value = 0.0f;
    max_value = 0.0f;
    for (scan_index = 0U; scan_index < reader->layout.scan_count; ++scan_index) {
        float value = hdcv_read_be_f32(src + ((uint64_t)scan_index * row_bytes));
        dst[scan_index] = value;
        if (scan_index == 0U || value < min_value) {
            min_value = value;
        }
        if (scan_index == 0U || value > max_value) {
            max_value = value;
        }
    }

    if (out_min != NULL) {
        *out_min = min_value;
    }
    if (out_max != NULL) {
        *out_max = max_value;
    }
    return 1;
}

int hdcv_analysis_build_overview(
    const hdcv_reader *reader,
    uint32_t max_columns,
    float *dst,
    size_t dst_count,
    hdcv_overview_result *out_result
)
{
    uint32_t points_per_scan = reader->layout.points_per_scan;
    uint32_t column_count;
    uint64_t row_bytes;
    double *sums;
    const uint8_t *scan_ptr;
    float min_value = FLT_MAX;
    float max_value = -FLT_MAX;
    uint32_t column_index;

    if (max_columns == 0U) {
        return 0;
    }

    column_count = reader->layout.scan_count < max_columns ? reader->layout.scan_count : max_columns;
    if (reader->layout.waveform_count > 1U && reader->layout.scan_count > max_columns) {
        uint32_t phase_period = reader->layout.waveform_count;
        uint32_t scans_per_column = (reader->layout.scan_count + max_columns - 1U) / max_columns;
        uint32_t balanced_scans_per_column =
            ((scans_per_column + phase_period - 1U) / phase_period) * phase_period;
        if (balanced_scans_per_column > scans_per_column) {
            column_count = (reader->layout.scan_count + balanced_scans_per_column - 1U) / balanced_scans_per_column;
            if (column_count == 0U) {
                column_count = 1U;
            }
        }
    }
    if ((uint64_t)column_count * points_per_scan > dst_count) {
        return 0;
    }

    row_bytes = (uint64_t)points_per_scan * 4U;
    sums = (double *)malloc((size_t)points_per_scan * sizeof(*sums));
    if (sums == NULL) {
        return 0;
    }

    for (column_index = 0U; column_index < column_count; ++column_index) {
        uint32_t start_scan = (uint32_t)(((uint64_t)column_index * reader->layout.scan_count) / column_count);
        uint32_t end_scan = (uint32_t)(((uint64_t)(column_index + 1U) * reader->layout.scan_count) / column_count);
        uint32_t scan_index;
        uint32_t point_index;
        double inv_count;

        if (end_scan <= start_scan) {
            end_scan = start_scan + 1U;
        }

        for (point_index = 0U; point_index < points_per_scan; ++point_index) {
            sums[point_index] = 0.0;
        }

        scan_ptr = reader->mapped.data + reader->layout.current_matrix_offset + ((uint64_t)start_scan * row_bytes);
        for (scan_index = start_scan; scan_index < end_scan; ++scan_index) {
            const uint8_t *row_ptr = scan_ptr;
            for (point_index = 0U; point_index < points_per_scan; ++point_index) {
                sums[point_index] += (double)hdcv_read_be_f32(row_ptr + ((uint64_t)point_index * 4U));
            }
            scan_ptr += row_bytes;
        }

        inv_count = 1.0 / (double)(end_scan - start_scan);
        for (point_index = 0U; point_index < points_per_scan; ++point_index) {
            float value = (float)(sums[point_index] * inv_count);
            dst[(size_t)point_index * column_count + column_index] = value;
            if (value < min_value) {
                min_value = value;
            }
            if (value > max_value) {
                max_value = value;
            }
        }
    }

    free(sums);

    if (out_result != NULL) {
        out_result->column_count = column_count;
        out_result->min_value = min_value;
        out_result->max_value = max_value;
    }
    return 1;
}

void hdcv_analysis_compute_min_max(
    const float *values,
    size_t count,
    float *out_min,
    float *out_max
)
{
    size_t i;
    float min_value = 0.0f;
    float max_value = 0.0f;

    for (i = 0U; i < count; ++i) {
        float value = values[i];
        if (i == 0U || value < min_value) {
            min_value = value;
        }
        if (i == 0U || value > max_value) {
            max_value = value;
        }
    }

    if (out_min != NULL) {
        *out_min = min_value;
    }
    if (out_max != NULL) {
        *out_max = max_value;
    }
}
