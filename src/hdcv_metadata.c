#include "hdcv_metadata.h"

#include "hdcv_utils.h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

static int metadata_push_entry(
    hdcv_metadata *metadata,
    const char *section,
    const char *key,
    const char *value,
    char *error,
    size_t error_size
)
{
    hdcv_metadata_entry *grown;
    size_t new_capacity;

    if (metadata->count == metadata->capacity) {
        new_capacity = metadata->capacity == 0U ? 32U : metadata->capacity * 2U;
        grown = (hdcv_metadata_entry *)realloc(metadata->entries, new_capacity * sizeof(*grown));
        if (grown == NULL) {
            hdcv_set_error(error, error_size, "Out of memory while parsing metadata.");
            return 0;
        }
        metadata->entries = grown;
        metadata->capacity = new_capacity;
    }

    metadata->entries[metadata->count].section = hdcv_strdup(section);
    metadata->entries[metadata->count].key = hdcv_strdup(key);
    metadata->entries[metadata->count].value = hdcv_strdup(value);
    if (metadata->entries[metadata->count].section == NULL ||
        metadata->entries[metadata->count].key == NULL ||
        metadata->entries[metadata->count].value == NULL) {
        hdcv_set_error(error, error_size, "Out of memory while storing metadata.");
        return 0;
    }

    metadata->count += 1U;
    return 1;
}

static const uint8_t *find_bytes(
    const uint8_t *haystack,
    size_t haystack_size,
    const uint8_t *needle,
    size_t needle_size
)
{
    size_t i;

    if (needle_size == 0U || haystack_size < needle_size) {
        return NULL;
    }

    for (i = 0U; i + needle_size <= haystack_size; ++i) {
        if (memcmp(haystack + i, needle, needle_size) == 0) {
            return haystack + i;
        }
    }
    return NULL;
}

static void trim_ascii(char *text)
{
    size_t length;
    size_t start;
    size_t end;

    if (text == NULL) {
        return;
    }

    length = strlen(text);
    start = 0U;
    while (start < length && isspace((unsigned char)text[start]) != 0) {
        start += 1U;
    }

    end = length;
    while (end > start && isspace((unsigned char)text[end - 1U]) != 0) {
        end -= 1U;
    }

    if (start > 0U) {
        memmove(text, text + start, end - start);
    }
    text[end - start] = '\0';
}

void hdcv_metadata_init(hdcv_metadata *metadata)
{
    memset(metadata, 0, sizeof(*metadata));
}

void hdcv_metadata_free(hdcv_metadata *metadata)
{
    size_t i;

    if (metadata == NULL) {
        return;
    }

    free(metadata->raw_text);
    metadata->raw_text = NULL;

    for (i = 0; i < metadata->count; ++i) {
        free(metadata->entries[i].section);
        free(metadata->entries[i].key);
        free(metadata->entries[i].value);
    }
    free(metadata->entries);

    metadata->entries = NULL;
    metadata->count = 0U;
    metadata->capacity = 0U;
    metadata->raw_length = 0U;
}

int hdcv_extract_metadata(
    const uint8_t *data,
    size_t size,
    hdcv_metadata *metadata,
    uint64_t *metadata_start,
    uint64_t *metadata_end,
    char *error,
    size_t error_size
)
{
    static const char marker[] = "[Core Cluster]";
    const uint8_t *start_ptr;
    const uint8_t *end_ptr;
    size_t length;
    char *cursor;
    char *parse_text;
    char *saveptr;
    char current_section[128];

    start_ptr = find_bytes(data, size, (const uint8_t *)marker, sizeof(marker) - 1U);
    if (start_ptr == NULL) {
        hdcv_set_error(error, error_size, "Could not locate [Core Cluster] metadata marker.");
        return 0;
    }

    end_ptr = (const uint8_t *)memchr(start_ptr, '\0', size - (size_t)(start_ptr - data));
    if (end_ptr == NULL) {
        hdcv_set_error(error, error_size, "Could not locate NUL terminator after metadata.");
        return 0;
    }

    length = (size_t)(end_ptr - start_ptr);
    metadata->raw_text = (char *)malloc(length + 1U);
    if (metadata->raw_text == NULL) {
        hdcv_set_error(error, error_size, "Out of memory while copying metadata text.");
        return 0;
    }
    memcpy(metadata->raw_text, start_ptr, length);
    metadata->raw_text[length] = '\0';
    metadata->raw_length = length;
    parse_text = hdcv_strdup(metadata->raw_text);
    if (parse_text == NULL) {
        hdcv_set_error(error, error_size, "Out of memory while preparing metadata parser.");
        return 0;
    }

    if (metadata_start != NULL) {
        *metadata_start = (uint64_t)(start_ptr - data);
    }
    if (metadata_end != NULL) {
        *metadata_end = (uint64_t)(end_ptr - data);
    }

    current_section[0] = '\0';
    cursor = parse_text;
    saveptr = NULL;
    for (;;) {
        char *line = strtok_r(cursor, "\n", &saveptr);
        char *equals;
        char *value;
        cursor = NULL;
        if (line == NULL) {
            break;
        }

        trim_ascii(line);
        if (line[0] == '\0') {
            continue;
        }
        if (line[0] == '[') {
            size_t section_length = strlen(line);
            if (section_length > 2U && line[section_length - 1U] == ']') {
                line[section_length - 1U] = '\0';
                (void)snprintf(current_section, sizeof(current_section), "%s", line + 1);
                trim_ascii(current_section);
            }
            continue;
        }

        equals = strchr(line, '=');
        if (equals == NULL) {
            continue;
        }

        *equals = '\0';
        value = equals + 1;
        trim_ascii(line);
        trim_ascii(value);
        if (value[0] == '"' && value[strlen(value) - 1U] == '"' && strlen(value) >= 2U) {
            value[strlen(value) - 1U] = '\0';
            value += 1;
        }

        if (!metadata_push_entry(metadata, current_section, line, value, error, error_size)) {
            free(parse_text);
            return 0;
        }
    }

    free(parse_text);
    return 1;
}

const char *hdcv_metadata_get(
    const hdcv_metadata *metadata,
    const char *section,
    const char *key
)
{
    size_t i;

    for (i = 0; i < metadata->count; ++i) {
        if ((section == NULL || strcmp(metadata->entries[i].section, section) == 0) &&
            strcmp(metadata->entries[i].key, key) == 0) {
            return metadata->entries[i].value;
        }
    }
    return NULL;
}

int hdcv_metadata_get_double(
    const hdcv_metadata *metadata,
    const char *section,
    const char *key,
    double *out_value
)
{
    const char *text = hdcv_metadata_get(metadata, section, key);
    char *endptr = NULL;
    double value;

    if (text == NULL) {
        return 0;
    }
    value = strtod(text, &endptr);
    if (endptr == text) {
        return 0;
    }
    *out_value = value;
    return 1;
}

int hdcv_metadata_get_uint32(
    const hdcv_metadata *metadata,
    const char *section,
    const char *key,
    uint32_t *out_value
)
{
    const char *text = hdcv_metadata_get(metadata, section, key);
    char *endptr = NULL;
    unsigned long value;

    if (text == NULL) {
        return 0;
    }
    value = strtoul(text, &endptr, 10);
    if (endptr == text) {
        return 0;
    }
    *out_value = (uint32_t)value;
    return 1;
}
