# HDCV Decoder (Best-Effort)

This folder now contains a Python decoder for Pine Research HDCV `.hdcv` files:

- `hdcv_decoder.py`

It reverse-engineers these files by extracting metadata, detecting the waveform axis, and heuristically decoding current scans into a matrix that can be analyzed directly.

## What It Produces

For an input file `example.hdcv`, it writes to `example_decoded/`:

- `metadata_raw.txt` (original metadata block as text)
- `metadata_parsed.json` (sectioned metadata)
- `decode_summary.json` (detected offsets, types, sizes)
- `voltage_waveform.npy`
- `time_axis_s.npy`
- `current_matrix_raw.npy`
- `current_matrix.npy` (outlier-cleaned)
- Optional CSV exports:
  - `voltage_waveform.csv`
  - `time_axis_s.csv`
  - `current_matrix.csv`

## Install Dependencies

Use the same Python interpreter you use to run the script:

```bash
python -m pip install numpy matplotlib
```

## Run

```bash
python hdcv_decoder.py DA_5uM_1.hdcv
```

This opens an interactive viewer with:

- FSCV color plot (time vs voltage, color=current)
- Current vs time at selected voltage
- CV plot (current vs voltage) at selected time

Crosshair lines are draggable on all three plots. Moving them in any plot updates the corresponding crosshair position in the other plots.

## Useful Flags

```bash
python hdcv_decoder.py DA_5uM_1.hdcv --no-viewer
python hdcv_decoder.py DA_5uM_1.hdcv --no-csv
python hdcv_decoder.py DA_5uM_1.hdcv --out my_output_folder
python hdcv_decoder.py DA_5uM_1.hdcv --no-cache
```

## Performance

- The first run decodes and writes cache files to `<input>_decoded/`.
- Re-running on the same unchanged input automatically reuses cached arrays, which is much faster.

## Notes

- The HDCV file format is proprietary and may vary by software version.
- This decoder is robust for the provided sample and intended as a practical reverse-engineering base.
- If another file decodes poorly, share its `decode_summary.json` and we can refine the detection heuristics.
