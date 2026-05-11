#include "hdcv_reader.h"

#include "hdcv_metadata.h"
#include "hdcv_utils.h"

#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct {
    uint64_t count_offset;
    uint64_t data_offset;
    uint32_t scan_count;
    double score;
} current_candidate;

static int map_file(hdcv_reader *reader, const char *path)
{
    struct stat st;

    reader->mapped.fd = open(path, O_RDONLY);
    if (reader->mapped.fd < 0) {
        hdcv_set_error(reader->error, sizeof(reader->error), "open(%s) failed: %s", path, strerror(errno));
        return 0;
    }

    if (fstat(reader->mapped.fd, &st) != 0) {
        hdcv_set_error(reader->error, sizeof(reader->error), "fstat(%s) failed: %s", path, strerror(errno));
        return 0;
    }
    if (st.st_size <= 0) {
        hdcv_set_error(reader->error, sizeof(reader->error), "Input file is empty.");
        return 0;
    }

    reader->mapped.size = (size_t)st.st_size;
    reader->mapped.data = (const uint8_t *)mmap(NULL, reader->mapped.size, PROT_READ, MAP_PRIVATE, reader->mapped.fd, 0);
    if (reader->mapped.data == MAP_FAILED) {
        reader->mapped.data = NULL;
        hdcv_set_error(reader->error, sizeof(reader->error), "mmap(%s) failed: %s", path, strerror(errno));
        return 0;
    }

    (void)madvise((void *)reader->mapped.data, reader->mapped.size, MADV_SEQUENTIAL);
    return 1;
}

static void unmap_file(hdcv_reader *reader)
{
    if (reader->mapped.data != NULL) {
        (void)munmap((void *)reader->mapped.data, reader->mapped.size);
        reader->mapped.data = NULL;
    }
    if (reader->mapped.fd >= 0) {
        (void)close(reader->mapped.fd);
        reader->mapped.fd = -1;
    }
    reader->mapped.size = 0U;
}

static double safe_fabs_diff(double a, double b)
{
    return fabs(a - b);
}

static double compute_correlation(const float *a, const float *b, size_t count)
{
    size_t i;
    double mean_a = 0.0;
    double mean_b = 0.0;
    double num = 0.0;
    double den_a = 0.0;
    double den_b = 0.0;

    for (i = 0; i < count; ++i) {
        mean_a += (double)a[i];
        mean_b += (double)b[i];
    }
    mean_a /= (double)count;
    mean_b /= (double)count;

    for (i = 0; i < count; ++i) {
        double da = (double)a[i] - mean_a;
        double db = (double)b[i] - mean_b;
        num += da * db;
        den_a += da * da;
        den_b += db * db;
    }

    if (den_a <= 0.0 || den_b <= 0.0) {
        return 0.0;
    }
    return num / sqrt(den_a * den_b);
}

static double compute_stddev(const float *values, size_t count)
{
    size_t i;
    double mean = 0.0;
    double var = 0.0;

    for (i = 0; i < count; ++i) {
        mean += (double)values[i];
    }
    mean /= (double)count;

    for (i = 0; i < count; ++i) {
        double delta = (double)values[i] - mean;
        var += delta * delta;
    }
    var /= (double)count;
    return sqrt(var);
}

