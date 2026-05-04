#ifndef HDCV_EXPORT_H
#define HDCV_EXPORT_H

#include "hdcv_types.h"

#include <stdint.h>
#include <stdio.h>

int hdcv_print_info(const hdcv_reader *reader, FILE *out, int as_json);
int hdcv_export_scan_csv(const hdcv_reader *reader, uint32_t scan_index, const char *out_path);
int hdcv_export_range(
    const hdcv_reader *reader,
    uint32_t start_scan,
    uint32_t end_scan,
    const char *format,
    const char *out_path
);
int hdcv_validate_reference(const hdcv_reader *reader, const char *reference_dir, FILE *out);
int hdcv_run_benchmark(const hdcv_reader *reader, FILE *out);

#endif
