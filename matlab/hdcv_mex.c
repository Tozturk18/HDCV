#include "hdcv_analysis.h"
#include "hdcv_reader.h"

#include "mex.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define HDCV_MEX_CV_HALF_WINDOW 1U

static double scan_interval_s(const hdcv_reader *reader)
{
    double interval = reader->layout.scan_interval_s;
    if (!(interval > 0.0) && reader->layout.cvf_hz > 0.0) {
        interval = 1.0 / reader->layout.cvf_hz;
    }
    if (!(interval > 0.0)) {
        interval = 0.1;
    }
    return interval;
}

static uint32_t scan_for_time_raw(const hdcv_reader *reader, double time_s)
{
    double raw_scan = round(time_s / scan_interval_s(reader));

    if (reader->layout.scan_count == 0U || !mxIsFinite(raw_scan) || raw_scan < 0.0) {
        return 0U;
    }
    if (raw_scan > (double)(reader->layout.scan_count - 1U)) {
        return reader->layout.scan_count - 1U;
    }
    return (uint32_t)raw_scan;
}

static uint32_t nearest_scan_for_time(const hdcv_reader *reader, double time_s, uint32_t phase_index)
{
    return hdcv_analysis_nearest_scan_index_for_phase(
        scan_for_time_raw(reader, time_s),
        reader->layout.scan_count,
        phase_index,
        reader->layout.waveform_count
    );
}

