#include "hdcv_analysis.h"

#include "hdcv_utils.h"

#include <float.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#ifndef M_SQRT2
#define M_SQRT2 1.41421356237309504880
#endif

#define HDCV_SCAN_INDEX_NOT_FOUND UINT32_MAX

typedef struct {
    double b0;
    double b1;
    double b2;
    double a1;
    double a2;
} hdcv_biquad;

static hdcv_biquad hdcv_analysis_butterworth_lowpass(double cutoff_hz, double sample_rate_hz)
{
    double k = tan(M_PI * cutoff_hz / sample_rate_hz);
    double norm = 1.0 / (1.0 + (M_SQRT2 * k) + (k * k));
    hdcv_biquad c;
    c.b0 = k * k * norm;
    c.b1 = 2.0 * c.b0;
    c.b2 = c.b0;
    c.a1 = 2.0 * ((k * k) - 1.0) * norm;
    c.a2 = (1.0 - (M_SQRT2 * k) + (k * k)) * norm;
    return c;
}

static hdcv_biquad hdcv_analysis_butterworth_highpass(double cutoff_hz, double sample_rate_hz)
{
    double k = tan(M_PI * cutoff_hz / sample_rate_hz);
    double norm = 1.0 / (1.0 + (M_SQRT2 * k) + (k * k));
    hdcv_biquad c;
    c.b0 = norm;
    c.b1 = -2.0 * c.b0;
    c.b2 = c.b0;
    c.a1 = 2.0 * ((k * k) - 1.0) * norm;
    c.a2 = (1.0 - (M_SQRT2 * k) + (k * k)) * norm;
    return c;
}

static void hdcv_analysis_apply_biquad_forward(const float *src, float *dst, size_t count, hdcv_biquad c)
{
    double x1 = 0.0;
    double x2 = 0.0;
    double y1 = 0.0;
    double y2 = 0.0;

    for (size_t i = 0U; i < count; ++i) {
        double x0 = (double)src[i];
        double y0 = (c.b0 * x0) + (c.b1 * x1) + (c.b2 * x2) - (c.a1 * y1) - (c.a2 * y2);
        dst[i] = (float)y0;
        x2 = x1;
        x1 = x0;
        y2 = y1;
        y1 = y0;
    }
}

static void hdcv_analysis_reverse_float_array(float *values, size_t count)
{
    for (size_t i = 0U; i < count / 2U; ++i) {
        float tmp = values[i];
        values[i] = values[count - 1U - i];
        values[count - 1U - i] = tmp;
    }
}

static void hdcv_analysis_apply_biquad_zero_phase(float *values, float *scratch, size_t count, hdcv_biquad c)
{
    hdcv_analysis_apply_biquad_forward(values, scratch, count, c);
    hdcv_analysis_reverse_float_array(scratch, count);
    hdcv_analysis_apply_biquad_forward(scratch, values, count, c);
    hdcv_analysis_reverse_float_array(values, count);
}

static int hdcv_analysis_voltage_step_direction(float previous, float current, float epsilon)
{
    float delta = current - previous;
    if (delta > epsilon) {
        return 1;
    }
    if (delta < -epsilon) {
        return -1;
    }
    return 0;
}

static void hdcv_analysis_smooth_cv_segment(
    const float *source,
    float *destination,
    size_t start_index,
    size_t end_index,
    size_t radius
)
{
    if (end_index <= start_index) {
        return;
    }

    for (size_t index = start_index; index < end_index; ++index) {
        size_t left = (index > start_index + radius) ? index - radius : start_index;
        size_t right = (index + radius < end_index) ? index + radius : end_index - 1U;
        double sum = 0.0;
        double weight_sum = 0.0;

        for (size_t neighbor = left; neighbor <= right; ++neighbor) {
            size_t distance = (neighbor > index) ? neighbor - index : index - neighbor;
            double weight = (double)(radius + 1U - distance);
            sum += (double)source[neighbor] * weight;
            weight_sum += weight;
        }

        destination[index] = (weight_sum > 0.0) ? (float)(sum / weight_sum) : source[index];
    }
}

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

