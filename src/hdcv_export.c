#include "hdcv_export.h"

#include "hdcv_reader.h"
#include "hdcv_utils.h"

#include <errno.h>
#include <inttypes.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

static void print_json_string(FILE *out, const char *text)
{
    const unsigned char *p = (const unsigned char *)text;
    fputc('"', out);
    while (*p != '\0') {
        if (*p == '"' || *p == '\\') {
            fputc('\\', out);
            fputc((int)*p, out);
        } else if (*p == '\n') {
            fputs("\\n", out);
        } else if (*p == '\r') {
            fputs("\\r", out);
        } else if (*p == '\t') {
            fputs("\\t", out);
        } else if (*p < 32U) {
            (void)fprintf(out, "\\u%04x", (unsigned int)*p);
        } else {
            fputc((int)*p, out);
        }
        ++p;
    }
    fputc('"', out);
}

int hdcv_print_info(const hdcv_reader *reader, FILE *out, int as_json)
{
    const hdcv_layout *layout = &reader->layout;

    if (as_json) {
        fputs("{\n", out);
        fputs("  \"file\": ", out);
        print_json_string(out, reader->path);
        fputs(",\n", out);
        fprintf(out, "  \"file_size_bytes\": %zu,\n", reader->mapped.size);
        fprintf(out, "  \"metadata_start_offset\": %" PRIu64 ",\n", layout->metadata_start_offset);
        fprintf(out, "  \"metadata_end_offset\": %" PRIu64 ",\n", layout->metadata_end_offset);
        fprintf(out, "  \"first_wave_data_offset\": %" PRIu64 ",\n", layout->first_wave_data_offset);
        fprintf(out, "  \"current_header_offset\": %" PRIu64 ",\n", layout->current_header_offset);
        fprintf(out, "  \"current_matrix_offset\": %" PRIu64 ",\n", layout->current_matrix_offset);
        fprintf(out, "  \"waveform_count\": %" PRIu32 ",\n", layout->waveform_count);
        fprintf(out, "  \"waveform_full_points\": %" PRIu32 ",\n", layout->waveform_full_points);
        fprintf(out, "  \"points_per_scan\": %" PRIu32 ",\n", layout->points_per_scan);
        fprintf(out, "  \"scan_count\": %" PRIu32 ",\n", layout->scan_count);
        fprintf(out, "  \"sample_rate_hz\": %.9f,\n", layout->sample_rate_hz);
        fprintf(out, "  \"cvf_hz\": %.9f,\n", layout->cvf_hz);
        fprintf(out, "  \"scan_interval_s\": %.9f,\n", layout->scan_interval_s);
        fprintf(out, "  \"scan_duration_s\": %.9f,\n", layout->scan_duration_s);
        fprintf(out, "  \"run_count\": %" PRIu32 ",\n", layout->run_count);
        fprintf(out, "  \"scans_per_run\": %" PRIu32 ",\n", layout->scans_per_run);
        fprintf(out, "  \"delay_between_runs_s\": %.9f,\n", layout->delay_between_runs_s);
        fprintf(out, "  \"has_run_structure\": %s,\n", layout->has_run_structure ? "true" : "false");
        fprintf(out, "  \"has_experiment_timing\": %s,\n", layout->has_experiment_timing ? "true" : "false");
        if (layout->has_voltage_bounds) {
            fprintf(out, "  \"v1_v\": %.9f,\n", layout->v1_v);
            fprintf(out, "  \"v2_v\": %.9f,\n", layout->v2_v);
        }
        fputs("  \"wave_data_offsets\": [", out);
        for (uint32_t i = 0U; i < layout->waveform_count; ++i) {
            if (i > 0U) {
                fputs(", ", out);
            }
            fprintf(out, "%" PRIu64, layout->wave_data_offsets[i]);
        }
        fputs("]\n", out);
        fputs("}\n", out);
        return 1;
    }

    fprintf(out, "file: %s\n", reader->path);
    fprintf(out, "size: %zu bytes\n", reader->mapped.size);
    fprintf(out, "metadata: [%" PRIu64 ", %" PRIu64 ")\n", layout->metadata_start_offset, layout->metadata_end_offset);
    fprintf(out, "waveform templates: %" PRIu32 " blocks, %" PRIu32 " full-cycle points each\n", layout->waveform_count, layout->waveform_full_points);
    fprintf(out, "active scan points: %" PRIu32 "\n", layout->points_per_scan);
    fprintf(out, "current matrix offset: %" PRIu64 "\n", layout->current_matrix_offset);
    fprintf(out, "scan count: %" PRIu32 "\n", layout->scan_count);
    fprintf(out, "sample rate: %.3f Hz\n", layout->sample_rate_hz);
    fprintf(out, "CVF: %.3f Hz\n", layout->cvf_hz);
    fprintf(out, "sequence time span: 0.0 .. %.3f s\n", hdcv_reader_scan_time_sequence_s(reader, layout->scan_count - 1U));
    fprintf(out, "experiment time span: 0.0 .. %.3f s\n", hdcv_reader_scan_time_experiment_s(reader, layout->scan_count - 1U));
    if (layout->has_run_structure) {
        fprintf(out, "run structure: %" PRIu32 " runs x %" PRIu32 " scans per run\n", layout->run_count, layout->scans_per_run);
    }
    if (layout->has_voltage_bounds) {
        fprintf(out, "voltage bounds: %.3f V .. %.3f V\n", layout->v1_v, layout->v2_v);
    }
    return 1;
}

