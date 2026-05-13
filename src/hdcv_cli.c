#include "hdcv_export.h"
#include "hdcv_reader.h"

#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#ifdef __APPLE__
#include <mach-o/dyld.h>
#endif

typedef struct {
    double *values;
    size_t count;
    size_t capacity;
} hdcv_time_list;

static void usage(FILE *stream)
{
    fputs("Usage:\n", stream);
    fputs("  hdcv <file.hdcv>\n", stream);
    fputs("  hdcv <file.hdcv> --info [--json]\n", stream);
    fputs("  hdcv <file.hdcv> --cv 100,200,300 [--out exports] [--prefix name] [--phase 0]\n", stream);
    fputs("  hdcv <file.hdcv> -cv [100, 200, 300] --bg-cv 10 [--out exports]\n", stream);
    fputs("\n", stream);
    fputs("With no export options, hdcv launches the native HDCV Viewer app for the file.\n", stream);
}

static void free_time_list(hdcv_time_list *list)
{
    free(list->values);
    list->values = NULL;
    list->count = 0U;
    list->capacity = 0U;
}

static int append_time_value(hdcv_time_list *list, double value)
{
    double *new_values;
    size_t new_capacity;

    if (!isfinite(value)) {
        return 0;
    }
    if (list->count == list->capacity) {
        new_capacity = (list->capacity == 0U) ? 8U : list->capacity * 2U;
        new_values = (double *)realloc(list->values, new_capacity * sizeof(*new_values));
        if (new_values == NULL) {
            return 0;
        }
        list->values = new_values;
        list->capacity = new_capacity;
    }
    list->values[list->count] = value;
    list->count += 1U;
    return 1;
}

static int parse_time_values_from_text(const char *text, hdcv_time_list *list)
{
    const char *p = text;

    while (*p != '\0') {
        char *end = NULL;
        double value;

        while (*p != '\0' && (isspace((unsigned char)*p) || *p == '[' || *p == ']' || *p == ',' || *p == ';')) {
            ++p;
        }
        if (*p == '\0') {
            break;
        }

        errno = 0;
        value = strtod(p, &end);
        if (end == p || errno == ERANGE) {
            return 0;
        }
        if (!append_time_value(list, value)) {
            return 0;
        }
        p = end;
    }
    return 1;
}

static int looks_like_option(const char *arg)
{
    return arg[0] == '-' && arg[1] != '\0' && !isdigit((unsigned char)arg[1]) && arg[1] != '.';
}

static int parse_time_list_arguments(int argc, char **argv, int *index, hdcv_time_list *list, const char *flag)
{
    size_t before = list->count;

    *index += 1;
    while (*index < argc && !looks_like_option(argv[*index])) {
        if (!parse_time_values_from_text(argv[*index], list)) {
            fprintf(stderr, "Invalid time list for %s: %s\n", flag, argv[*index]);
            return 0;
        }
        *index += 1;
    }
    *index -= 1;

    if (list->count == before) {
        fprintf(stderr, "Missing time list for %s\n", flag);
        return 0;
    }
    return 1;
}

static const char *arg_value(int argc, char **argv, int *index, const char *flag)
{
    if (*index + 1 >= argc) {
        fprintf(stderr, "Missing value for %s\n", flag);
        return NULL;
    }
    *index += 1;
    return argv[*index];
}

static int copy_string(char *dst, size_t dst_size, const char *src)
{
    size_t length = strlen(src);
    if (length + 1U > dst_size) {
        return 0;
    }
    memcpy(dst, src, length + 1U);
    return 1;
}

static int directory_from_path(const char *path, char *out, size_t out_size)
{
    const char *slash = strrchr(path, '/');
    size_t length;

    if (slash == NULL) {
        return copy_string(out, out_size, ".");
    }
    length = (size_t)(slash - path);
    if (length == 0U) {
        return copy_string(out, out_size, "/");
    }
    if (length + 1U > out_size) {
        return 0;
    }
    memcpy(out, path, length);
    out[length] = '\0';
    return 1;
}