static int metadata_to_layout(hdcv_reader *reader)
{
    double temp = 0.0;
    uint32_t u32 = 0U;
    hdcv_layout *layout = &reader->layout;
    uint64_t metadata_start_offset = layout->metadata_start_offset;
    uint64_t metadata_end_offset = layout->metadata_end_offset;

    memset(layout, 0, sizeof(*layout));
    layout->metadata_start_offset = metadata_start_offset;
    layout->metadata_end_offset = metadata_end_offset;

    if (!hdcv_metadata_get_double(&reader->metadata, "Core Cluster", "SampRate", &layout->sample_rate_hz)) {
        hdcv_set_error(reader->error, sizeof(reader->error), "Metadata is missing Core Cluster/SampRate.");
        return 0;
    }
    if (!hdcv_metadata_get_double(&reader->metadata, "Core Cluster", "CVF", &layout->cvf_hz)) {
        hdcv_set_error(reader->error, sizeof(reader->error), "Metadata is missing Core Cluster/CVF.");
        return 0;
    }
    if (!hdcv_metadata_get_uint32(&reader->metadata, "Setup Cluster", "Wavespecs.<size(s)>", &layout->waveform_count)) {
        layout->waveform_count = 1U;
    }
    if (!hdcv_metadata_get_uint32(&reader->metadata, "Setup Cluster", "Wavespecs 0.Data points per scan", &layout->points_per_scan)) {
        hdcv_set_error(reader->error, sizeof(reader->error), "Metadata is missing Setup Cluster/Wavespecs 0.Data points per scan.");
        return 0;
    }
    if (hdcv_metadata_get_double(&reader->metadata, "Setup Cluster", "Wavespecs 0.V1", &layout->v1_v) &&
        hdcv_metadata_get_double(&reader->metadata, "Setup Cluster", "Wavespecs 0.V2", &layout->v2_v)) {
        layout->has_voltage_bounds = 1;
    }
    if (hdcv_metadata_get_double(&reader->metadata, "Setup Cluster", "Wavespecs 0.Duration of scan (ms)", &temp)) {
        layout->scan_duration_s = temp / 1000.0;
    }
    if (hdcv_metadata_get_double(&reader->metadata, "Experiment control cluster", "Run duration", &layout->run_duration_s) &&
        hdcv_metadata_get_double(&reader->metadata, "Experiment control cluster", "Delay between runs", &layout->delay_between_runs_s) &&
        hdcv_metadata_get_uint32(&reader->metadata, "Experiment control cluster", "Runs", &layout->run_count)) {
        layout->has_experiment_timing = 1;
    }

    layout->sample_period_s = 1.0 / layout->sample_rate_hz;
    layout->scan_interval_s = 1.0 / layout->cvf_hz;
    temp = layout->sample_rate_hz / layout->cvf_hz;
    layout->waveform_full_points = (uint32_t)llround(temp);

    if (layout->has_experiment_timing) {
        u32 = (uint32_t)llround(layout->run_duration_s * layout->cvf_hz);
        if (u32 > 0U) {
            layout->scans_per_run = u32;
        }
    }
    return 1;
}

static int locate_waveform_blocks(hdcv_reader *reader)
{
    const uint8_t *data = reader->mapped.data;
    size_t size = reader->mapped.size;
    hdcv_layout *layout = &reader->layout;
    uint64_t search_start;
    uint64_t search_end;
    uint64_t off;
    uint64_t count_offset = 0U;
    uint32_t i;
    int found = 0;

    search_start = layout->metadata_end_offset;
    search_end = search_start + 256U;
    if (search_end > size) {
        search_end = size;
    }

    for (off = search_start + 8U; off + 4U <= search_end; ++off) {
        if (hdcv_read_be_u32(data + off) == layout->waveform_full_points) {
            double dt = hdcv_read_be_f64(data + off - 8U);
            if (safe_fabs_diff(dt, layout->sample_period_s) <= 1.0e-12) {
                count_offset = off;
                found = 1;
                break;
            }
        }
    }

    if (!found) {
        hdcv_set_error(reader->error, sizeof(reader->error), "Could not locate the first full-cycle waveform block.");
        return 0;
    }

    layout->first_wave_data_offset = count_offset + 4U;
    layout->wave_data_offsets[0] = layout->first_wave_data_offset;
    layout->waveform_block_bytes = (uint64_t)layout->waveform_full_points * 4U;
    if (layout->first_wave_data_offset + layout->waveform_block_bytes > size) {
        hdcv_set_error(reader->error, sizeof(reader->error), "First waveform block exceeds file size.");
        return 0;
    }

    for (i = 1U; i < layout->waveform_count; ++i) {
        uint64_t prev_end = layout->wave_data_offsets[i - 1U] + layout->waveform_block_bytes;
        uint64_t window_end = prev_end + 256U;
        int found_next = 0;
        if (window_end > size) {
            window_end = size;
        }
        for (off = prev_end + 8U; off + 4U <= window_end; ++off) {
            if (hdcv_read_be_u32(data + off) == layout->waveform_full_points) {
                double dt = hdcv_read_be_f64(data + off - 8U);
                if (safe_fabs_diff(dt, layout->sample_period_s) <= 1.0e-12) {
                    layout->wave_data_offsets[i] = off + 4U;
                    found_next = 1;
                    break;
                }
            }
        }
        if (!found_next) {
            hdcv_set_error(
                reader->error,
                sizeof(reader->error),
                "Could not locate waveform template block %u of %u.",
                i + 1U,
                layout->waveform_count
            );
            return 0;
        }
        if (layout->wave_data_offsets[i] + layout->waveform_block_bytes > size) {
            hdcv_set_error(reader->error, sizeof(reader->error), "Waveform block %u exceeds file size.", i);
            return 0;
        }
    }

    return 1;
}