uint32_t hdcv_analysis_phase_aligned_background_index(
    uint32_t raw_background_index,
    uint32_t scan_index,
    uint32_t scan_count,
    uint32_t phase_period
)
{
    uint32_t period = phase_period == 0U ? 1U : phase_period;
    uint32_t raw_index;
    uint32_t target_mod;
    double nearest_period;
    int64_t nearest;
    int64_t max_scan;

    if (scan_count == 0U) {
        return 0U;
    }

    raw_index = raw_background_index < scan_count ? raw_background_index : scan_count - 1U;
    if (period <= 1U) {
        return raw_index;
    }

    target_mod = scan_index % period;
    nearest_period = round(((double)raw_index - (double)target_mod) / (double)period);
    nearest = (int64_t)target_mod + ((int64_t)llround(nearest_period) * (int64_t)period);
    max_scan = (int64_t)scan_count - 1;
    if (nearest < 0) {
        nearest = 0;
    }
    if (nearest > max_scan) {
        nearest = max_scan;
    }

    while ((uint32_t)nearest > scan_index && nearest - (int64_t)period >= 0) {
        nearest -= (int64_t)period;
    }
    if (nearest < 0) {
        nearest = 0;
    }
    if (nearest > max_scan) {
        nearest = max_scan;
    }
    return (uint32_t)nearest;
}

uint32_t hdcv_analysis_nearest_scan_index_for_phase(
    uint32_t scan_index,
    uint32_t scan_count,
    uint32_t phase_index,
    uint32_t phase_period
)
{
    uint32_t period = phase_period == 0U ? 1U : phase_period;
    uint32_t target_phase = phase_index % period;
    int64_t candidate;
    int64_t max_scan;

    if (scan_count == 0U) {
        return 0U;
    }
    if (period <= 1U || scan_count <= 1U) {
        return scan_index < scan_count ? scan_index : scan_count - 1U;
    }
    if (target_phase >= scan_count) {
        target_phase = 0U;
    }

    candidate = (int64_t)target_phase +
        ((int64_t)llround(((double)scan_index - (double)target_phase) / (double)period) * (int64_t)period);
    max_scan = (int64_t)scan_count - 1;
    while (candidate < 0) {
        candidate += (int64_t)period;
    }
    while (candidate > max_scan) {
        candidate -= (int64_t)period;
    }
    if (candidate < 0) {
        candidate = 0;
    }
    if (candidate > max_scan) {
        candidate = max_scan;
    }
    return (uint32_t)candidate;
}

uint32_t hdcv_analysis_first_phase_scan_in_range(
    uint32_t min_scan,
    uint32_t max_scan,
    uint32_t phase_index,
    uint32_t phase_period
)
{
    uint32_t period = phase_period == 0U ? 1U : phase_period;
    uint32_t target_phase = phase_index % period;
    uint32_t remainder;
    uint32_t delta;

    if (max_scan < min_scan) {
        return HDCV_SCAN_INDEX_NOT_FOUND;
    }
    if (period <= 1U) {
        return min_scan;
    }
    remainder = min_scan % period;
    delta = (target_phase + period - remainder) % period;
    if (min_scan + delta > max_scan) {
        return HDCV_SCAN_INDEX_NOT_FOUND;
    }
    return min_scan + delta;
}

uint32_t hdcv_analysis_phase_sample_count_in_range(
    uint32_t min_scan,
    uint32_t max_scan,
    uint32_t phase_index,
    uint32_t phase_period
)
{
    uint32_t period = phase_period == 0U ? 1U : phase_period;
    uint32_t first_scan = hdcv_analysis_first_phase_scan_in_range(min_scan, max_scan, phase_index, period);

    if (first_scan == HDCV_SCAN_INDEX_NOT_FOUND) {
        return 0U;
    }
    if (period <= 1U) {
        return max_scan - first_scan + 1U;
    }
    return ((max_scan - first_scan) / period) + 1U;
}

float hdcv_analysis_average_trace_in_phase_window(
    const float *trace,
    uint32_t scan_count,
    uint32_t center_scan,
    uint32_t phase_index,
    uint32_t phase_period,
    uint32_t half_window
)
{
    uint32_t period = phase_period == 0U ? 1U : phase_period;
    uint32_t center = hdcv_analysis_nearest_scan_index_for_phase(center_scan, scan_count, phase_index, period);
    int64_t start = (int64_t)center - ((int64_t)half_window * (int64_t)period);
    int64_t end = (int64_t)center + ((int64_t)half_window * (int64_t)period);
    double sum = 0.0;
    uint32_t count = 0U;

    if (trace == NULL || scan_count == 0U) {
        return 0.0f;
    }

    while (start < 0) {
        start += (int64_t)period;
    }
    while (end >= (int64_t)scan_count) {
        end -= (int64_t)period;
    }

    for (int64_t scan_index = start; scan_index <= end; scan_index += (int64_t)period) {
        if (scan_index >= 0 && scan_index < (int64_t)scan_count) {
            sum += (double)trace[scan_index];
            count += 1U;
        }
    }

    if (count == 0U) {
        return trace[center];
    }
    return (float)(sum / (double)count);
}