static int executable_directory(const char *argv0, char *out, size_t out_size)
{
#ifdef __APPLE__
    char path[4096];
    uint32_t path_size = (uint32_t)sizeof(path);

    if (_NSGetExecutablePath(path, &path_size) == 0) {
        char resolved[4096];
        const char *source = path;
        if (realpath(path, resolved) != NULL) {
            source = resolved;
        }
        return directory_from_path(source, out, out_size);
    }
#endif
    return directory_from_path(argv0, out, out_size);
}

static int join_path(char *out, size_t out_size, const char *left, const char *right)
{
    int written;
    if (strcmp(left, "/") == 0) {
        written = snprintf(out, out_size, "/%s", right);
    } else {
        written = snprintf(out, out_size, "%s/%s", left, right);
    }
    return written >= 0 && (size_t)written < out_size;
}

static int run_and_wait(char *const command_argv[])
{
    pid_t pid = fork();
    int status = 0;

    if (pid < 0) {
        return 0;
    }
    if (pid == 0) {
        execv(command_argv[0], command_argv);
        _exit(127);
    }
    if (waitpid(pid, &status, 0) < 0) {
        return 0;
    }
    return WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static int launch_viewer(const char *file_path, const char *argv0)
{
    char executable_dir[4096];
    char app_path[4096];
    char viewer_path[4096];

    if (!executable_directory(argv0, executable_dir, sizeof(executable_dir))) {
        fputs("Could not resolve the hdcv executable location.\n", stderr);
        return 0;
    }

    if (join_path(app_path, sizeof(app_path), executable_dir, "HDCV Viewer.app") && access(app_path, F_OK) == 0) {
        char *const command_argv[] = {"/usr/bin/open", "-n", "-a", app_path, (char *)file_path, NULL};
        if (run_and_wait(command_argv)) {
            return 1;
        }
    }

    if (join_path(viewer_path, sizeof(viewer_path), executable_dir, "hdcv_viewer") && access(viewer_path, X_OK) == 0) {
        char *const command_argv[] = {viewer_path, (char *)file_path, NULL};
        if (run_and_wait(command_argv)) {
            return 1;
        }
    }

    {
        char *const command_argv[] = {"/usr/bin/open", "-a", "HDCV Viewer", (char *)file_path, NULL};
        if (run_and_wait(command_argv)) {
            return 1;
        }
    }

    fprintf(stderr, "Could not launch HDCV Viewer for %s\n", file_path);
    return 0;
}

static int ensure_directory(const char *path)
{
    struct stat info;

    if (stat(path, &info) == 0) {
        if (S_ISDIR(info.st_mode)) {
            return 1;
        }
        fprintf(stderr, "Output path exists but is not a directory: %s\n", path);
        return 0;
    }
    if (mkdir(path, 0755) == 0) {
        return 1;
    }
    fprintf(stderr, "Could not create output directory %s: %s\n", path, strerror(errno));
    return 0;
}

static void basename_without_extension(const char *path, char *out, size_t out_size)
{
    const char *base = strrchr(path, '/');
    const char *dot;
    size_t length;

    base = (base == NULL) ? path : base + 1;
    dot = strrchr(base, '.');
    length = (dot != NULL && dot > base) ? (size_t)(dot - base) : strlen(base);
    if (length + 1U > out_size) {
        length = out_size - 1U;
    }
    memcpy(out, base, length);
    out[length] = '\0';
}

static void format_time_token(double time_s, char *out, size_t out_size)
{
    char temp[96];
    size_t length;
    int written = snprintf(temp, sizeof(temp), "%.6f", time_s);

    if (written < 0) {
        (void)copy_string(out, out_size, "time");
        return;
    }
    length = strlen(temp);
    while (length > 0U && temp[length - 1U] == '0') {
        temp[length - 1U] = '\0';
        length -= 1U;
    }
    if (length > 0U && temp[length - 1U] == '.') {
        temp[length - 1U] = '\0';
    }

    length = 0U;
    for (const char *p = temp; *p != '\0' && length + 2U < out_size; ++p) {
        if (*p == '-') {
            out[length] = 'm';
        } else if (*p == '.') {
            out[length] = 'p';
        } else if (*p == '+') {
            continue;
        } else {
            out[length] = *p;
        }
        length += 1U;
    }
    if (length + 2U < out_size) {
        out[length] = 's';
        length += 1U;
    }
    out[length] = '\0';
}

static int output_path_for_cv(
    char *out,
    size_t out_size,
    const char *directory,
    const char *prefix,
    const char *kind,
    double time_s
)
{
    char token[96];
    int written;

    format_time_token(time_s, token, sizeof(token));
    written = snprintf(out, out_size, "%s/%s_%s_%s.csv", directory, prefix, kind, token);
    return written >= 0 && (size_t)written < out_size;
}

static uint32_t nearest_phase_scan_index(
    uint32_t scan_index,
    uint32_t scan_count,
    uint32_t phase_index,
    uint32_t phase_period
)
{
    uint32_t period = (phase_period == 0U) ? 1U : phase_period;
    uint32_t target_phase = (period <= 1U) ? 0U : phase_index % period;
    double candidate_d;
    int64_t candidate;

    if (scan_count == 0U) {
        return 0U;
    }
    if (period <= 1U || scan_count <= 1U) {
        return (scan_index < scan_count) ? scan_index : scan_count - 1U;
    }
    if (target_phase >= scan_count) {
        target_phase = 0U;
    }

    candidate_d = (double)target_phase +
        (round(((double)scan_index - (double)target_phase) / (double)period) * (double)period);
    candidate = (int64_t)llround(candidate_d);
    while (candidate < 0) {
        candidate += (int64_t)period;
    }
    while (candidate >= (int64_t)scan_count) {
        candidate -= (int64_t)period;
    }
    if (candidate < 0) {
        candidate = 0;
    }
    return (uint32_t)candidate;
}

static uint32_t nearest_scan_for_time(const hdcv_reader *reader, double time_s, uint32_t phase_index)
{
    double interval = reader->layout.scan_interval_s;
    uint32_t scan_index;
    double raw_scan;

    if (reader->layout.scan_count == 0U) {
        return 0U;
    }
    if (!(interval > 0.0) && reader->layout.cvf_hz > 0.0) {
        interval = 1.0 / reader->layout.cvf_hz;
    }
    if (!(interval > 0.0)) {
        interval = 0.1;
    }

    raw_scan = round(time_s / interval);
    if (!isfinite(raw_scan) || raw_scan < 0.0) {
        scan_index = 0U;
    } else if (raw_scan > (double)(reader->layout.scan_count - 1U)) {
        scan_index = reader->layout.scan_count - 1U;
    } else {
        scan_index = (uint32_t)raw_scan;
    }
    return nearest_phase_scan_index(scan_index, reader->layout.scan_count, phase_index, reader->layout.waveform_count);
}

static int write_cv_csv(const hdcv_reader *reader, uint32_t scan_index, const char *out_path)
{
    FILE *stream;
    float *voltage;
    float *current;
    uint32_t point_index;

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
    (void)setvbuf(stream, NULL, _IOFBF, 1024U * 1024U);
    fputs("voltage_V,current_nA\n", stream);
    for (point_index = 0U; point_index < reader->layout.points_per_scan; ++point_index) {
        fprintf(stream, "%.9g,%.9g\n", (double)voltage[point_index], (double)current[point_index]);
    }

    {
        int had_write_error = ferror(stream);
        int close_result = fclose(stream);
        if (had_write_error != 0 || close_result != 0) {
            free(voltage);
            free(current);
            return 0;
        }
    }

    free(voltage);
    free(current);
    return 1;
}

static int export_cv_list(
    const hdcv_reader *reader,
    const hdcv_time_list *times,
    const char *out_dir,
    const char *prefix,
    const char *kind,
    uint32_t phase_index
)
{
    size_t i;

    for (i = 0U; i < times->count; ++i) {
        char out_path[4096];
        uint32_t scan_index = nearest_scan_for_time(reader, times->values[i], phase_index);

        if (!output_path_for_cv(out_path, sizeof(out_path), out_dir, prefix, kind, times->values[i])) {
            fprintf(stderr, "Output path is too long for %.9g s.\n", times->values[i]);
            return 0;
        }
        if (!write_cv_csv(reader, scan_index, out_path)) {
            fprintf(stderr, "Could not write %s\n", out_path);
            return 0;
        }
        printf("wrote %s (t=%.9g s, scan=%" PRIu32 ")\n", out_path, times->values[i], scan_index);
    }
    return 1;
}

int main(int argc, char **argv)
{
    const char *file_path;
    const char *out_dir = ".";
    const char *prefix = NULL;
    char default_prefix[512];
    hdcv_time_list cv_times = {0};
    hdcv_time_list background_cv_times = {0};
    uint32_t phase_index = 0U;
    int show_info = 0;
    int as_json = 0;
    int status = 1;
    hdcv_reader reader;

    if (argc < 2 || strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0) {
        usage((argc < 2) ? stderr : stdout);
        return (argc < 2) ? 1 : 0;
    }

    file_path = argv[1];
    basename_without_extension(file_path, default_prefix, sizeof(default_prefix));
    prefix = default_prefix;

    if (argc == 2) {
        return launch_viewer(file_path, argv[0]) ? 0 : 1;
    }

    for (int i = 2; i < argc; ++i) {
        if (strcmp(argv[i], "--info") == 0) {
            show_info = 1;
        } else if (strcmp(argv[i], "--json") == 0) {
            as_json = 1;
        } else if (strcmp(argv[i], "--cv") == 0 || strcmp(argv[i], "-cv") == 0) {
            if (!parse_time_list_arguments(argc, argv, &i, &cv_times, argv[i])) {
                goto done_without_reader;
            }
        } else if (strcmp(argv[i], "--bg-cv") == 0 || strcmp(argv[i], "--background-cv") == 0) {
            if (!parse_time_list_arguments(argc, argv, &i, &background_cv_times, argv[i])) {
                goto done_without_reader;
            }
        } else if (strcmp(argv[i], "--out") == 0) {
            out_dir = arg_value(argc, argv, &i, "--out");
            if (out_dir == NULL) {
                goto done_without_reader;
            }
        } else if (strcmp(argv[i], "--prefix") == 0) {
            prefix = arg_value(argc, argv, &i, "--prefix");
            if (prefix == NULL) {
                goto done_without_reader;
            }
        } else if (strcmp(argv[i], "--phase") == 0) {
            const char *value = arg_value(argc, argv, &i, "--phase");
            char *end = NULL;
            unsigned long parsed;
            if (value == NULL) {
                goto done_without_reader;
            }
            errno = 0;
            parsed = strtoul(value, &end, 10);
            if (errno != 0 || end == value || *end != '\0' || parsed > UINT32_MAX) {
                fprintf(stderr, "Invalid --phase value: %s\n", value);
                goto done_without_reader;
            }
            phase_index = (uint32_t)parsed;
        } else if (strcmp(argv[i], "--launch") == 0) {
            status = launch_viewer(file_path, argv[0]) ? 0 : 1;
            goto done_without_reader;
        } else {
            fprintf(stderr, "Unknown option: %s\n", argv[i]);
            usage(stderr);
            goto done_without_reader;
        }
    }

    if (!hdcv_reader_open(&reader, file_path)) {
        fprintf(stderr, "error: %s\n", reader.error);
        goto done_without_reader;
    }

    if (show_info) {
        status = hdcv_print_info(&reader, stdout, as_json) ? 0 : 1;
        goto done_with_reader;
    }

    if (cv_times.count == 0U && background_cv_times.count == 0U) {
        hdcv_reader_close(&reader);
        status = launch_viewer(file_path, argv[0]) ? 0 : 1;
        goto done_without_reader;
    }

    if (!ensure_directory(out_dir)) {
        goto done_with_reader;
    }

    if (!export_cv_list(&reader, &cv_times, out_dir, prefix, "CV", phase_index)) {
        goto done_with_reader;
    }
    if (!export_cv_list(&reader, &background_cv_times, out_dir, prefix, "CV_bg", phase_index)) {
        goto done_with_reader;
    }
    status = 0;

done_with_reader:
    hdcv_reader_close(&reader);
done_without_reader:
    free_time_list(&cv_times);
    free_time_list(&background_cv_times);
    return status;
}