static double score_current_candidate(
    const hdcv_reader *reader,
    uint64_t data_offset,
    uint32_t rows,
    uint32_t expected_total_scans
)
{
    const uint8_t *src;
    float *row0;
    float *row1;
    double corr;
    double std0;
    double std1;
    double score = 0.0;
    size_t row_bytes = (size_t)reader->layout.points_per_scan * 4U;

    row0 = (float *)malloc((size_t)reader->layout.points_per_scan * sizeof(*row0));
    row1 = (float *)malloc((size_t)reader->layout.points_per_scan * sizeof(*row1));
    if (row0 == NULL || row1 == NULL) {
        free(row0);
        free(row1);
        return -1.0e12;
    }

    src = reader->mapped.data + data_offset;
    hdcv_copy_be_f32_array(src, row0, reader->layout.points_per_scan);
    if (rows > 1U) {
        hdcv_copy_be_f32_array(src + row_bytes, row1, reader->layout.points_per_scan);
    } else {
        memcpy(row1, row0, (size_t)reader->layout.points_per_scan * sizeof(*row1));
    }

    std0 = compute_stddev(row0, reader->layout.points_per_scan);
    std1 = compute_stddev(row1, reader->layout.points_per_scan);
    corr = compute_correlation(row0, row1, reader->layout.points_per_scan);

    score += corr * 1000.0;
    score += fmin(std0, 1000.0) + fmin(std1, 1000.0);
    if (expected_total_scans > 0U) {
        if (rows == expected_total_scans) {
            score += 10000.0;
        } else {
            score -= fabs((double)rows - (double)expected_total_scans) * 10.0;
        }
    }
    if (std0 < 1.0e-6 || std1 < 1.0e-6) {
        score -= 5000.0;
    }

    free(row0);
    free(row1);
    return score;
}

static int locate_current_matrix(hdcv_reader *reader)
{
    const uint8_t *data = reader->mapped.data;
    size_t size = reader->mapped.size;
    hdcv_layout *layout = &reader->layout;
    uint64_t last_wave_end = layout->wave_data_offsets[layout->waveform_count - 1U] + layout->waveform_block_bytes;
    uint64_t search_end = last_wave_end + 512U;
    uint64_t off;
    uint64_t row_bytes = (uint64_t)layout->points_per_scan * 4U;
    uint32_t expected_total_scans = 0U;
    current_candidate best;
    int have_best = 0;

    memset(&best, 0, sizeof(best));

    if (layout->has_experiment_timing && layout->scans_per_run > 0U && layout->run_count > 0U) {
        expected_total_scans = layout->scans_per_run * layout->run_count;
    }

    if (search_end > size) {
        search_end = size;
    }

    for (off = last_wave_end; off + 4U <= search_end; ++off) {
        uint64_t data_offset;
        uint64_t remaining;
        current_candidate candidate;
        if (hdcv_read_be_u32(data + off) != layout->points_per_scan) {
            continue;
        }
        data_offset = off + 4U;
        if (data_offset >= size) {
            continue;
        }
        remaining = size - data_offset;
        if (remaining % row_bytes != 0U) {
            continue;
        }
        candidate.count_offset = off;
        candidate.data_offset = data_offset;
        candidate.scan_count = (uint32_t)(remaining / row_bytes);
        candidate.score = score_current_candidate(reader, data_offset, candidate.scan_count, expected_total_scans);
        candidate.score -= (double)(data_offset - last_wave_end) * 0.05;

        if (!have_best || candidate.score > best.score) {
            best = candidate;
            have_best = 1;
        }
    }

    if (!have_best) {
        hdcv_set_error(reader->error, sizeof(reader->error), "Could not locate the current matrix block.");
        return 0;
    }

    layout->current_header_offset = last_wave_end;
    layout->current_header_size_bytes = best.data_offset - last_wave_end;
    layout->current_matrix_offset = best.data_offset;
    layout->current_matrix_bytes = size - best.data_offset;
    layout->scan_count = best.scan_count;

    if (layout->current_header_size_bytes > HDCV_MAX_HEADER_TAIL) {
        layout->current_header_tail_len = HDCV_MAX_HEADER_TAIL;
        memcpy(
            layout->current_header_tail,
            data + (best.data_offset - HDCV_MAX_HEADER_TAIL),
            HDCV_MAX_HEADER_TAIL
        );
    } else {
        layout->current_header_tail_len = (size_t)layout->current_header_size_bytes;
        memcpy(layout->current_header_tail, data + layout->current_header_offset, layout->current_header_tail_len);
    }

    if (layout->current_header_size_bytes >= 12U) {
        uint64_t header_end = layout->current_matrix_offset;
        uint32_t header_scans_per_run = hdcv_read_be_u32(data + header_end - 12U);
        uint32_t header_run_count = hdcv_read_be_u32(data + header_end - 8U);
        uint32_t header_points = hdcv_read_be_u32(data + header_end - 4U);
        if (header_points == layout->points_per_scan &&
            header_scans_per_run > 0U &&
            header_run_count > 0U &&
            header_scans_per_run * header_run_count == layout->scan_count) {
            layout->scans_per_run = header_scans_per_run;
            layout->run_count = header_run_count;
            layout->has_run_structure = 1;
        }
    }

    if (!layout->has_run_structure &&
        layout->has_experiment_timing &&
        layout->scans_per_run > 0U &&
        layout->run_count > 0U &&
        layout->scans_per_run * layout->run_count == layout->scan_count) {
        layout->has_run_structure = 1;
    }

    return 1;
}