int hdcv_export_scan_csv(const hdcv_reader *reader, uint32_t scan_index, const char *out_path)
{
    FILE *stream;
    float *voltage;
    float *current;
    uint32_t i;

    voltage = (float *)malloc((size_t)reader->layout.points_per_scan * sizeof(*voltage));
    current = (float *)malloc((size_t)reader->layout.points_per_scan * sizeof(*current));
    if (voltage == NULL || current == NULL) {
        free(voltage);
        free(current);
        return 0;
    }

    if (!hdcv_reader_copy_voltage(reader, voltage, reader->layout.points_per_scan) ||
        !hdcv_reader_copy_scan(reader, scan_index, current, reader->layout.points_per_scan)) {
        free(voltage);
        free(current);
        return 0;
    }

    stream = fopen(out_path, "w");
    if (stream == NULL) {
        free(voltage);
        free(current);
        return 0;
    }

    fputs("point_index,within_scan_time_s,voltage_v,current\n", stream);
    for (i = 0U; i < reader->layout.points_per_scan; ++i) {
        fprintf(
            stream,
            "%" PRIu32 ",%.9f,%.9f,%.9f\n",
            i,
            hdcv_reader_within_scan_time_s(reader, i),
            (double)voltage[i],
            (double)current[i]
        );
    }

    fclose(stream);
    free(voltage);
    free(current);
    return 1;
}

static int export_range_csv(
    const hdcv_reader *reader,
    uint32_t start_scan,
    uint32_t end_scan,
    const char *out_path
)
{
    FILE *stream;
    float *voltage;
    float *scan;
    uint32_t scan_index;
    uint32_t point_index;

    voltage = (float *)malloc((size_t)reader->layout.points_per_scan * sizeof(*voltage));
    scan = (float *)malloc((size_t)reader->layout.points_per_scan * sizeof(*scan));
    if (voltage == NULL || scan == NULL) {
        free(voltage);
        free(scan);
        return 0;
    }

    if (!hdcv_reader_copy_voltage(reader, voltage, reader->layout.points_per_scan)) {
        free(voltage);
        free(scan);
        return 0;
    }

    stream = fopen(out_path, "w");
    if (stream == NULL) {
        free(voltage);
        free(scan);
        return 0;
    }

    fputs("scan_index,sequence_time_s,experiment_time_s,point_index,within_scan_time_s,voltage_v,current\n", stream);
    for (scan_index = start_scan; scan_index <= end_scan; ++scan_index) {
        if (!hdcv_reader_copy_scan(reader, scan_index, scan, reader->layout.points_per_scan)) {
            fclose(stream);
            free(voltage);
            free(scan);
            return 0;
        }
        for (point_index = 0U; point_index < reader->layout.points_per_scan; ++point_index) {
            fprintf(
                stream,
                "%" PRIu32 ",%.9f,%.9f,%" PRIu32 ",%.9f,%.9f,%.9f\n",
                scan_index,
                hdcv_reader_scan_time_sequence_s(reader, scan_index),
                hdcv_reader_scan_time_experiment_s(reader, scan_index),
                point_index,
                hdcv_reader_within_scan_time_s(reader, point_index),
                (double)voltage[point_index],
                (double)scan[point_index]
            );
        }
    }

    fclose(stream);
    free(voltage);
    free(scan);
    return 1;
}

