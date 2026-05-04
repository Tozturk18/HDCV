#include "hdcv_export.h"
#include "hdcv_reader.h"

#include <inttypes.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static void usage(FILE *stream)
{
    fputs("Usage:\n", stream);
    fputs("  hdcv_reader info <file.hdcv> [--json]\n", stream);
    fputs("  hdcv_reader export-scan <file.hdcv> --scan <index> --out <scan.csv>\n", stream);
    fputs("  hdcv_reader export-range <file.hdcv> --start <index> --end <index> --out <file> [--format hdcvbin|csv]\n", stream);
    fputs("  hdcv_reader validate <file.hdcv> --reference <reference_dir>\n", stream);
    fputs("  hdcv_reader benchmark <file.hdcv>\n", stream);
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

int main(int argc, char **argv)
{
    const char *command;
    const char *path;
    hdcv_reader reader;
    int status = 1;

    if (argc < 3) {
        usage(stderr);
        return 1;
    }

    command = argv[1];
    path = argv[2];

    if (!hdcv_reader_open(&reader, path)) {
        fprintf(stderr, "error: %s\n", reader.error);
        return 1;
    }

    if (strcmp(command, "info") == 0) {
        int as_json = 0;
        for (int i = 3; i < argc; ++i) {
            if (strcmp(argv[i], "--json") == 0) {
                as_json = 1;
            } else {
                fprintf(stderr, "Unknown option: %s\n", argv[i]);
                usage(stderr);
                goto done;
            }
        }
        status = hdcv_print_info(&reader, stdout, as_json) ? 0 : 1;
    } else if (strcmp(command, "export-scan") == 0) {
        uint32_t scan_index = UINT32_MAX;
        const char *out_path = NULL;
        for (int i = 3; i < argc; ++i) {
            if (strcmp(argv[i], "--scan") == 0) {
                const char *value = arg_value(argc, argv, &i, "--scan");
                if (value == NULL) {
                    goto done;
                }
                scan_index = (uint32_t)strtoul(value, NULL, 10);
            } else if (strcmp(argv[i], "--out") == 0) {
                out_path = arg_value(argc, argv, &i, "--out");
                if (out_path == NULL) {
                    goto done;
                }
            } else {
                fprintf(stderr, "Unknown option: %s\n", argv[i]);
                goto done;
            }
        }
        if (scan_index == UINT32_MAX || out_path == NULL) {
            usage(stderr);
            goto done;
        }
        status = hdcv_export_scan_csv(&reader, scan_index, out_path) ? 0 : 1;
    } else if (strcmp(command, "export-range") == 0) {
        uint32_t start_scan = UINT32_MAX;
        uint32_t end_scan = UINT32_MAX;
        const char *out_path = NULL;
        const char *format = "hdcvbin";
        for (int i = 3; i < argc; ++i) {
            if (strcmp(argv[i], "--start") == 0) {
                const char *value = arg_value(argc, argv, &i, "--start");
                if (value == NULL) {
                    goto done;
                }
                start_scan = (uint32_t)strtoul(value, NULL, 10);
            } else if (strcmp(argv[i], "--end") == 0) {
                const char *value = arg_value(argc, argv, &i, "--end");
                if (value == NULL) {
                    goto done;
                }
                end_scan = (uint32_t)strtoul(value, NULL, 10);
            } else if (strcmp(argv[i], "--out") == 0) {
                out_path = arg_value(argc, argv, &i, "--out");
                if (out_path == NULL) {
                    goto done;
                }
            } else if (strcmp(argv[i], "--format") == 0) {
                format = arg_value(argc, argv, &i, "--format");
                if (format == NULL) {
                    goto done;
                }
            } else {
                fprintf(stderr, "Unknown option: %s\n", argv[i]);
                goto done;
            }
        }
        if (start_scan == UINT32_MAX || end_scan == UINT32_MAX || out_path == NULL || end_scan < start_scan) {
            usage(stderr);
            goto done;
        }
        status = hdcv_export_range(&reader, start_scan, end_scan, format, out_path) ? 0 : 1;
    } else if (strcmp(command, "validate") == 0) {
        const char *reference_dir = NULL;
        for (int i = 3; i < argc; ++i) {
            if (strcmp(argv[i], "--reference") == 0) {
                reference_dir = arg_value(argc, argv, &i, "--reference");
                if (reference_dir == NULL) {
                    goto done;
                }
            } else {
                fprintf(stderr, "Unknown option: %s\n", argv[i]);
                goto done;
            }
        }
        if (reference_dir == NULL) {
            usage(stderr);
            goto done;
        }
        status = hdcv_validate_reference(&reader, reference_dir, stdout) ? 0 : 1;
    } else if (strcmp(command, "benchmark") == 0) {
        status = hdcv_run_benchmark(&reader, stdout) ? 0 : 1;
    } else {
        usage(stderr);
    }

done:
    hdcv_reader_close(&reader);
    return status;
}