static int copy_average_scan(
    const hdcv_reader *reader,
    uint32_t center_scan,
    uint32_t phase_index,
    uint32_t phase_period,
    uint32_t half_window,
    float *destination,
    float *scratch,
    double *sums
)
{
    uint32_t points_per_scan = reader->layout.points_per_scan;
    uint32_t center = hdcv_analysis_nearest_scan_index_for_phase(center_scan, reader->layout.scan_count, phase_index, phase_period);
    int64_t start = (int64_t)center - ((int64_t)half_window * (int64_t)phase_period);
    int64_t end = (int64_t)center + ((int64_t)half_window * (int64_t)phase_period);
    uint32_t used_count = 0U;

    memset(sums, 0, (size_t)points_per_scan * sizeof(*sums));
    while (start < 0) {
        start += (int64_t)phase_period;
    }
    while (end >= (int64_t)reader->layout.scan_count) {
        end -= (int64_t)phase_period;
    }
    for (int64_t local_scan = start; local_scan <= end; local_scan += (int64_t)phase_period) {
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

static const double *checked_double_vector(const mxArray *array, const char *name, mwSize *out_count)
{
    if (!mxIsDouble(array) || mxIsComplex(array)) {
        mexErrMsgIdAndTxt("hdcv_mex:InvalidInput", "%s must be a real double vector.", name);
    }
    if (mxGetM(array) != 1U && mxGetN(array) != 1U && mxGetNumberOfElements(array) != 0U) {
        mexErrMsgIdAndTxt("hdcv_mex:InvalidInput", "%s must be a vector.", name);
    }
    *out_count = mxGetNumberOfElements(array);
    return mxGetPr(array);
}

static uint32_t checked_phase_index(const mxArray *array)
{
    double value;
    if (!mxIsDouble(array) || mxIsComplex(array) || mxGetNumberOfElements(array) != 1U) {
        mexErrMsgIdAndTxt("hdcv_mex:InvalidInput", "phaseIndex must be a real double scalar.");
    }
    value = mxGetScalar(array);
    if (!mxIsFinite(value) || value < 0.0 || value > (double)UINT32_MAX || floor(value) != value) {
        mexErrMsgIdAndTxt("hdcv_mex:InvalidInput", "phaseIndex must be a nonnegative integer.");
    }
    return (uint32_t)value;
}

static void fill_cv_matrix(
    const hdcv_reader *reader,
    const double *times,
    mwSize time_count,
    uint32_t active_phase,
    uint32_t phase_period,
    mxArray *matrix_array,
    mxArray *actual_times_array,
    mxArray *scan_indices_array
)
{
    mwSize points_per_scan = (mwSize)reader->layout.points_per_scan;
    double *matrix = mxGetPr(matrix_array);
    double *actual_times = mxGetPr(actual_times_array);
    double *scan_indices = mxGetPr(scan_indices_array);
    float *average = (float *)mxMalloc((size_t)points_per_scan * sizeof(*average));
    float *scratch = (float *)mxMalloc((size_t)points_per_scan * sizeof(*scratch));
    double *sums = (double *)mxMalloc((size_t)points_per_scan * sizeof(*sums));

    if (average == NULL || scratch == NULL || sums == NULL) {
        mxFree(average);
        mxFree(scratch);
        mxFree(sums);
        mexErrMsgIdAndTxt("hdcv_mex:OutOfMemory", "Could not allocate CV buffers.");
    }

    for (mwSize column = 0U; column < time_count; ++column) {
        uint32_t scan_index = nearest_scan_for_time(reader, times[column], active_phase);
        if (!copy_average_scan(
                reader,
                scan_index,
                active_phase,
                phase_period,
                HDCV_MEX_CV_HALF_WINDOW,
                average,
                scratch,
                sums)) {
            mxFree(average);
            mxFree(scratch);
            mxFree(sums);
            mexErrMsgIdAndTxt("hdcv_mex:ReadFailed", "Could not read CV data from the HDCV file.");
        }
        for (mwSize row = 0U; row < points_per_scan; ++row) {
            matrix[row + (points_per_scan * column)] = (double)average[row];
        }
        actual_times[column] = hdcv_reader_scan_time_sequence_s(reader, scan_index);
        scan_indices[column] = (double)scan_index;
    }

    mxFree(average);
    mxFree(scratch);
    mxFree(sums);
}

void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    static const char *field_names[] = {
        "voltage_V",
        "signal_current_nA",
        "background_current_nA",
        "signal_time_s",
        "background_time_s",
        "signal_scan_index",
        "background_scan_index",
        "points_per_scan",
        "scan_count",
        "phase_index",
        "phase_period",
        "cvf_Hz"
    };
    enum {
        FIELD_VOLTAGE = 0,
        FIELD_SIGNAL_CURRENT,
        FIELD_BACKGROUND_CURRENT,
        FIELD_SIGNAL_TIME,
        FIELD_BACKGROUND_TIME,
        FIELD_SIGNAL_SCAN,
        FIELD_BACKGROUND_SCAN,
        FIELD_POINTS_PER_SCAN,
        FIELD_SCAN_COUNT,
        FIELD_PHASE_INDEX,
        FIELD_PHASE_PERIOD,
        FIELD_CVF_HZ
    };

    char *path = NULL;
    const double *signal_times = NULL;
    const double *background_times = NULL;
    mwSize signal_count = 0U;
    mwSize background_count = 0U;
    uint32_t phase_index = 0U;
    uint32_t phase_period;
    uint32_t active_phase;
    hdcv_reader reader;
    mxArray *out;
    mxArray *voltage_array;
    mxArray *signal_matrix;
    mxArray *background_matrix;
    mxArray *signal_times_array;
    mxArray *background_times_array;
    mxArray *signal_scans_array;
    mxArray *background_scans_array;
    double *voltage;
    float *voltage_float;
    mwSize points_per_scan;

    if (nlhs > 1) {
        mexErrMsgIdAndTxt("hdcv_mex:InvalidOutput", "hdcv_mex returns one struct output.");
    }
    if (nrhs < 2 || nrhs > 4) {
        mexErrMsgIdAndTxt(
            "hdcv_mex:InvalidInput",
            "Usage: out = hdcv_mex(filePath, signalTimes_s, backgroundTimes_s, phaseIndex)");
    }
    if (!mxIsChar(prhs[0])) {
        mexErrMsgIdAndTxt("hdcv_mex:InvalidInput", "filePath must be a string.");
    }

    path = mxArrayToString(prhs[0]);
    if (path == NULL) {
        mexErrMsgIdAndTxt("hdcv_mex:InvalidInput", "Could not read filePath.");
    }
    signal_times = checked_double_vector(prhs[1], "signalTimes_s", &signal_count);
    if (nrhs >= 3 && !mxIsEmpty(prhs[2])) {
        background_times = checked_double_vector(prhs[2], "backgroundTimes_s", &background_count);
    }
    if (nrhs >= 4) {
        phase_index = checked_phase_index(prhs[3]);
    }

    if (background_count != 0U && background_count != signal_count) {
        mxFree(path);
        mexErrMsgIdAndTxt("hdcv_mex:InvalidInput", "backgroundTimes_s must be empty or match signalTimes_s length.");
    }

    if (!hdcv_reader_open(&reader, path)) {
        char message[512];
        snprintf(message, sizeof(message), "Could not open HDCV file: %s", reader.error);
        mxFree(path);
        mexErrMsgIdAndTxt("hdcv_mex:OpenFailed", "%s", message);
    }
    mxFree(path);

    phase_period = reader.layout.waveform_count == 0U ? 1U : reader.layout.waveform_count;
    active_phase = phase_index % phase_period;
    points_per_scan = (mwSize)reader.layout.points_per_scan;

    out = mxCreateStructMatrix(1, 1, (int)(sizeof(field_names) / sizeof(field_names[0])), field_names);
    voltage_array = mxCreateDoubleMatrix(points_per_scan, 1, mxREAL);
    signal_matrix = mxCreateDoubleMatrix(points_per_scan, signal_count, mxREAL);
    background_matrix = mxCreateDoubleMatrix(points_per_scan, background_count, mxREAL);
    signal_times_array = mxCreateDoubleMatrix(1, signal_count, mxREAL);
    background_times_array = mxCreateDoubleMatrix(1, background_count, mxREAL);
    signal_scans_array = mxCreateDoubleMatrix(1, signal_count, mxREAL);
    background_scans_array = mxCreateDoubleMatrix(1, background_count, mxREAL);
    voltage_float = (float *)mxMalloc((size_t)points_per_scan * sizeof(*voltage_float));

    if (out == NULL || voltage_array == NULL || signal_matrix == NULL || background_matrix == NULL ||
        signal_times_array == NULL || background_times_array == NULL || signal_scans_array == NULL ||
        background_scans_array == NULL || voltage_float == NULL) {
        hdcv_reader_close(&reader);
        mexErrMsgIdAndTxt("hdcv_mex:OutOfMemory", "Could not allocate MATLAB output arrays.");
    }
    if (!hdcv_reader_copy_voltage(&reader, voltage_float, points_per_scan)) {
        mxFree(voltage_float);
        hdcv_reader_close(&reader);
        mexErrMsgIdAndTxt("hdcv_mex:ReadFailed", "Could not read voltage axis from the HDCV file.");
    }
    voltage = mxGetPr(voltage_array);
    for (mwSize row = 0U; row < points_per_scan; ++row) {
        voltage[row] = (double)voltage_float[row];
    }
    mxFree(voltage_float);

    fill_cv_matrix(&reader, signal_times, signal_count, active_phase, phase_period, signal_matrix, signal_times_array, signal_scans_array);
    if (background_count > 0U) {
        fill_cv_matrix(&reader, background_times, background_count, active_phase, phase_period, background_matrix, background_times_array, background_scans_array);
    }

    mxSetFieldByNumber(out, 0, FIELD_VOLTAGE, voltage_array);
    mxSetFieldByNumber(out, 0, FIELD_SIGNAL_CURRENT, signal_matrix);
    mxSetFieldByNumber(out, 0, FIELD_BACKGROUND_CURRENT, background_matrix);
    mxSetFieldByNumber(out, 0, FIELD_SIGNAL_TIME, signal_times_array);
    mxSetFieldByNumber(out, 0, FIELD_BACKGROUND_TIME, background_times_array);
    mxSetFieldByNumber(out, 0, FIELD_SIGNAL_SCAN, signal_scans_array);
    mxSetFieldByNumber(out, 0, FIELD_BACKGROUND_SCAN, background_scans_array);
    mxSetFieldByNumber(out, 0, FIELD_POINTS_PER_SCAN, mxCreateDoubleScalar((double)reader.layout.points_per_scan));
    mxSetFieldByNumber(out, 0, FIELD_SCAN_COUNT, mxCreateDoubleScalar((double)reader.layout.scan_count));
    mxSetFieldByNumber(out, 0, FIELD_PHASE_INDEX, mxCreateDoubleScalar((double)active_phase));
    mxSetFieldByNumber(out, 0, FIELD_PHASE_PERIOD, mxCreateDoubleScalar((double)phase_period));
    mxSetFieldByNumber(out, 0, FIELD_CVF_HZ, mxCreateDoubleScalar(reader.layout.cvf_hz));

    hdcv_reader_close(&reader);
    plhs[0] = out;
}