static int export_range_hdcvbin(
    const hdcv_reader *reader,
    uint32_t start_scan,
    uint32_t end_scan,
    const char *out_path
)
{
    FILE *stream;
    float *voltage;
    float *scan;
    uint32_t exported_scans = (end_scan - start_scan) + 1U;
    uint32_t scan_index;
    static const char magic[8] = {'H', 'D', 'C', 'V', 'B', 'I', 'N', '1'};

    voltage = (float *)malloc((size_t)reader->layout.points_per_scan * sizeof(*voltage));
    scan = (float *)malloc((size_t)reader->layout.points_per_scan * sizeof(*scan));
    if (voltage == NULL || scan == NULL) {
        free(voltage);
        free(scan);
        return 0;
    }
    if (!hdcv_reader_copy_voltage(reader, voltage, reader->layout.points_per_scan)) {
        free(voltage);
        free(scan);
        return 0;
    }

    stream = fopen(out_path, "wb");
    if (stream == NULL) {
        free(voltage);
        free(scan);
        return 0;
    }

    (void)fwrite(magic, 1U, sizeof(magic), stream);
    hdcv_write_le_u32(stream, 1U);
    hdcv_write_le_u32(stream, reader->layout.points_per_scan);
    hdcv_write_le_u32(stream, exported_scans);
    hdcv_write_le_u32(stream, start_scan);
    hdcv_write_le_f64(stream, reader->layout.sample_rate_hz);
    hdcv_write_le_f64(stream, reader->layout.cvf_hz);
    hdcv_write_le_f64(stream, reader->layout.scan_interval_s);
    hdcv_write_le_f64(stream, reader->layout.scan_duration_s);
    hdcv_write_le_u32(stream, reader->layout.waveform_count);
    hdcv_write_le_u32(stream, reader->layout.run_count);
    hdcv_write_le_u32(stream, reader->layout.scans_per_run);
    hdcv_write_le_u32(stream, reader->layout.has_experiment_timing ? 1U : 0U);
    hdcv_write_le_f64(stream, reader->layout.run_duration_s);
    hdcv_write_le_f64(stream, reader->layout.delay_between_runs_s);
    hdcv_write_le_f32(stream, (float)reader->layout.v1_v);
    hdcv_write_le_f32(stream, (float)reader->layout.v2_v);

    for (uint32_t i = 0U; i < reader->layout.points_per_scan; ++i) {
        hdcv_write_le_f32(stream, voltage[i]);
    }
    for (scan_index = start_scan; scan_index <= end_scan; ++scan_index) {
        uint32_t i;
        if (!hdcv_reader_copy_scan(reader, scan_index, scan, reader->layout.points_per_scan)) {
            fclose(stream);
            free(voltage);
            free(scan);
            return 0;
        }
        for (i = 0U; i < reader->layout.points_per_scan; ++i) {
            hdcv_write_le_f32(stream, scan[i]);
        }
    }

    fclose(stream);
    free(voltage);
    free(scan);
    return 1;
}

