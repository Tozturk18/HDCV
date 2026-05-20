# HDCV v1001 Format Note

This note documents the HDCV v1001-style WaveNeuro layout implemented by the C reader. The format is proprietary, so these are dataset-backed observations rather than a vendor specification.

## Scope

Verified against local files under `/Users/tozturk/PhD/FSCV_Data`, including:

- `RATIO/DA/R10000_DA_5uM.hdcv`
- `RECT/RECT_P2_200UA.hdcv`
- `TRI/TRI_-0.4V_P2_200UA_2.hdcv`

The older `DA_5uM_1.hdcv` sample remains useful for offsets and single-file validation, but the broader local dataset corrects the old "phase" interpretation. The interleaved row families are recorded channels/electrodes.

## High-Level Layout

Files are organized as:

1. binary preamble
2. ASCII metadata block beginning at `[Core Cluster]`
3. first waveform-template header tail plus first full-cycle waveform data
4. additional waveform-template headers and full-cycle waveform data blocks
5. current-matrix header
6. big-endian float32 current matrix

## Metadata Fields Used

Important metadata fields:

- `Core Cluster/SampRate`: raw waveform sample rate
- `Core Cluster/CVF`: per-channel FSCV scan frequency
- `Setup Cluster/Wavespecs.<size(s)>`: recorded channel/electrode count
- `Setup Cluster/Wavespecs N.Name`: channel-associated names such as `Ramp0`, `Ramp1`
- `Setup Cluster/Wavespecs 0.Data points per scan`: active current points per scan
- `Setup Cluster/Wavespecs 0.V1`, `V2`, and `Duration of scan (ms)`: voltage-axis sanity checks

Numbered `Wavespecs N...` entries and physical waveform-template blocks are tracked separately from the recorded channel count.

## Waveform Template Blocks

Each physical waveform template contains `SampRate / CVF` big-endian float32 values. At `100000 Hz` and `10 Hz`, that is `10000` values for a full `100 ms` cycle.

The current matrix stores only the active FSCV ramp points, not the full `10000`-point commanded waveform. For example, rectangular files may store `1060` active current points per row while triangular files store `2300`, `2350`, or `2400`.

Some valid files declare `Wavespecs.<size(s)> = 3` but include numbered entries through `Wavespecs 3...` and physically store four contiguous waveform templates. The reader therefore:

- uses `Wavespecs.<size(s)>` as recorded channel count
- uses numbered WaveSpec entries only to estimate how many physical waveform templates to expect
- keeps detecting contiguous physical waveform-template blocks before locating the current matrix

## Current Matrix Block

The current matrix is stored as big-endian float32 rows of `points_per_scan` values.

The current-matrix header tail is interpreted as:

```text
samples_per_channel, channel_count, points_per_scan
```

Rows are interleaved by channel:

```text
row_index = sample_index * channel_count + channel_index
```

Sequence time is therefore:

```text
time_s = sample_index / CVF
```

not `row_index / CVF`.

## Dataset Evidence

All 26 `.hdcv` files under `/Users/tozturk/PhD/FSCV_Data` matched:

```text
current_matrix_rows == samples_per_channel * channel_count
```

Representative files:

| File | `Wavespecs.<size(s)>` | Numbered WaveSpecs | Physical templates | Header tail | Matrix rows |
| --- | ---: | ---: | ---: | --- | ---: |
| `RATIO/DA/R10000_DA_5uM.hdcv` | 4 | 4 | 4 | `1905, 4, 1501` | 7620 |
| `RECT/RECT_P2_200UA.hdcv` | 3 | 4 | 4 | `305, 3, 1060` | 915 |
| `TRI/TRI_-0.4V_P2_200UA_2.hdcv` | 3 | 4 | 4 | `947, 3, 2350` | 2841 |

The `RECT` and `TRI` examples are the clearest correction: they physically contain four waveform-template blocks, but the recorded current matrix has three interleaved channels.

## Background And Filtering

Background subtraction must be channel-local. A background row is aligned to the same channel modulo as the selected row, and overview traces use the first sample in the same channel as the fixed baseline.

Butterworth filtering is also channel-local. Because `CVF` is already the per-channel scan frequency, each channel trace is filtered at `CVF`, not at `CVF / channel_count`.

## Time Axes

Sequence time is contiguous per channel:

```text
sample_index / CVF
```

Experiment timing from `Run duration`, `Delay between runs`, and `Runs` is used only when the metadata-derived run structure matches `samples_per_channel`. Several local files have short captures where the header `samples_per_channel` does not match the configured run duration, so the reader preserves sequence time in those cases.

## Reader Strategy

The C reader avoids the old Python heuristic by:

1. parsing metadata-derived sample rate, CVF, channel count, and points per scan
2. locating physical full-cycle waveform-template blocks directly
3. locating the current matrix only after those physical templates
4. validating the matrix size against `samples_per_channel * channel_count`
5. exposing both physical template count and recorded channel count in `hdcv_layout`

## Units

The current matrix values are already float32 values in the file. No extra integer ADC scaling has been identified. The magnitudes are treated as nA-scale current values by the reader, CLI, viewer, and MATLAB wrapper.

## Remaining Uncertainties

- meaning of several non-ASCII fields in waveform and current headers
- whether all HDCV v1001 exports use the same partial first-wave header behavior at the metadata boundary
- whether future datasets can contain more physical waveform templates than numbered WaveSpecs

The implementation is conservative: it validates size and offsets before reading, keeps physical waveform-template detection separate from channel count, and fails with a clear error if the expected block pattern is not found.
