#ifndef HDCV_METADATA_H
#define HDCV_METADATA_H

#include "hdcv_types.h"

#include <stddef.h>
#include <stdint.h>

void hdcv_metadata_init(hdcv_metadata *metadata);
void hdcv_metadata_free(hdcv_metadata *metadata);
int hdcv_extract_metadata(
    const uint8_t *data,
    size_t size,
    hdcv_metadata *metadata,
    uint64_t *metadata_start,
    uint64_t *metadata_end,
    char *error,
    size_t error_size
);
const char *hdcv_metadata_get(
    const hdcv_metadata *metadata,
    const char *section,
    const char *key
);
int hdcv_metadata_get_double(
    const hdcv_metadata *metadata,
    const char *section,
    const char *key,
    double *out_value
);
int hdcv_metadata_get_uint32(
    const hdcv_metadata *metadata,
    const char *section,
    const char *key,
    uint32_t *out_value
);

#endif