int hdcv_export_range(
    const hdcv_reader *reader,
    uint32_t start_scan,
    uint32_t end_scan,
    const char *format,
    const char *out_path
)
{
    if (strcmp(format, "csv") == 0) {
        return export_range_csv(reader, start_scan, end_scan, out_path);
    }
    return export_range_hdcvbin(reader, start_scan, end_scan, out_path);
}

static int parse_manifest_line(const char *line, char *key, size_t key_size, char *value, size_t value_size)
{
    const char *equals = strchr(line, '=');
    size_t key_len;
    size_t value_len;
    if (equals == NULL) {
        return 0;
    }
    key_len = (size_t)(equals - line);
    value_len = strlen(equals + 1);
    if (key_len + 1U > key_size || value_len + 1U > value_size) {
        return 0;
    }
    memcpy(key, line, key_len);
    key[key_len] = '\0';
    memcpy(value, equals + 1, value_len + 1U);
    return 1;
}

static int load_float_file(const char *path, float *dst, size_t count)
{
    FILE *stream = fopen(path, "rb");
    if (stream == NULL) {
        return 0;
    }
    if (fread(dst, sizeof(*dst), count, stream) != count) {
        fclose(stream);
        return 0;
    }
    fclose(stream);
    return 1;
}

int hdcv_validate_reference(const hdcv_reader *reader, const char *reference_dir, FILE *out)
{
    char manifest_path[1024];
    FILE *manifest;
    char line[1024];
    uint32_t ref_scan_count = 0U;
    uint32_t ref_points_per_scan = 0U;
    uint32_t first_idx = 0U;
    uint32_t middle_idx = 0U;
    uint32_t last_idx = 0U;
    float *voltage_ref;
    float *scan_ref;
    float *scan_cur;
    char pathbuf[1024];
    double max_abs_diff;
    uint32_t i;

    (void)snprintf(manifest_path, sizeof(manifest_path), "%s/manifest.txt", reference_dir);
    manifest = fopen(manifest_path, "r");
    if (manifest == NULL) {
        fprintf(out, "reference manifest not found: %s\n", manifest_path);
        return 0;
    }

    while (fgets(line, sizeof(line), manifest) != NULL) {
        char key[256];
        char value[256];
        char *newline;
        newline = strchr(line, '\n');
        if (newline != NULL) {
            *newline = '\0';
        }
        if (!parse_manifest_line(line, key, sizeof(key), value, sizeof(value))) {
            continue;
        }
        if (strcmp(key, "scan_count") == 0) {
            ref_scan_count = (uint32_t)strtoul(value, NULL, 10);
        } else if (strcmp(key, "points_per_scan") == 0) {
            ref_points_per_scan = (uint32_t)strtoul(value, NULL, 10);
        } else if (strcmp(key, "first_scan_index") == 0) {
            first_idx = (uint32_t)strtoul(value, NULL, 10);
        } else if (strcmp(key, "middle_scan_index") == 0) {
            middle_idx = (uint32_t)strtoul(value, NULL, 10);
        } else if (strcmp(key, "last_scan_index") == 0) {
            last_idx = (uint32_t)strtoul(value, NULL, 10);
        }
    }
    fclose(manifest);

    fprintf(out, "scan_count: C=%" PRIu32 " reference=%" PRIu32 "\n", reader->layout.scan_count, ref_scan_count);
    fprintf(out, "points_per_scan: C=%" PRIu32 " reference=%" PRIu32 "\n", reader->layout.points_per_scan, ref_points_per_scan);

    if (reader->layout.scan_count != ref_scan_count || reader->layout.points_per_scan != ref_points_per_scan) {
        return 0;
    }

    voltage_ref = (float *)malloc((size_t)reader->layout.points_per_scan * sizeof(*voltage_ref));
    scan_ref = (float *)malloc((size_t)reader->layout.points_per_scan * sizeof(*scan_ref));
    scan_cur = (float *)malloc((size_t)reader->layout.points_per_scan * sizeof(*scan_cur));
    if (voltage_ref == NULL || scan_ref == NULL || scan_cur == NULL) {
        free(voltage_ref);
        free(scan_ref);
        free(scan_cur);
        return 0;
    }

    (void)snprintf(pathbuf, sizeof(pathbuf), "%s/voltage_active.f32", reference_dir);
    if (!load_float_file(pathbuf, voltage_ref, reader->layout.points_per_scan)) {
        free(voltage_ref);
        free(scan_ref);
        free(scan_cur);
        return 0;
    }
    if (!hdcv_reader_copy_voltage(reader, scan_cur, reader->layout.points_per_scan)) {
        free(voltage_ref);
        free(scan_ref);
        free(scan_cur);
        return 0;
    }
    max_abs_diff = 0.0;
    for (i = 0U; i < reader->layout.points_per_scan; ++i) {
        double diff = fabs((double)scan_cur[i] - (double)voltage_ref[i]);
        if (diff > max_abs_diff) {
            max_abs_diff = diff;
        }
    }
    fprintf(out, "voltage max_abs_diff: %.9g\n", max_abs_diff);

    const struct {
        const char *file_name;
        uint32_t scan_index;
        const char *label;
    } checks[] = {
        {"scan_first.f32", first_idx, "first"},
        {"scan_middle.f32", middle_idx, "middle"},
        {"scan_last.f32", last_idx, "last"},
    };

    for (size_t check = 0U; check < sizeof(checks) / sizeof(checks[0]); ++check) {
        (void)snprintf(pathbuf, sizeof(pathbuf), "%s/%s", reference_dir, checks[check].file_name);
        if (!load_float_file(pathbuf, scan_ref, reader->layout.points_per_scan) ||
            !hdcv_reader_copy_scan(reader, checks[check].scan_index, scan_cur, reader->layout.points_per_scan)) {
            free(voltage_ref);
            free(scan_ref);
            free(scan_cur);
            return 0;
        }
        max_abs_diff = 0.0;
        for (i = 0U; i < reader->layout.points_per_scan; ++i) {
            double diff = fabs((double)scan_cur[i] - (double)scan_ref[i]);
            if (diff > max_abs_diff) {
                max_abs_diff = diff;
            }
        }
        fprintf(out, "%s scan max_abs_diff: %.9g\n", checks[check].label, max_abs_diff);
    }

    free(voltage_ref);
    free(scan_ref);
    free(scan_cur);
    return 1;
}