static int verify_waveform_active_segment(hdcv_reader *reader)
{
    hdcv_layout *layout = &reader->layout;
    const uint8_t *src;
    float *active;
    float *tail;
    double min_v;
    double max_v;
    double tail_mean;
    size_t i;
    size_t tail_count;

    active = (float *)malloc((size_t)layout->points_per_scan * sizeof(*active));
    if (active == NULL) {
        hdcv_set_error(reader->error, sizeof(reader->error), "Out of memory while validating waveform segment.");
        return 0;
    }
    src = reader->mapped.data + layout->first_wave_data_offset;
    hdcv_copy_be_f32_array(src, active, layout->points_per_scan);

    min_v = (double)active[0];
    max_v = (double)active[0];
    for (i = 1U; i < layout->points_per_scan; ++i) {
        if ((double)active[i] < min_v) {
            min_v = (double)active[i];
        }
        if ((double)active[i] > max_v) {
            max_v = (double)active[i];
        }
    }

    if (layout->has_voltage_bounds) {
        if (fabs(min_v - layout->v1_v) > 0.2 || fabs(max_v - layout->v2_v) > 0.2) {
            free(active);
            hdcv_set_error(
                reader->error,
                sizeof(reader->error),
                "Waveform active segment does not match metadata voltage bounds (min %.6f, max %.6f).",
                min_v,
                max_v
            );
            return 0;
        }
    }

    tail_count = (size_t)layout->waveform_full_points - layout->points_per_scan;
    if (tail_count > 0U) {
        tail = (float *)malloc(tail_count * sizeof(*tail));
        if (tail == NULL) {
            free(active);
            hdcv_set_error(reader->error, sizeof(reader->error), "Out of memory while validating waveform tail.");
            return 0;
        }
        hdcv_copy_be_f32_array(src + ((size_t)layout->points_per_scan * 4U), tail, tail_count);
        tail_mean = 0.0;
        for (i = 0U; i < tail_count; ++i) {
            tail_mean += (double)tail[i];
        }
        tail_mean /= (double)tail_count;
        free(tail);
        if (layout->has_voltage_bounds && fabs(tail_mean - layout->v1_v) > 0.1) {
            free(active);
            hdcv_set_error(
                reader->error,
                sizeof(reader->error),
                "Waveform tail mean %.6f does not match the expected hold voltage %.6f.",
                tail_mean,
                layout->v1_v
            );
            return 0;
        }
    }

    free(active);
    return 1;
}

