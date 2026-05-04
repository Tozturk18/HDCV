#ifndef HDCV_UTILS_H
#define HDCV_UTILS_H

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

void hdcv_set_error(char *dst, size_t dst_size, const char *fmt, ...);
char *hdcv_strdup(const char *src);
double hdcv_now_seconds(void);
uint32_t hdcv_read_be_u32(const uint8_t *ptr);
uint64_t hdcv_read_be_u64(const uint8_t *ptr);
double hdcv_read_be_f64(const uint8_t *ptr);
float hdcv_read_be_f32(const uint8_t *ptr);
void hdcv_copy_be_f32_array(const uint8_t *src, float *dst, size_t count);
void hdcv_write_le_u32(FILE *stream, uint32_t value);
void hdcv_write_le_u64(FILE *stream, uint64_t value);
void hdcv_write_le_f32(FILE *stream, float value);
void hdcv_write_le_f64(FILE *stream, double value);
int hdcv_mkdir_p(const char *path, char *error, size_t error_size);

#endif
