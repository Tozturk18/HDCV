# HDCV Reader

Fast C parser and CLI for large Pine Research WaveNeuro `.hdcv` FSCV files, built from the local Python decoder and then re-verified directly against the sample binary in this repository.

The current implementation is validated on `DA_5uM_1.hdcv` and targets the HDCV v1001-style layout seen in that file:

- text metadata block
- four full-cycle waveform template blocks
- one current-matrix header
- big-endian float32 current matrix

It is designed for streaming, mmap-backed scan access, and macOS/Apple Silicon builds.

## Repository Findings

The Python file [`hdcv_decoder.py`](hdcv_decoder.py) contains both parser and GUI logic.

- Parsing entrypoints: `extract_metadata_block`, `parse_metadata`, `find_waveform`, `guess_current_matrix`, `decode_hdcv`
- GUI/viewer entrypoints: `_open_file_dialog`, `launch_viewer`, `decode_file`, `main`

For the sample file, the Python metadata extraction is useful, but the current-matrix offset is heuristic. The C reader uses a verified layout instead:

- metadata starts at byte `161`
- metadata ends at byte `5897`
- active FSCV points per scan: `1060`
- full-cycle waveform points: `10000`
- current matrix offset: `166317`
- current matrix shape: `7200 x 1060`

That `7200`-scan count matches `4 runs x 180 s x 10 Hz`. The reader also reconstructs an experiment-time axis with the 1-second inter-run gaps restored, so sequence time and wall-clock experiment time stay distinct.

## Build

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j4
```

Debug build with sanitizers:

```bash
cmake -S . -B build-debug -DCMAKE_BUILD_TYPE=Debug
cmake --build build-debug -j4
```

## Commands

Inspect a file:

```bash
./build/hdcv_reader info DA_5uM_1.hdcv
./build/hdcv_reader info DA_5uM_1.hdcv --json
```

Export a single scan:

```bash
./build/hdcv_reader export-scan DA_5uM_1.hdcv --scan 100 --out scan_100.csv
```

Export a scan range:

```bash
./build/hdcv_reader export-range DA_5uM_1.hdcv --start 0 --end 999 --out scans.hdcvbin
./build/hdcv_reader export-range DA_5uM_1.hdcv --start 0 --end 9 --format csv --out scans.csv
```

Benchmark the scan-matrix stream:

```bash
./build/hdcv_reader benchmark DA_5uM_1.hdcv
```

## Native GUI

A native macOS AppKit viewer is now built with the same verified C parser:

```bash
./build/hdcv_viewer
./build/hdcv_viewer DA_5uM_1.hdcv
```

The viewer is optimized for the current system and uses the C reader directly rather than the old Python GUI path.

Current GUI features:

- native macOS window with Open dialog
- overview heatmap built from a downsampled scan matrix
- selected current-vs-time trace
- selected cyclic voltammogram
- scan slider and waveform-point slider
- click-to-select on the heatmap
- sequence-time vs experiment-time toggle
- summary plus raw metadata panel

Performance notes:

- file open and overview generation run off the main thread
- the heatmap is decimated for display rather than rendered at full scan-count width
- the current-vs-time trace for the selected waveform point is extracted asynchronously
- scan selection updates the CV immediately from the mmap-backed reader

## Validation Workflow

Generate a strict Python reference bundle:

```bash
python3 tools/hdcv_reference_export.py DA_5uM_1.hdcv --out reference_bundle
```

Validate the C reader against that bundle:

```bash
./build/hdcv_reader validate DA_5uM_1.hdcv --reference reference_bundle
```

The bundle contains:

- `manifest.txt`
- `metadata.txt`
- `voltage_active.f32`
- `scan_first.f32`
- `scan_middle.f32`
- `scan_last.f32`

The C validator compares:

- scan count
- points per scan
- active voltage axis
- first, middle, and last current scans

On the sample file in this workspace, the validator reports exact agreement:

- `scan_count: C=7200 reference=7200`
- `points_per_scan: C=1060 reference=1060`
- `voltage max_abs_diff: 0`
- `first scan max_abs_diff: 0`
- `middle scan max_abs_diff: 0`
- `last scan max_abs_diff: 0`

## Export Format

`export-range` defaults to a compact custom binary container: `HDCVBIN1`.

Layout:

1. 8-byte magic: `HDCVBIN1`
2. little-endian header with counts and timing
3. active voltage axis as little-endian `float32[points_per_scan]`
4. current matrix as little-endian row-major `float32[scan_count][points_per_scan]`

This is much more practical than full-dataset CSV for multi-GB experiments.

## Local Benchmarks

Measured in this workspace on `DA_5uM_1.hdcv`:

- Existing `hdcv_decoder.py --no-viewer`: `61.41 s`
- Strict Python reference bundle export: `0.06 s`
- `./build/hdcv_reader benchmark`: `0.008493 s` to stream and checksum the full `30,528,000`-byte current matrix, about `3428 MB/s`

Benchmark caveat:

- the existing Python decoder is doing heuristic waveform and matrix offset search
- the strict Python reference exporter and the C reader both use the verified sample layout
- the C benchmark measures matrix streaming after the reader has already mapped the file and resolved the layout

## Technical Note

Format details, verified offsets, and remaining uncertainties are documented in [docs/hdcv_format.md](docs/hdcv_format.md).
