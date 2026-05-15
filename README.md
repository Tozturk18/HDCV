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

## Packaging For Sharing

The app can be packaged as a drag-install DMG and an app ZIP:

```bash
scripts/package_macos.sh --clean
```

This creates:

- `dist/HDCV_Viewer-<version>-arm64.dmg`
- `dist/HDCV_Viewer-<version>-arm64.app.zip`

The default package is ad-hoc signed and useful for local/internal testing. For smooth sharing on other people's Macs without Gatekeeper warnings, use an Apple Developer Program Developer ID Application certificate and notarize the package.

Create a notarytool profile once:

```bash
xcrun notarytool store-credentials hdcv-notary \
  --apple-id you@example.com \
  --team-id TEAMID \
  --password APP_SPECIFIC_PASSWORD
```

Then build a Developer ID signed and notarized package:

```bash
scripts/package_macos.sh --clean \
  --identity "Developer ID Application: Your Name (TEAMID)" \
  --notary-profile hdcv-notary \
  --notarize
```

For Intel plus Apple Silicon distribution, add `--universal`. The default remains `arm64`, matching the Apple Silicon target for this project.

Packaging details:

- the release bundle identifier is `com.tozturk.hdcvviewer`
- the app bundle embeds the `hdcv` CLI in `Contents/Resources/bin/hdcv`
- the package script signs the embedded CLI, the app executable, the app bundle, and the DMG
- notarized builds staple tickets to both the app and DMG
- the bundle exports the `.hdcv` document type so double-click and Open With work on fresh macOS installs
- the bundle declares macOS `11.0` or later, which matches the AppKit/UniformTypeIdentifiers API surface and Apple Silicon deployment target

## Commands

Inspect a file:

```bash
./build/hdcv_reader info DA_5uM_1.hdcv
./build/hdcv_reader info DA_5uM_1.hdcv --json
./build/hdcv DA_5uM_1.hdcv --info
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

Launch the native viewer or export MATLAB-ready CV files through the higher-level `hdcv` command:

```bash
./build/hdcv DA_5uM_1.hdcv
./build/hdcv DA_5uM_1.hdcv --cv 100,200,300 --out exports
./build/hdcv DA_5uM_1.hdcv -cv "[100, 200, 300]" --bg-cv 50 --out exports
./build/hdcv DA_5uM_1.hdcv --it 0.65 --bg-time 50 --bg-subtract --bandpass --out exports
./build/hdcv DA_5uM_1.hdcv --color --time-range 100:300 --point-range 0:1500 --out exports
./build/hdcv DA_5uM_1.hdcv --cv 100 --stdout
```

`hdcv --cv` exports one `voltage_V,current_nA` CSV per requested sequence-time value, using the nearest scan in the selected phase family. `--bg-cv` exports raw background CV files, `--it` exports selected-voltage `time_s,current_nA` traces, and `--color` exports long-form `time_s,current_nA,voltage_V` color plot data. `--bg-time`, `--bg-subtract`, and `--bandpass` apply the same phase-aware background subtraction and Butterworth processing model used by the viewer. The default phase is `0`, matching the viewer's single-phase default for interleaved WaveNeuro files; use `--phase <index>` when a different phase family is scientifically intended.

For MATLAB, shell pipelines, or other software that should not receive temporary CSV files, add `--stdout` to stream exactly one export to standard output. Status messages are written to standard error so the CSV stream stays clean:

```bash
hdcv DA_5uM_1.hdcv --cv 100 --stdout > cv_100s.csv
hdcv DA_5uM_1.hdcv --bg-cv 50 --stdout > cv_background_50s.csv
hdcv DA_5uM_1.hdcv --it 0.65 --stdout > it_0p65V.csv
hdcv DA_5uM_1.hdcv --color --time-range 100:101 --stdout > color_window.csv
```

`--stdout` is intentionally limited to one requested export at a time, because concatenating multiple CSV headers into one stream is ambiguous for downstream tools.

Release app bundles include the `hdcv` command inside `HDCV Viewer.app/Contents/Resources/bin/hdcv`. To make the command available as `hdcv` from Terminal, use `HDCV Viewer > Install hdcv Command in PATH...` from the app menu, or run:

```bash
./build/hdcv --install-command
```

The installer creates a VS Code-style symlink in the first writable standard `PATH` location and points it back to the command bundled with the app or the current debug build. It prefers `/usr/local/bin/hdcv`; on Apple Silicon systems where that is not writable but `/opt/homebrew/bin` is available, it uses `/opt/homebrew/bin/hdcv` automatically. Remove it with `HDCV Viewer > Uninstall hdcv Command...` or `hdcv --uninstall-command`.

## Native GUI

A native macOS AppKit viewer is now built with the same verified C parser:

```bash
./build/hdcv_viewer
./build/hdcv_viewer DA_5uM_1.hdcv
```

Release builds also produce a compact macOS app bundle:

```bash
open -n "build/HDCV Viewer.app"
open -n "build/HDCV Viewer.app" --args DA_5uM_1.hdcv
open -n -a "build/HDCV Viewer.app" DA_5uM_1.hdcv
```

The app bundle registers `.hdcv` files, so Finder double-click and Open With launch paths load the selected file directly.
It also embeds the `hdcv` command line tool and provides app-menu actions to install or uninstall the shell command in `/usr/local/bin`, similar to VS Code's `code` command workflow.

The viewer is optimized for the current system and uses the C reader directly rather than the old Python GUI path.

Current GUI features:

- native macOS window with open dialog and drag-and-drop file loading
- overview color plot built from a downsampled scan matrix
- selected `I-t` plot at the chosen waveform point
- selected `CV` plot at the chosen scan, preserving the full active waveform including custom repeated triangle cycles
- constant FSCV waveform plot from the decoded active voltage waveform, shown across the parser-reported full-cycle duration
- waveform-program table with WaveNeuro-style 10 voltage rows and 9 time rows; meaningful hold intervals are preserved and inactive entries are greyed out
- numeric crosshair controls in plot headers using axis units: time in seconds and voltage in volts
- direct axis editing by double-clicking visible plot min/max tick labels, typing a value, and pressing Return
- background subtraction for the color plot, `I-t`, and `CV`
- optional zero-phase Butterworth-style bandpass filter for the color plot, `I-t`, and `CV`
- MATLAB-friendly CSV export for the color plot, selected-voltage `I-t`, selected-time `CV`, raw background `CV`, and crosshair time lists
- bundled `hdcv` shell command for launching files and batch-exporting processed CV, background CV, `I-t`, and color plot CSVs from Terminal or MATLAB
- single-phase plotting for files that contain repeated interleaved WaveNeuro waveform phases
- synchronized vertical and horizontal crosshair lines across the plots
- drag-to-move crosshair lines on the color plot, `I-t`, and `CV` plots, including labeled `T#` CV-time and `B#` background-time markers
- sequence-time plotting
- editable color legend in nA for the overview color plot

Performance notes:

- file open and overview generation run off the main thread
- the heatmap is decimated for display rather than rendered at full scan-count width; display bins are balanced against repeated WaveNeuro template phases to avoid artificial column striping
- the current-vs-time trace for the selected waveform point is extracted asynchronously
- line plots render all visible samples when zoomed and use per-pixel min/max envelopes only for very dense ranges, so repeated scan phases are not hidden by stride aliasing
- scan selection updates the CV immediately from the mmap-backed reader

FSCV-specific interaction model:

- the color plot is the primary overview surface
- dragging color-plot crosshair lines updates both the `I-t` and `CV` plots
- dragging the `I-t` vertical crosshair moves the selected scan
- dragging the `CV` vertical crosshair moves the waveform point
- dragging inside the `I-t` or `CV` plot pans the visible axis range; MacBook trackpad pinch zooms around the pointer, and Option-scroll/Command-scroll zooms as a fallback
- each `I-t` and `CV` plot header includes a `Reset` button to return quickly to automatic scaling; trackpad smart zoom also resets the active line plot
- the waveform plot crosshair follows the selected waveform point; dragging its vertical line also moves the selected waveform point
- the background scan can be chosen explicitly, dragged in the color plot and `I-t` plot, or set from the current selected scan
- right-click the color plot or `I-t` plot to add linked CV-time or background-time crosshairs; compact bookmark badges label scan markers as `T1`, `T2`, ... and background markers as `B1`, `B2`, ...
- clicking or dragging `Tn` activates that selected time for the `CV` plot and uses `Bn` as its background when that background marker exists; when there is only one background marker, `B1` is shared by all `T` markers
- sequence time remains contiguous by scan index
- plot subtitles use compact coordinates with three decimal places: color plot `[time ; voltage ; current]`, `I-t` `[time ; current]`, and `CV` `[voltage ; current]`
- plot axis ranges are edited by double-clicking visible min/max tick labels; the color plot's current scale is edited the same way from the color legend labels
- color-plot voltage ticks prioritize waveform extrema and breakpoint/hold voltages while still adding proportional intermediate ticks; raw `I-t` current ranges are not forced to include zero, while background-subtracted `I-t` and the waveform plot keep zero visible when appropriate
- the color plot uses independent positive and negative current limits so asymmetric data ranges such as `+20 nA / -10 nA` are represented honestly instead of being forced into a symmetric legend
- the viewer preserves the full active voltage waveform reported by the parser, including custom repeated triangle cycles, and plots a single scan phase by default so `I-t` traces do not interleave multiple baseline families
- when background subtraction is enabled, the color plot and `I-t` plot subtract a fixed first-scan baseline within each displayed phase family, so moving the background marker does not reshape those overview traces; the visible background marker remains user-selected for the active `CV`, background `CV`, marker-time export, and MATLAB workflows
- the `CV` plot keeps the full active waveform intact, including custom repeated triangle cycles; to reduce point jitter without cropping, it averages matching 3-scan same-phase windows for the selected and background times, so selecting the same scan as background produces an exactly zero CV
- the waveform plot uses the active voltage axis decoded by the C reader; its display length comes from `waveform_full_points / sample_rate_hz`, and any time after the active custom waveform is shown as a hold at the first voltage
- the waveform-program table is read-only and inferred from voltage-axis intervals, matching WaveNeuro's 10-voltage/9-time custom-waveform convention without turning the viewer into waveform-authoring software; real holds become `0 V/s` rows, including one-sample holds between custom waveform segments
- editing the color-plot time bounds also updates the linked `I-t` time range, and editing the `I-t` time range updates the color-plot scan crop
- the bandpass filter uses a zero-phase two-pole high-pass and low-pass cascade; for interleaved phase files it filters each phase family independently at that phase family's effective sampling rate
- `Export Data` remembers the last selected plot checkboxes across launches and writes simple CSV files using the current plot processing state and active phase: color plot rows are `time_s,current_nA,voltage_V`, `I-t` rows are `time_s,current_nA` at the selected voltage crosshair, selected `CV` rows are `voltage_V,current_nA` at the active `T` marker, background `CV` rows are raw `voltage_V,current_nA` at the paired `B` marker, and marker-time rows are paired as `CV_times_s,BG_times_s,CV_scan_index,BG_scan_index`

## MATLAB Integration

The repository includes two MATLAB-friendly integration paths:

- `hdcv --stdout` streams one requested export directly into MATLAB through `system(...)`, avoiding temporary data folders.
- `matlab/hdcv_mex.c` builds an in-process MEX reader for CV extraction. It returns voltage and current matrices directly from the C parser, using the same selected phase and 3-scan same-phase averaging as the CLI CV export.

Build the MEX wrapper from MATLAB:

```matlab
addpath('/Users/tozturk/PhD/HDCV/matlab')
build_hdcv_mex
```

Then call it directly:

```matlab
out = hdcv_mex('/path/to/file.hdcv', [100 200 300], [50 50 50], 0);
voltage_V = out.voltage_V;
signal_current_nA = out.signal_current_nA(:, 1);
background_current_nA = out.background_current_nA(:, 1);
```

The current ratio workflow in `/Users/tozturk/PhD/FSCV_Data/RATIO/DA/RATIO.m` now prefers `hdcv_mex` when it is on the MATLAB path and falls back to `hdcv --stdout` otherwise, so the analysis can run with only the `.m` file and `.hdcv` file in the study folder.

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