int hdcv_reader_open(hdcv_reader *reader, const char *path)
{
    memset(reader, 0, sizeof(*reader));
    reader->mapped.fd = -1;
    hdcv_metadata_init(&reader->metadata);
    reader->path = hdcv_strdup(path);
    if (reader->path == NULL) {
        hdcv_set_error(reader->error, sizeof(reader->error), "Out of memory while storing input path.");
        return 0;
    }

    if (!map_file(reader, path)) {
        hdcv_reader_close(reader);
        return 0;
    }

    if (!hdcv_extract_metadata(
            reader->mapped.data,
            reader->mapped.size,
            &reader->metadata,
            &reader->layout.metadata_start_offset,
            &reader->layout.metadata_end_offset,
            reader->error,
            sizeof(reader->error))) {
        hdcv_reader_close(reader);
        return 0;
    }

    if (!metadata_to_layout(reader) ||
        !locate_waveform_blocks(reader) ||
        !locate_current_matrix(reader) ||
        !verify_waveform_active_segment(reader)) {
        hdcv_reader_close(reader);
        return 0;
    }

    return 1;
}

void hdcv_reader_close(hdcv_reader *reader)
{
    if (reader == NULL) {
        return;
    }

    free(reader->path);
    reader->path = NULL;

    hdcv_metadata_free(&reader->metadata);
    unmap_file(reader);
}

int hdcv_reader_copy_voltage(const hdcv_reader *reader, float *dst, size_t count)
{
    if (count < reader->layout.points_per_scan) {
        return 0;
    }
    hdcv_copy_be_f32_array(
        reader->mapped.data + reader->layout.first_wave_data_offset,
        dst,
        reader->layout.points_per_scan
    );
    return 1;
}

int hdcv_reader_copy_scan(const hdcv_reader *reader, uint32_t scan_index, float *dst, size_t count)
{
    uint64_t row_bytes;
    uint64_t offset;

    if (count < reader->layout.points_per_scan || scan_index >= reader->layout.scan_count) {
        return 0;
    }

    row_bytes = (uint64_t)reader->layout.points_per_scan * 4U;
    offset = reader->layout.current_matrix_offset + ((uint64_t)scan_index * row_bytes);
    hdcv_copy_be_f32_array(reader->mapped.data + offset, dst, reader->layout.points_per_scan);
    return 1;
}

int hdcv_reader_copy_scan_points(
    const hdcv_reader *reader,
    uint32_t scan_index,
    uint32_t point_start,
    uint32_t point_count,
    float *dst,
    size_t dst_count
)
{
    uint64_t row_bytes;
    uint64_t offset;

    if (scan_index >= reader->layout.scan_count ||
        point_start > reader->layout.points_per_scan ||
        point_count > reader->layout.points_per_scan - point_start ||
        dst_count < point_count) {
        return 0;
    }

    row_bytes = (uint64_t)reader->layout.points_per_scan * 4U;
    offset = reader->layout.current_matrix_offset +
        ((uint64_t)scan_index * row_bytes) +
        ((uint64_t)point_start * 4U);
    hdcv_copy_be_f32_array(reader->mapped.data + offset, dst, point_count);
    return 1;
}

int hdcv_reader_copy_scan_range(
    const hdcv_reader *reader,
    uint32_t start_scan,
    uint32_t scan_count,
    float *dst,
    size_t dst_count
)
{
    uint32_t i;

    if ((uint64_t)scan_count * reader->layout.points_per_scan > dst_count) {
        return 0;
    }
    if (start_scan >= reader->layout.scan_count || start_scan + scan_count > reader->layout.scan_count) {
        return 0;
    }

    for (i = 0U; i < scan_count; ++i) {
        if (!hdcv_reader_copy_scan(
                reader,
                start_scan + i,
                dst + ((size_t)i * reader->layout.points_per_scan),
                reader->layout.points_per_scan)) {
            return 0;
        }
    }
    return 1;
}

double hdcv_reader_within_scan_time_s(const hdcv_reader *reader, uint32_t point_index)
{
    return (double)point_index * reader->layout.sample_period_s;
}

double hdcv_reader_scan_time_sequence_s(const hdcv_reader *reader, uint32_t scan_index)
{
    return (double)scan_index * reader->layout.scan_interval_s;
}

double hdcv_reader_scan_time_experiment_s(const hdcv_reader *reader, uint32_t scan_index)
{
    if (reader->layout.has_run_structure &&
        reader->layout.has_experiment_timing &&
        reader->layout.scans_per_run > 0U) {
        uint32_t run_index = scan_index / reader->layout.scans_per_run;
        uint32_t scan_in_run = scan_index % reader->layout.scans_per_run;
        double run_block = reader->layout.run_duration_s + reader->layout.delay_between_runs_s;
        return ((double)run_index * run_block) + ((double)scan_in_run * reader->layout.scan_interval_s);
    }
    return hdcv_reader_scan_time_sequence_s(reader, scan_index);
}
