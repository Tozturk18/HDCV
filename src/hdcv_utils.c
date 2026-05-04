#include "hdcv_utils.h"

#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>

void hdcv_set_error(char *dst, size_t dst_size, const char *fmt, ...)
{
    va_list args;

    if (dst == NULL || dst_size == 0U) {
        return;
    }

    va_start(args, fmt);
    (void)vsnprintf(dst, dst_size, fmt, args);
    va_end(args);
}

char *hdcv_strdup(const char *src)
{
    size_t length;
    char *copy;

    if (src == NULL) {
        return NULL;
    }

    length = strlen(src);
    copy = (char *)malloc(length + 1U);
    if (copy == NULL) {
        return NULL;
    }
    memcpy(copy, src, length + 1U);
    return copy;
}

double hdcv_now_seconds(void)
{
    struct timespec ts;
    (void)clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + ((double)ts.tv_nsec / 1.0e9);
}

uint32_t hdcv_read_be_u32(const uint8_t *ptr)
{
    return ((uint32_t)ptr[0] << 24U) |
           ((uint32_t)ptr[1] << 16U) |
           ((uint32_t)ptr[2] << 8U) |
           (uint32_t)ptr[3];
}

uint64_t hdcv_read_be_u64(const uint8_t *ptr)
{
    return ((uint64_t)ptr[0] << 56U) |
           ((uint64_t)ptr[1] << 48U) |
           ((uint64_t)ptr[2] << 40U) |
           ((uint64_t)ptr[3] << 32U) |
           ((uint64_t)ptr[4] << 24U) |
           ((uint64_t)ptr[5] << 16U) |
           ((uint64_t)ptr[6] << 8U) |
           (uint64_t)ptr[7];
}

double hdcv_read_be_f64(const uint8_t *ptr)
{
    uint64_t bits = hdcv_read_be_u64(ptr);
    double value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

float hdcv_read_be_f32(const uint8_t *ptr)
{
    uint32_t bits = hdcv_read_be_u32(ptr);
    float value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

void hdcv_copy_be_f32_array(const uint8_t *src, float *dst, size_t count)
{
    size_t i;
    for (i = 0; i < count; ++i) {
        dst[i] = hdcv_read_be_f32(src + (i * 4U));
    }
}

void hdcv_write_le_u32(FILE *stream, uint32_t value)
{
    unsigned char out[4];
    out[0] = (unsigned char)(value & 0xffU);
    out[1] = (unsigned char)((value >> 8U) & 0xffU);
    out[2] = (unsigned char)((value >> 16U) & 0xffU);
    out[3] = (unsigned char)((value >> 24U) & 0xffU);
    (void)fwrite(out, 1U, sizeof(out), stream);
}

void hdcv_write_le_u64(FILE *stream, uint64_t value)
{
    unsigned char out[8];
    out[0] = (unsigned char)(value & 0xffU);
    out[1] = (unsigned char)((value >> 8U) & 0xffU);
    out[2] = (unsigned char)((value >> 16U) & 0xffU);
    out[3] = (unsigned char)((value >> 24U) & 0xffU);
    out[4] = (unsigned char)((value >> 32U) & 0xffU);
    out[5] = (unsigned char)((value >> 40U) & 0xffU);
    out[6] = (unsigned char)((value >> 48U) & 0xffU);
    out[7] = (unsigned char)((value >> 56U) & 0xffU);
    (void)fwrite(out, 1U, sizeof(out), stream);
}

void hdcv_write_le_f32(FILE *stream, float value)
{
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    hdcv_write_le_u32(stream, bits);
}

void hdcv_write_le_f64(FILE *stream, double value)
{
    uint64_t bits;
    memcpy(&bits, &value, sizeof(bits));
    hdcv_write_le_u64(stream, bits);
}

int hdcv_mkdir_p(const char *path, char *error, size_t error_size)
{
    char *mutable_path;
    size_t i;

    if (path == NULL || path[0] == '\0') {
        hdcv_set_error(error, error_size, "Output directory path is empty.");
        return 0;
    }

    mutable_path = hdcv_strdup(path);
    if (mutable_path == NULL) {
        hdcv_set_error(error, error_size, "Out of memory while creating directory path.");
        return 0;
    }

    for (i = 1; mutable_path[i] != '\0'; ++i) {
        if (mutable_path[i] == '/') {
            mutable_path[i] = '\0';
            if (mutable_path[0] != '\0' && mkdir(mutable_path, 0755) != 0 && errno != EEXIST) {
                hdcv_set_error(error, error_size, "mkdir(%s) failed: %s", mutable_path, strerror(errno));
                free(mutable_path);
                return 0;
            }
            mutable_path[i] = '/';
        }
    }

    if (mkdir(mutable_path, 0755) != 0 && errno != EEXIST) {
        hdcv_set_error(error, error_size, "mkdir(%s) failed: %s", mutable_path, strerror(errno));
        free(mutable_path);
        return 0;
    }

    free(mutable_path);
    return 1;
}