void hdcv_analysis_apply_phase_aligned_background_to_trace(
    const float *source,
    float *destination,
    uint32_t scan_count,
    uint32_t raw_background_index,
    uint32_t phase_period
)
{
    if (source == NULL || destination == NULL) {
        return;
    }
    for (uint32_t scan_index = 0U; scan_index < scan_count; ++scan_index) {
        uint32_t aligned_index = hdcv_analysis_phase_aligned_background_index(
            raw_background_index,
            scan_index,
            scan_count,
            phase_period
        );
        destination[scan_index] = source[scan_index] - source[aligned_index];
    }
}

int hdcv_analysis_apply_butterworth_bandpass(float *values, size_t count, double sample_rate_hz)
{
    double nyquist = sample_rate_hz * 0.5;
    double low_hz = 0.01;
    double high_hz = fmin(2.0, nyquist * 0.80);
    float *scratch;

    if (values == NULL || count < 8U || sample_rate_hz <= 0.0 || high_hz <= low_hz) {
        return 0;
    }

    scratch = (float *)malloc(count * sizeof(*scratch));
    if (scratch == NULL) {
        return 0;
    }

    hdcv_analysis_apply_biquad_zero_phase(
        values,
        scratch,
        count,
        hdcv_analysis_butterworth_highpass(low_hz, sample_rate_hz)
    );
    hdcv_analysis_apply_biquad_zero_phase(
        values,
        scratch,
        count,
        hdcv_analysis_butterworth_lowpass(high_hz, sample_rate_hz)
    );
    free(scratch);
    return 1;
}

int hdcv_analysis_apply_butterworth_bandpass_by_phase(
    float *values,
    size_t count,
    uint32_t phase_period,
    double scan_rate_hz
)
{
    uint32_t period = phase_period == 0U ? 1U : phase_period;
    int filtered = 0;

    if (values == NULL) {
        return 0;
    }
    if (period <= 1U) {
        return hdcv_analysis_apply_butterworth_bandpass(values, count, scan_rate_hz);
    }

    for (uint32_t phase = 0U; phase < period; ++phase) {
        size_t phase_count = (phase < count) ? (((count - 1U - phase) / period) + 1U) : 0U;
        float *phase_values;
        size_t j = 0U;

        if (phase_count == 0U) {
            continue;
        }

        phase_values = (float *)malloc(phase_count * sizeof(*phase_values));
        if (phase_values == NULL) {
            continue;
        }
        for (size_t scan_index = phase; scan_index < count; scan_index += period) {
            phase_values[j++] = values[scan_index];
        }

        if (hdcv_analysis_apply_butterworth_bandpass(phase_values, phase_count, scan_rate_hz / (double)period)) {
            j = 0U;
            for (size_t scan_index = phase; scan_index < count; scan_index += period) {
                values[scan_index] = phase_values[j++];
            }
            filtered = 1;
        }
        free(phase_values);
    }

    return filtered;
}

void hdcv_analysis_background_subtracted_cv_denoise(float *values, const float *voltage, size_t count)
{
    static const size_t radius = 2U;
    float *source;
    float voltage_min;
    float voltage_max;
    float epsilon;
    size_t segment_start;
    int segment_direction;

    if (values == NULL || voltage == NULL || count < ((radius * 2U) + 3U)) {
        return;
    }

    source = (float *)malloc(count * sizeof(*source));
    if (source == NULL) {
        return;
    }
    memcpy(source, values, count * sizeof(*source));

    voltage_min = voltage[0];
    voltage_max = voltage[0];
    for (size_t index = 1U; index < count; ++index) {
        if (voltage[index] < voltage_min) {
            voltage_min = voltage[index];
        }
        if (voltage[index] > voltage_max) {
            voltage_max = voltage[index];
        }
    }
    epsilon = fmaxf(1.0e-6f, (voltage_max - voltage_min) * 1.0e-5f);

    segment_start = 0U;
    segment_direction = 0;
    for (size_t index = 1U; index < count; ++index) {
        int direction = hdcv_analysis_voltage_step_direction(voltage[index - 1U], voltage[index], epsilon);
        if (direction == 0) {
            continue;
        }
        if (segment_direction != 0 && direction != segment_direction && index > segment_start + (radius * 2U)) {
            hdcv_analysis_smooth_cv_segment(source, values, segment_start, index, radius);
            segment_start = index - 1U;
        }
        segment_direction = direction;
    }
    hdcv_analysis_smooth_cv_segment(source, values, segment_start, count, radius);

    free(source);
}
