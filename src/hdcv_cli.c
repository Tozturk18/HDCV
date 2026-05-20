#include "hdcv_analysis.h"
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

#define HDCV_SCAN_INDEX_NOT_FOUND UINT32_MAX
#define HDCV_CV_HALF_WINDOW 1U

typedef struct {
    double *values;
    size_t count;
    size_t capacity;
} hdcv_number_list;

typedef struct {
    const char *out_dir;
    const char *prefix;
    uint32_t channel_index;
    const char *channel_spec;
    int channel_spec_zero_based;
    int background_subtract;
    int bandpass;
    double background_time_s;
    int has_time_range;
    double time_min_s;
    double time_max_s;
    int has_point_range;
    uint32_t point_min;
    uint32_t point_max;
    int stdout_export;
} hdcv_cli_options;

static void usage(FILE *stream)
{
    fputs("Usage:\n", stream);
    fputs("  hdcv <file.hdcv>\n", stream);
    fputs("  hdcv <file.hdcv> --info [--json]\n", stream);
    fputs("  hdcv <file.hdcv> --cv 100,200,300 [--bg-time 50 --bg-subtract] [--bandpass] [--out exports]\n", stream);
    fputs("  hdcv <file.hdcv> --it 0.65 [--bg-time 50 --bg-subtract] [--bandpass] [--out exports]\n", stream);
    fputs("  hdcv <file.hdcv> --color [--channel 1|Ramp0] [--time-range 100:300] [--point-range 0:1500] [--out exports]\n", stream);
    fputs("  hdcv <file.hdcv> -cv [100, 200, 300] --bg-cv 50 [--channel 1]\n", stream);
    fputs("  hdcv <file.hdcv> --cv 100 --stdout\n", stream);
    fputs("  hdcv <file.hdcv> --it 0.65 --stdout\n", stream);
    fputs("  hdcv --install-command [--install-destination /path/to/hdcv]\n", stream);
    fputs("  hdcv --uninstall-command [--install-destination /path/to/hdcv]\n", stream);
    fputs("\n", stream);
    fputs("With no export options, hdcv launches the native HDCV Viewer app for the file.\n", stream);
}

static void free_number_list(hdcv_number_list *list)
{
    free(list->values);
    list->values = NULL;
    list->count = 0U;
    list->capacity = 0U;
}

static int append_number_value(hdcv_number_list *list, double value)
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