int hdcv_run_benchmark(const hdcv_reader *reader, FILE *out)
{
    float *buffer;
    uint32_t scan_index;
    double start;
    double elapsed;
    double checksum = 0.0;

    buffer = (float *)malloc((size_t)reader->layout.points_per_scan * sizeof(*buffer));
    if (buffer == NULL) {
        return 0;
    }

    start = hdcv_now_seconds();
    for (scan_index = 0U; scan_index < reader->layout.scan_count; ++scan_index) {
        uint32_t i;
        if (!hdcv_reader_copy_scan(reader, scan_index, buffer, reader->layout.points_per_scan)) {
            free(buffer);
            return 0;
        }
        for (i = 0U; i < reader->layout.points_per_scan; ++i) {
            checksum += (double)buffer[i];
        }
    }
    elapsed = hdcv_now_seconds() - start;

    fprintf(out, "scan_count=%" PRIu32 "\n", reader->layout.scan_count);
    fprintf(out, "points_per_scan=%" PRIu32 "\n", reader->layout.points_per_scan);
    fprintf(out, "matrix_bytes=%" PRIu64 "\n", reader->layout.current_matrix_bytes);
    fprintf(out, "stream_seconds=%.6f\n", elapsed);
    fprintf(out, "throughput_mb_s=%.3f\n", ((double)reader->layout.current_matrix_bytes / (1024.0 * 1024.0)) / elapsed);
    fprintf(out, "checksum=%.9f\n", checksum);

    free(buffer);
    return 1;
}