static int parse_number_values_from_text(const char *text, hdcv_number_list *list)
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
        if (!append_number_value(list, value)) {
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

static int parse_number_list_arguments(int argc, char **argv, int *index, hdcv_number_list *list, const char *flag)
{
    size_t before = list->count;

    *index += 1;
    while (*index < argc && !looks_like_option(argv[*index])) {
        if (!parse_number_values_from_text(argv[*index], list)) {
            fprintf(stderr, "Invalid number list for %s: %s\n", flag, argv[*index]);
            return 0;
        }
        *index += 1;
    }
    *index -= 1;

    if (list->count == before) {
        fprintf(stderr, "Missing number list for %s\n", flag);
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

static int parse_double_range(const char *text, double *out_min, double *out_max)
{
    char *end = NULL;
    double min_value;
    double max_value;
    char *second_start;

    errno = 0;
    min_value = strtod(text, &end);
    if (end == text || errno == ERANGE) {
        return 0;
    }
    while (*end != '\0' && (isspace((unsigned char)*end) || *end == ':' || *end == ',' || *end == ';')) {
        ++end;
    }
    second_start = end;
    errno = 0;
    max_value = strtod(end, &end);
    if (end == second_start || errno == ERANGE || !isfinite(min_value) || !isfinite(max_value)) {
        return 0;
    }
    if (max_value < min_value) {
        double tmp = min_value;
        min_value = max_value;
        max_value = tmp;
    }
    *out_min = min_value;
    *out_max = max_value;
    return 1;
}

static int parse_u32_range(const char *text, uint32_t *out_min, uint32_t *out_max)
{
    char *end = NULL;
    unsigned long min_value;
    unsigned long max_value;
    char *second_start;

    errno = 0;
    min_value = strtoul(text, &end, 10);
    if (end == text || errno != 0 || min_value > UINT32_MAX) {
        return 0;
    }
    while (*end != '\0' && (isspace((unsigned char)*end) || *end == ':' || *end == ',' || *end == ';')) {
        ++end;
    }
    second_start = end;
    errno = 0;
    max_value = strtoul(end, &end, 10);
    if (end == second_start || errno != 0 || max_value > UINT32_MAX) {
        return 0;
    }
    if (max_value < min_value) {
        unsigned long tmp = min_value;
        min_value = max_value;
        max_value = tmp;
    }
    *out_min = (uint32_t)min_value;
    *out_max = (uint32_t)max_value;
    return 1;
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

static int executable_path(const char *argv0, char *out, size_t out_size)
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
        return copy_string(out, out_size, source);
    }
#endif
    if (strchr(argv0, '/') != NULL) {
        char resolved[4096];
        if (realpath(argv0, resolved) != NULL) {
            return copy_string(out, out_size, resolved);
        }
        return copy_string(out, out_size, argv0);
    }
    return 0;
}

static int executable_directory(const char *argv0, char *out, size_t out_size)
{
    char path[4096];
    if (executable_path(argv0, path, sizeof(path))) {
        return directory_from_path(path, out, out_size);
    }
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

    if (strstr(executable_dir, "/Contents/Resources/bin") != NULL) {
        char bundle_path[4096];
        size_t prefix_length = (size_t)(strstr(executable_dir, "/Contents/Resources/bin") - executable_dir);
        if (prefix_length + 1U < sizeof(bundle_path)) {
            memcpy(bundle_path, executable_dir, prefix_length);
            bundle_path[prefix_length] = '\0';
            if (access(bundle_path, F_OK) == 0) {
                char *const command_argv[] = {"/usr/bin/open", "-n", "-a", bundle_path, (char *)file_path, NULL};
                if (run_and_wait(command_argv)) {
                    return 1;
                }
            }
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

static int install_command_line_tool(const char *argv0, const char *destination)
{
    char source[4096];
    char destination_dir[4096];
    struct stat info;

    if (!executable_path(argv0, source, sizeof(source))) {
        fputs("Could not resolve the current hdcv executable path.\n", stderr);
        return 0;
    }
    if (!directory_from_path(destination, destination_dir, sizeof(destination_dir))) {
        fprintf(stderr, "Install destination is too long: %s\n", destination);
        return 0;
    }
    if (!ensure_directory(destination_dir)) {
        return 0;
    }

    if (lstat(destination, &info) == 0) {
        if (!S_ISLNK(info.st_mode)) {
            fprintf(stderr, "%s exists and is not a symlink; not overwriting it.\n", destination);
            return 0;
        }
        if (unlink(destination) != 0) {
            fprintf(stderr, "Could not replace %s: %s\n", destination, strerror(errno));
            return 0;
        }
    }
    if (symlink(source, destination) != 0) {
        fprintf(stderr, "Could not install %s: %s\n", destination, strerror(errno));
        fprintf(stderr, "Try: sudo ln -sf \"%s\" \"%s\"\n", source, destination);
        return 0;
    }
    printf("installed %s -> %s\n", destination, source);
    return 1;
}

static int uninstall_command_line_tool(const char *destination)
{
    struct stat info;
    if (lstat(destination, &info) != 0) {
        printf("%s is not installed.\n", destination);
        return 1;
    }
    if (!S_ISLNK(info.st_mode)) {
        fprintf(stderr, "%s exists and is not a symlink; not removing it.\n", destination);
        return 0;
    }
    if (unlink(destination) != 0) {
        fprintf(stderr, "Could not remove %s: %s\n", destination, strerror(errno));
        return 0;
    }
    printf("removed %s\n", destination);
    return 1;
}

static const char *default_install_destination(void)
{
    if (access("/usr/local/bin", W_OK) == 0) {
        return "/usr/local/bin/hdcv";
    }
    if (access("/opt/homebrew/bin", W_OK) == 0) {
        return "/opt/homebrew/bin/hdcv";
    }
    return "/usr/local/bin/hdcv";
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

static void format_number_token(double value, const char *suffix, char *out, size_t out_size)
{
    char temp[96];
    size_t length;
    int written = snprintf(temp, sizeof(temp), "%.6f", value);

    if (written < 0) {
        (void)copy_string(out, out_size, "value");
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
    for (const char *p = suffix; *p != '\0' && length + 1U < out_size; ++p) {
        out[length++] = *p;
    }
    out[length] = '\0';
}

static int output_path_with_token(
    char *out,
    size_t out_size,
    const char *directory,
    const char *prefix,
    const char *kind,
    const char *token
)
{
    int written = snprintf(out, out_size, "%s/%s_%s_%s.csv", directory, prefix, kind, token);
    return written >= 0 && (size_t)written < out_size;
}

static int output_path_simple(
    char *out,
    size_t out_size,
    const char *directory,
    const char *prefix,
    const char *kind
)
{
    int written = snprintf(out, out_size, "%s/%s_%s.csv", directory, prefix, kind);
    return written >= 0 && (size_t)written < out_size;
}

static uint32_t nearest_scan_for_time(const hdcv_reader *reader, double time_s, uint32_t channel_index)
{
    return hdcv_reader_nearest_row_for_channel_time(reader, channel_index, time_s);
}

static int parse_channel_spec(
    const hdcv_reader *reader,
    const char *text,
    int zero_based_numeric,
    uint32_t *out_channel_index
)
{
    char *end = NULL;
    unsigned long parsed;

    if (text == NULL || text[0] == '\0') {
        *out_channel_index = 0U;
        return 1;
    }

    errno = 0;
    parsed = strtoul(text, &end, 10);
    if (errno == 0 && end != text && *end == '\0') {
        if (zero_based_numeric) {
            if (parsed >= reader->layout.channel_count) {
                return 0;
            }
            *out_channel_index = (uint32_t)parsed;
            return 1;
        }
        if (parsed == 0UL) {
            *out_channel_index = 0U;
            return 1;
        }
        if (parsed <= reader->layout.channel_count) {
            *out_channel_index = (uint32_t)(parsed - 1UL);
            return 1;
        }
        return 0;
    }

    for (uint32_t i = 0U; i < reader->layout.channel_count; ++i) {
        const char *name = hdcv_reader_channel_name(reader, i);
        if (strcmp(text, name) == 0) {
            *out_channel_index = i;
            return 1;
        }
    }
    return 0;
}

static uint32_t nearest_point_for_voltage(const float *voltage, uint32_t point_count, double requested_voltage)
{
    uint32_t best_index = 0U;
    double best_error = HUGE_VAL;

    for (uint32_t point_index = 0U; point_index < point_count; ++point_index) {
        double error = fabs((double)voltage[point_index] - requested_voltage);
        if (error < best_error) {
            best_error = error;
            best_index = point_index;
        }
    }
    return best_index;
}

static FILE *open_csv_file(const char *path)
{
    if (strcmp(path, "-") == 0) {
        return stdout;
    }

    FILE *stream = fopen(path, "w");
    if (stream == NULL) {
        fprintf(stderr, "Could not create %s: %s\n", path, strerror(errno));
        return NULL;
    }
    (void)setvbuf(stream, NULL, _IOFBF, 1024U * 1024U);
    return stream;
}

static int close_csv_file(FILE *stream, const char *path)
{
    if (strcmp(path, "-") == 0) {
        return fflush(stream) == 0;
    }

    int had_write_error = ferror(stream);
    int close_result = fclose(stream);
    if (had_write_error != 0 || close_result != 0) {
        fprintf(stderr, "Could not finish writing %s: %s\n", path, strerror(errno));
        return 0;
    }
    return 1;
}

static int write_cv_values_csv(const char *out_path, const float *voltage, const float *current, uint32_t point_count)
{
    FILE *stream = open_csv_file(out_path);
    if (stream == NULL) {
        return 0;
    }
    fputs("voltage_V,current_nA\n", stream);
    for (uint32_t point_index = 0U; point_index < point_count; ++point_index) {
        fprintf(stream, "%.9g,%.9g\n", (double)voltage[point_index], (double)current[point_index]);
    }
    return close_csv_file(stream, out_path);
}

static int copy_average_scan(
    const hdcv_reader *reader,
    uint32_t center_scan,
    uint32_t channel_index,
    uint32_t channel_count,
    uint32_t half_window,
    float *destination,
    float *scratch,
    double *sums
)
{
    uint32_t points_per_scan = reader->layout.points_per_scan;
    uint32_t center = hdcv_analysis_nearest_row_index_for_channel(center_scan, reader->layout.scan_count, channel_index, channel_count);
    int64_t start = (int64_t)center - ((int64_t)half_window * (int64_t)channel_count);
    int64_t end = (int64_t)center + ((int64_t)half_window * (int64_t)channel_count);
    uint32_t used_count = 0U;

    memset(sums, 0, (size_t)points_per_scan * sizeof(*sums));
    while (start < 0) {
        start += (int64_t)channel_count;
    }
    while (end >= (int64_t)reader->layout.scan_count) {
        end -= (int64_t)channel_count;
    }
    for (int64_t local_scan = start; local_scan <= end; local_scan += (int64_t)channel_count) {
        if (local_scan < 0 || local_scan >= (int64_t)reader->layout.scan_count) {
            continue;
        }
        if (!hdcv_reader_copy_scan(reader, (uint32_t)local_scan, scratch, points_per_scan)) {
            return 0;
        }
        for (uint32_t point_index = 0U; point_index < points_per_scan; ++point_index) {
            sums[point_index] += (double)scratch[point_index];
        }
        used_count += 1U;
    }
    if (used_count == 0U) {
        return hdcv_reader_copy_scan(reader, center, destination, points_per_scan);
    }
    for (uint32_t point_index = 0U; point_index < points_per_scan; ++point_index) {
        destination[point_index] = (float)(sums[point_index] / (double)used_count);
    }
    return 1;
}

static int write_processed_cv_csv(
    const hdcv_reader *reader,
    double time_s,
    const hdcv_cli_options *options,
    const char *out_path,
    int force_raw
)
{
    uint32_t scan_count = reader->layout.scan_count;
    uint32_t points_per_scan = reader->layout.points_per_scan;
    uint32_t channel_count = reader->layout.channel_count == 0U ? 1U : reader->layout.channel_count;
    uint32_t active_channel = options->channel_index % channel_count;
    uint32_t selected_center = nearest_scan_for_time(reader, time_s, active_channel);
    uint32_t background_center = nearest_scan_for_time(reader, options->background_time_s, active_channel);
    int background_subtract = options->background_subtract && !force_raw;
    float *voltage = NULL;
    float *cv_values = NULL;
    int ok = 0;

    voltage = (float *)malloc((size_t)points_per_scan * sizeof(*voltage));
    cv_values = (float *)malloc((size_t)points_per_scan * sizeof(*cv_values));
    if (voltage == NULL || cv_values == NULL) {
        goto done;
    }
    if (!hdcv_reader_copy_voltage_for_channel(reader, active_channel, voltage, points_per_scan)) {
        goto done;
    }

    if (background_subtract && selected_center == background_center) {
        memset(cv_values, 0, (size_t)points_per_scan * sizeof(*cv_values));
        ok = write_cv_values_csv(out_path, voltage, cv_values, points_per_scan);
        goto done;
    }

    if (options->bandpass) {
        float *trace = (float *)malloc((size_t)scan_count * sizeof(*trace));
        float *source_trace = background_subtract ? (float *)malloc((size_t)scan_count * sizeof(*source_trace)) : NULL;
        if (trace == NULL || (background_subtract && source_trace == NULL)) {
            free(trace);
            free(source_trace);
            goto done;
        }
        for (uint32_t point_index = 0U; point_index < points_per_scan; ++point_index) {
            if (!hdcv_analysis_copy_point_trace(reader, point_index, trace, scan_count, NULL, NULL)) {
                free(trace);
                free(source_trace);
                goto done;
            }
            if (background_subtract) {
                memcpy(source_trace, trace, (size_t)scan_count * sizeof(*source_trace));
                hdcv_analysis_apply_channel_aligned_background_to_trace(
                    source_trace,
                    trace,
                    scan_count,
                    background_center,
                    channel_count
                );
            }
            (void)hdcv_analysis_apply_butterworth_bandpass_by_channel(trace, scan_count, channel_count, reader->layout.cvf_hz);
            cv_values[point_index] = hdcv_analysis_average_trace_in_channel_window(
                trace,
                scan_count,
                selected_center,
                active_channel,
                channel_count,
                HDCV_CV_HALF_WINDOW
            );
        }
        free(trace);
        free(source_trace);
    } else {
        float *selected_average = (float *)malloc((size_t)points_per_scan * sizeof(*selected_average));
        float *background_average = (float *)malloc((size_t)points_per_scan * sizeof(*background_average));
        float *scratch = (float *)malloc((size_t)points_per_scan * sizeof(*scratch));
        double *sums = (double *)malloc((size_t)points_per_scan * sizeof(*sums));
        if (selected_average == NULL || background_average == NULL || scratch == NULL || sums == NULL) {
            free(selected_average);
            free(background_average);
            free(scratch);
            free(sums);
            goto done;
        }
        if (!copy_average_scan(reader, selected_center, active_channel, channel_count, HDCV_CV_HALF_WINDOW, selected_average, scratch, sums)) {
            free(selected_average);
            free(background_average);
            free(scratch);
            free(sums);
            goto done;
        }
        if (background_subtract) {
            if (!copy_average_scan(reader, background_center, active_channel, channel_count, HDCV_CV_HALF_WINDOW, background_average, scratch, sums)) {
                free(selected_average);
                free(background_average);
                free(scratch);
                free(sums);
                goto done;
            }
        }
        for (uint32_t point_index = 0U; point_index < points_per_scan; ++point_index) {
            double current = (double)selected_average[point_index] -
                (background_subtract ? (double)background_average[point_index] : 0.0);
            cv_values[point_index] = (float)current;
        }
        free(selected_average);
        free(background_average);
        free(scratch);
        free(sums);
    }

    if (background_subtract) {
        hdcv_analysis_background_subtracted_cv_denoise(cv_values, voltage, points_per_scan);
    }
    ok = write_cv_values_csv(out_path, voltage, cv_values, points_per_scan);

done:
    free(voltage);
    free(cv_values);
    return ok;
}

static int export_cv_list(
    const hdcv_reader *reader,
    const hdcv_number_list *times,
    const hdcv_cli_options *options,
    const char *kind,
    const char *suffix,
    int force_raw
)
{
    for (size_t i = 0U; i < times->count; ++i) {
        char out_path[4096];
        char token[96];
        uint32_t scan_index = nearest_scan_for_time(reader, times->values[i], options->channel_index);

        if (options->stdout_export) {
            if (!copy_string(out_path, sizeof(out_path), "-")) {
                return 0;
            }
        } else {
            format_number_token(times->values[i], "s", token, sizeof(token));
            if (!output_path_with_token(out_path, sizeof(out_path), options->out_dir, options->prefix, suffix, token)) {
                fprintf(stderr, "Output path is too long for %.9g s.\n", times->values[i]);
                return 0;
            }
        }
        if (!write_processed_cv_csv(reader, times->values[i], options, out_path, force_raw)) {
            fprintf(stderr, "Could not write %s\n", out_path);
            return 0;
        }
        if (options->stdout_export) {
            fprintf(stderr, "wrote stdout (%s t=%.9g s, scan=%" PRIu32 ")\n", kind, times->values[i], scan_index);
        } else {
            printf("wrote %s (%s t=%.9g s, scan=%" PRIu32 ")\n", out_path, kind, times->values[i], scan_index);
        }
    }
    return 1;
}

static int write_it_csv_for_voltage(
    const hdcv_reader *reader,
    double requested_voltage,
    const hdcv_cli_options *options,
    const char *out_path
)
{
    uint32_t scan_count = reader->layout.scan_count;
    uint32_t points_per_scan = reader->layout.points_per_scan;
    uint32_t channel_count = reader->layout.channel_count == 0U ? 1U : reader->layout.channel_count;
    uint32_t active_channel = options->channel_index % channel_count;
    uint32_t background_scan = nearest_scan_for_time(reader, options->background_time_s, active_channel);
    uint32_t scan_min = 0U;
    uint32_t scan_max = scan_count == 0U ? 0U : scan_count - 1U;
    uint32_t first_scan;
    uint32_t point_index;
    float *voltage = NULL;
    float *trace = NULL;
    int ok = 0;
    FILE *stream;

    if (options->has_time_range) {
        scan_min = nearest_scan_for_time(reader, options->time_min_s, active_channel);
        scan_max = nearest_scan_for_time(reader, options->time_max_s, active_channel);
        if (scan_max < scan_min) {
            uint32_t tmp = scan_min;
            scan_min = scan_max;
            scan_max = tmp;
        }
    }

    voltage = (float *)malloc((size_t)points_per_scan * sizeof(*voltage));
    trace = (float *)malloc((size_t)scan_count * sizeof(*trace));
    if (voltage == NULL || trace == NULL) {
        goto done;
    }
    if (!hdcv_reader_copy_voltage_for_channel(reader, active_channel, voltage, points_per_scan)) {
        goto done;
    }
    point_index = nearest_point_for_voltage(voltage, points_per_scan, requested_voltage);
    if (!hdcv_analysis_copy_point_trace(reader, point_index, trace, scan_count, NULL, NULL)) {
        goto done;
    }
    if (options->background_subtract) {
        float *source_trace = (float *)malloc((size_t)scan_count * sizeof(*source_trace));
        if (source_trace == NULL) {
            goto done;
        }
        memcpy(source_trace, trace, (size_t)scan_count * sizeof(*source_trace));
        hdcv_analysis_apply_channel_aligned_background_to_trace(
            source_trace,
            trace,
            scan_count,
            background_scan,
            channel_count
        );
        free(source_trace);
    }
    if (options->bandpass) {
        (void)hdcv_analysis_apply_butterworth_bandpass_by_channel(trace, scan_count, channel_count, reader->layout.cvf_hz);
    }

    stream = open_csv_file(out_path);
    if (stream == NULL) {
        goto done;
    }
    fprintf(stream, "time_s,current_nA\n");
    first_scan = hdcv_analysis_first_channel_row_in_range(scan_min, scan_max, active_channel, channel_count);
    for (uint32_t scan_index = first_scan; first_scan != HDCV_SCAN_INDEX_NOT_FOUND && scan_index <= scan_max; scan_index += channel_count) {
        fprintf(stream, "%.9g,%.9g\n", hdcv_reader_scan_time_sequence_s(reader, scan_index), (double)trace[scan_index]);
        if (channel_count == 0U) {
            break;
        }
    }
    ok = close_csv_file(stream, out_path);

done:
    free(voltage);
    free(trace);
    return ok;
}

static int export_it_list(const hdcv_reader *reader, const hdcv_number_list *voltages, const hdcv_cli_options *options)
{
    float *voltage = NULL;
    uint32_t points_per_scan = reader->layout.points_per_scan;

    if (voltages->count == 0U) {
        return 1;
    }
    voltage = (float *)malloc((size_t)points_per_scan * sizeof(*voltage));
    if (voltage == NULL || !hdcv_reader_copy_voltage_for_channel(reader, options->channel_index, voltage, points_per_scan)) {
        free(voltage);
        return 0;
    }

    for (size_t i = 0U; i < voltages->count; ++i) {
        char out_path[4096];
        char value_token[96];
        char token[128];
        uint32_t point_index = nearest_point_for_voltage(voltage, points_per_scan, voltages->values[i]);

        if (options->stdout_export) {
            if (!copy_string(out_path, sizeof(out_path), "-")) {
                free(voltage);
                return 0;
            }
        } else {
            format_number_token(voltages->values[i], "V", value_token, sizeof(value_token));
            snprintf(token, sizeof(token), "%s_p%" PRIu32, value_token, point_index);
            if (!output_path_with_token(out_path, sizeof(out_path), options->out_dir, options->prefix, "IT", token)) {
                fprintf(stderr, "Output path is too long for %.9g V.\n", voltages->values[i]);
                free(voltage);
                return 0;
            }
        }
        if (!write_it_csv_for_voltage(reader, voltages->values[i], options, out_path)) {
            fprintf(stderr, "Could not write %s\n", out_path);
            free(voltage);
            return 0;
        }
        if (options->stdout_export) {
            fprintf(stderr,
                "wrote stdout (requested %.9g V, point=%" PRIu32 ", actual %.9g V)\n",
                voltages->values[i],
                point_index,
                (double)voltage[point_index]);
        } else {
            printf("wrote %s (requested %.9g V, point=%" PRIu32 ", actual %.9g V)\n",
                out_path,
                voltages->values[i],
                point_index,
                (double)voltage[point_index]);
        }
    }
    free(voltage);
    return 1;
}

static int write_color_csv(const hdcv_reader *reader, const hdcv_cli_options *options)
{
    uint32_t scan_count = reader->layout.scan_count;
    uint32_t points_per_scan = reader->layout.points_per_scan;
    uint32_t channel_count = reader->layout.channel_count == 0U ? 1U : reader->layout.channel_count;
    uint32_t active_channel = options->channel_index % channel_count;
    uint32_t scan_min = 0U;
    uint32_t scan_max = scan_count == 0U ? 0U : scan_count - 1U;
    uint32_t point_min = 0U;
    uint32_t point_max = points_per_scan == 0U ? 0U : points_per_scan - 1U;
    uint32_t export_scan_count;
    uint32_t export_point_count;
    uint32_t background_scan = nearest_scan_for_time(reader, options->background_time_s, active_channel);
    char out_path[4096];
    float *voltage = NULL;
    int ok = 0;
    FILE *stream = NULL;

    if (options->has_time_range) {
        scan_min = nearest_scan_for_time(reader, options->time_min_s, active_channel);
        scan_max = nearest_scan_for_time(reader, options->time_max_s, active_channel);
        if (scan_max < scan_min) {
            uint32_t tmp = scan_min;
            scan_min = scan_max;
            scan_max = tmp;
        }
    }
    if (options->has_point_range) {
        point_min = options->point_min < points_per_scan ? options->point_min : points_per_scan - 1U;
        point_max = options->point_max < points_per_scan ? options->point_max : points_per_scan - 1U;
        if (point_max < point_min) {
            uint32_t tmp = point_min;
            point_min = point_max;
            point_max = tmp;
        }
    }

    export_scan_count = hdcv_analysis_channel_sample_count_in_range(scan_min, scan_max, active_channel, channel_count);
    export_point_count = point_max - point_min + 1U;
    if (export_scan_count == 0U || export_point_count == 0U) {
        fputs("No color plot samples match the requested range.\n", stderr);
        return 0;
    }

    if (options->stdout_export) {
        if (!copy_string(out_path, sizeof(out_path), "-")) {
            return 0;
        }
    } else {
        if (!output_path_simple(out_path, sizeof(out_path), options->out_dir, options->prefix, "color")) {
            fputs("Color export path is too long.\n", stderr);
            return 0;
        }
    }
    voltage = (float *)malloc((size_t)points_per_scan * sizeof(*voltage));
    if (voltage == NULL || !hdcv_reader_copy_voltage_for_channel(reader, active_channel, voltage, points_per_scan)) {
        goto done;
    }
    stream = open_csv_file(out_path);
    if (stream == NULL) {
        goto done;
    }
    fputs("time_s,current_nA,voltage_V\n", stream);

    if (options->bandpass) {
        float *trace = (float *)malloc((size_t)scan_count * sizeof(*trace));
        float *source_trace = options->background_subtract ? (float *)malloc((size_t)scan_count * sizeof(*source_trace)) : NULL;
        float *matrix = (float *)malloc((size_t)export_scan_count * export_point_count * sizeof(*matrix));
        if (trace == NULL || matrix == NULL || (options->background_subtract && source_trace == NULL)) {
            free(trace);
            free(source_trace);
            free(matrix);
            goto done;
        }

        for (uint32_t point_index = point_min; point_index <= point_max; ++point_index) {
            uint32_t local_point = point_index - point_min;
            uint32_t local_scan = 0U;
            uint32_t first_scan;

            if (!hdcv_analysis_copy_point_trace(reader, point_index, trace, scan_count, NULL, NULL)) {
                free(trace);
                free(source_trace);
                free(matrix);
                goto done;
            }
            if (options->background_subtract) {
                memcpy(source_trace, trace, (size_t)scan_count * sizeof(*source_trace));
                hdcv_analysis_apply_channel_aligned_background_to_trace(source_trace, trace, scan_count, background_scan, channel_count);
            }
            (void)hdcv_analysis_apply_butterworth_bandpass_by_channel(trace, scan_count, channel_count, reader->layout.cvf_hz);

            first_scan = hdcv_analysis_first_channel_row_in_range(scan_min, scan_max, active_channel, channel_count);
            for (uint32_t scan_index = first_scan; first_scan != HDCV_SCAN_INDEX_NOT_FOUND && scan_index <= scan_max; scan_index += channel_count) {
                matrix[((size_t)local_scan * export_point_count) + local_point] = trace[scan_index];
                local_scan += 1U;
            }
        }

        {
            uint32_t local_scan = 0U;
            uint32_t first_scan = hdcv_analysis_first_channel_row_in_range(scan_min, scan_max, active_channel, channel_count);
            for (uint32_t scan_index = first_scan; first_scan != HDCV_SCAN_INDEX_NOT_FOUND && scan_index <= scan_max; scan_index += channel_count) {
                double time = hdcv_reader_scan_time_sequence_s(reader, scan_index);
                for (uint32_t point_index = point_min; point_index <= point_max; ++point_index) {
                    uint32_t local_point = point_index - point_min;
                    fprintf(stream, "%.9g,%.9g,%.9g\n",
                        time,
                        (double)matrix[((size_t)local_scan * export_point_count) + local_point],
                        (double)voltage[point_index]);
                }
                local_scan += 1U;
            }
        }
        free(trace);
        free(source_trace);
        free(matrix);
    } else {
        float *scan = (float *)malloc((size_t)points_per_scan * sizeof(*scan));
        float **background_cache = NULL;
        if (scan == NULL) {
            free(scan);
            goto done;
        }
        if (options->background_subtract) {
            background_cache = (float **)calloc(channel_count, sizeof(*background_cache));
            if (background_cache == NULL) {
                free(scan);
                goto done;
            }
        }

        {
            uint32_t first_scan = hdcv_analysis_first_channel_row_in_range(scan_min, scan_max, active_channel, channel_count);
            for (uint32_t scan_index = first_scan; first_scan != HDCV_SCAN_INDEX_NOT_FOUND && scan_index <= scan_max; scan_index += channel_count) {
                const float *background = NULL;
                double time = hdcv_reader_scan_time_sequence_s(reader, scan_index);

                if (!hdcv_reader_copy_scan(reader, scan_index, scan, points_per_scan)) {
                    if (background_cache != NULL) {
                        for (uint32_t i = 0U; i < channel_count; ++i) {
                            free(background_cache[i]);
                        }
                    }
                    free(background_cache);
                    free(scan);
                    goto done;
                }
                if (options->background_subtract) {
                    uint32_t aligned_index = hdcv_analysis_channel_aligned_background_index(
                        background_scan,
                        scan_index,
                        scan_count,
                        channel_count
                    );
                    uint32_t cache_index = aligned_index % channel_count;
                    if (background_cache[cache_index] == NULL) {
                        background_cache[cache_index] = (float *)malloc((size_t)points_per_scan * sizeof(*background_cache[cache_index]));
                        if (background_cache[cache_index] == NULL ||
                            !hdcv_reader_copy_scan(reader, aligned_index, background_cache[cache_index], points_per_scan)) {
                            for (uint32_t i = 0U; i < channel_count; ++i) {
                                free(background_cache[i]);
                            }
                            free(background_cache);
                            free(scan);
                            goto done;
                        }
                    }
                    background = background_cache[cache_index];
                }

                for (uint32_t point_index = point_min; point_index <= point_max; ++point_index) {
                    double current = (double)scan[point_index] -
                        ((background != NULL) ? (double)background[point_index] : 0.0);
                    fprintf(stream, "%.9g,%.9g,%.9g\n", time, current, (double)voltage[point_index]);
                }
            }
        }
        if (background_cache != NULL) {
            for (uint32_t i = 0U; i < channel_count; ++i) {
                free(background_cache[i]);
            }
        }
        free(background_cache);
        free(scan);
    }

    ok = close_csv_file(stream, out_path);
    stream = NULL;
    if (ok) {
        FILE *status_stream = options->stdout_export ? stderr : stdout;
        fprintf(status_stream, "wrote %s (%" PRIu32 " channel-%" PRIu32 " samples x %" PRIu32 " points)\n",
            options->stdout_export ? "stdout" : out_path,
            export_scan_count,
            active_channel + 1U,
            export_point_count);
    }

done:
    if (stream != NULL) {
        fclose(stream);
    }
    free(voltage);
    return ok;
}

int main(int argc, char **argv)
{
    const char *install_destination = default_install_destination();
    const char *file_path;
    char default_prefix[512];
    hdcv_number_list cv_times = {0};
    hdcv_number_list background_cv_times = {0};
    hdcv_number_list it_voltages = {0};
    hdcv_cli_options options;
    int show_info = 0;
    int as_json = 0;
    int export_color = 0;
    int status = 1;
    hdcv_reader reader;

    if (argc < 2 || strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0) {
        usage((argc < 2) ? stderr : stdout);
        return (argc < 2) ? 1 : 0;
    }

    if (strcmp(argv[1], "--install-command") == 0 || strcmp(argv[1], "--uninstall-command") == 0) {
        int uninstall = strcmp(argv[1], "--uninstall-command") == 0;
        for (int i = 2; i < argc; ++i) {
            if (strcmp(argv[i], "--install-destination") == 0) {
                install_destination = arg_value(argc, argv, &i, "--install-destination");
                if (install_destination == NULL) {
                    return 1;
                }
            } else {
                fprintf(stderr, "Unknown option: %s\n", argv[i]);
                usage(stderr);
                return 1;
            }
        }
        return uninstall
            ? (uninstall_command_line_tool(install_destination) ? 0 : 1)
            : (install_command_line_tool(argv[0], install_destination) ? 0 : 1);
    }

    file_path = argv[1];
    basename_without_extension(file_path, default_prefix, sizeof(default_prefix));
    memset(&options, 0, sizeof(options));
    options.out_dir = ".";
    options.prefix = default_prefix;
    options.channel_index = 0U;
    options.background_time_s = 0.0;

    if (argc == 2) {
        return launch_viewer(file_path, argv[0]) ? 0 : 1;
    }

    for (int i = 2; i < argc; ++i) {
        if (strcmp(argv[i], "--info") == 0) {
            show_info = 1;
        } else if (strcmp(argv[i], "--json") == 0) {
            as_json = 1;
        } else if (strcmp(argv[i], "--cv") == 0 || strcmp(argv[i], "-cv") == 0) {
            if (!parse_number_list_arguments(argc, argv, &i, &cv_times, argv[i])) {
                goto done_without_reader;
            }
        } else if (strcmp(argv[i], "--bg-cv") == 0 || strcmp(argv[i], "--background-cv") == 0) {
            if (!parse_number_list_arguments(argc, argv, &i, &background_cv_times, argv[i])) {
                goto done_without_reader;
            }
        } else if (strcmp(argv[i], "--it") == 0 || strcmp(argv[i], "-it") == 0) {
            if (!parse_number_list_arguments(argc, argv, &i, &it_voltages, argv[i])) {
                goto done_without_reader;
            }
        } else if (strcmp(argv[i], "--color") == 0) {
            export_color = 1;
        } else if (strcmp(argv[i], "--stdout") == 0) {
            options.stdout_export = 1;
        } else if (strcmp(argv[i], "--bg-subtract") == 0 || strcmp(argv[i], "--background-subtract") == 0) {
            options.background_subtract = 1;
        } else if (strcmp(argv[i], "--bandpass") == 0) {
            options.bandpass = 1;
        } else if (strcmp(argv[i], "--bg-time") == 0 || strcmp(argv[i], "--background-time") == 0) {
            const char *value = arg_value(argc, argv, &i, argv[i]);
            if (value == NULL) {
                goto done_without_reader;
            }
            options.background_time_s = strtod(value, NULL);
            if (!isfinite(options.background_time_s)) {
                fprintf(stderr, "Invalid background time: %s\n", value);
                goto done_without_reader;
            }
        } else if (strcmp(argv[i], "--time-range") == 0) {
            const char *value = arg_value(argc, argv, &i, "--time-range");
            if (value == NULL || !parse_double_range(value, &options.time_min_s, &options.time_max_s)) {
                fprintf(stderr, "Invalid --time-range. Use start:end in seconds.\n");
                goto done_without_reader;
            }
            options.has_time_range = 1;
        } else if (strcmp(argv[i], "--point-range") == 0) {
            const char *value = arg_value(argc, argv, &i, "--point-range");
            if (value == NULL || !parse_u32_range(value, &options.point_min, &options.point_max)) {
                fprintf(stderr, "Invalid --point-range. Use start:end point indexes.\n");
                goto done_without_reader;
            }
            options.has_point_range = 1;
        } else if (strcmp(argv[i], "--out") == 0) {
            options.out_dir = arg_value(argc, argv, &i, "--out");
            if (options.out_dir == NULL) {
                goto done_without_reader;
            }
        } else if (strcmp(argv[i], "--prefix") == 0) {
            options.prefix = arg_value(argc, argv, &i, "--prefix");
            if (options.prefix == NULL) {
                goto done_without_reader;
            }
        } else if (strcmp(argv[i], "--channel") == 0) {
            const char *value = arg_value(argc, argv, &i, "--channel");
            if (value == NULL) {
                goto done_without_reader;
            }
            options.channel_spec = value;
            options.channel_spec_zero_based = 0;
        } else if (strcmp(argv[i], "--phase") == 0) {
            const char *value = arg_value(argc, argv, &i, "--phase");
            if (value == NULL) {
                goto done_without_reader;
            }
            options.channel_spec = value;
            options.channel_spec_zero_based = 1;
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
    if (!parse_channel_spec(&reader, options.channel_spec, options.channel_spec_zero_based, &options.channel_index)) {
        fprintf(stderr,
            "Invalid channel %s. This file has %" PRIu32 " channels",
            options.channel_spec != NULL ? options.channel_spec : "",
            reader.layout.channel_count);
        if (reader.layout.channel_count > 0U) {
            fputs(": ", stderr);
            for (uint32_t i = 0U; i < reader.layout.channel_count; ++i) {
                fprintf(stderr, "%s%s", i > 0U ? ", " : "", hdcv_reader_channel_name(&reader, i));
            }
        }
        fputc('\n', stderr);
        goto done_with_reader;
    }
    if (options.channel_spec_zero_based) {
        fputs("--phase is deprecated; use --channel with a channel number or name.\n", stderr);
    }

    if (show_info) {
        status = hdcv_print_info(&reader, stdout, as_json) ? 0 : 1;
        goto done_with_reader;
    }

    if (cv_times.count == 0U && background_cv_times.count == 0U && it_voltages.count == 0U && !export_color) {
        hdcv_reader_close(&reader);
        status = launch_viewer(file_path, argv[0]) ? 0 : 1;
        goto done_without_reader;
    }

    if (options.stdout_export) {
        size_t stdout_export_count = cv_times.count + background_cv_times.count + it_voltages.count + (export_color ? 1U : 0U);
        if (stdout_export_count != 1U) {
            fputs("--stdout requires exactly one export target. Use one --cv time, one --bg-cv time, one --it voltage, or --color.\n", stderr);
            goto done_with_reader;
        }
    } else if (!ensure_directory(options.out_dir)) {
        goto done_with_reader;
    }
    if (!export_cv_list(&reader, &cv_times, &options, "CV", "CV", 0)) {
        goto done_with_reader;
    }
    if (!export_cv_list(&reader, &background_cv_times, &options, "background CV", "CV_bg", 1)) {
        goto done_with_reader;
    }
    if (!export_it_list(&reader, &it_voltages, &options)) {
        goto done_with_reader;
    }
    if (export_color && !write_color_csv(&reader, &options)) {
        goto done_with_reader;
    }
    status = 0;

done_with_reader:
    hdcv_reader_close(&reader);
done_without_reader:
    free_number_list(&cv_times);
    free_number_list(&background_cv_times);
    free_number_list(&it_voltages);
    return status;
}
