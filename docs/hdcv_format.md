# HDCV v1001 Sample Format Note

This note documents what was verified directly in `DA_5uM_1.hdcv` and what remains inferred.

## Scope

Verified against:

- file: `DA_5uM_1.hdcv`
- software family: Pine Research WaveNeuro HDCV v1001

The format is proprietary. This note describes the sample-backed layout implemented by the C reader in this repository. It should be treated as version- and sample-qualified, not as a universal Pine spec.

## High-Level Layout

For the sample file, the file is organized as:

1. binary preamble
2. ASCII metadata block beginning at `[Core Cluster]`
3. first waveform-template header tail plus first full-cycle waveform data
4. three additional waveform-template headers and full-cycle waveform data blocks
5. current-matrix header
6. big-endian float32 current matrix

## Verified Offsets

Absolute offsets in the sample file:

- file size: `30,694,317` bytes
- metadata start: `161`
- metadata end at first NUL: `5897`
- first full-cycle waveform data start: `5929`
- second full-cycle waveform data start: `46025`
- third full-cycle waveform data start: `86121`
- fourth full-cycle waveform data start: `126217`
- current matrix start: `166317`

The current matrix therefore occupies:

- `30,694,317 - 166,317 = 30,528,000` bytes
- `30,528,000 / 4 = 7,632,000` float32 values
- `7,632,000 / 1060 = 7200` scans

## Metadata Fields Used

Important sample metadata fields:

- `SampRate = 100000.000000`
- `CVF = 10.000000`
- `Wavespecs.<size(s)> = 4`
- `Wavespecs 0.Data points per scan = 1060`
- `Wavespecs 0.V1 = -0.400000`
- `Wavespecs 0.V2 = 1.100000`
- `Wavespecs 0.Duration of scan (ms) = 10.600000`
- `Runs = 4`
- `Run duration = 180.000000`
- `Delay between runs = 1.000000`

## Waveform Template Blocks

### Verified properties

- The sample contains four identical full-cycle waveform templates.
- Each template contains `10000` big-endian float32 values.
- `10000 = SampRate / CVF = 100000 / 10`, so each template covers a full `100 ms` cycle.
- The first `1060` points are the active FSCV ramp.
- Points `1060..9999` are a hold at approximately `-0.4 V`.

### Scientific interpretation

This means the file stores both:

- the full commanded cycle voltage waveform at the raw sample rate
- the extracted active FSCV current matrix only for the `1060` ramp points

That distinction matters. The current matrix is not a `10000`-point full-cycle recording per scan.

### Header observations

Between the waveform blocks there are descriptor headers. The repeated full header seen before waveform blocks 2 through 4 is `96` bytes long and contains the ASCII token `RealPoints`.

A representative header suffix contains:

- `RealPoints`
- a big-endian `uint32` value `1060`
- a big-endian `float64` sample period `1e-5`
- a big-endian `uint32` full-cycle point count `10000`

The first waveform block header appears to begin before the metadata NUL boundary, so only its tail is plainly visible after `metadata_end`.

## Current Matrix Block

### Verified properties

- The current matrix begins at absolute offset `166317`.
- It is stored as big-endian float32.
- Matrix shape is `7200 x 1060`.
- Adjacent scans are highly correlated, as expected for sequential FSCV background-dominated traces.

### Header observations

Immediately before the current matrix is a `100`-byte header-like block. Its tail ends with:

- `1800`
- `4`
- `1060`

Those fields are consistent with:

- `1800 scans/run`
- `4 runs`
- `1060 points/scan`

`1800 * 4 = 7200`, which exactly matches the scan matrix length.

### Time-axis implication

The stored scan matrix contains `7200` scans, which corresponds to active FSCV acquisition only:

- `4 runs * 180 s/run * 10 scans/s = 7200 scans`

The 1-second inter-run delays are not represented as extra scan rows in the matrix itself.

As a result, two time axes are useful:

- sequence time: `scan_index / CVF`, contiguous from `0.0` to `719.9 s`
- experiment time: sequence time with the 1-second gaps restored between runs, from `0.0` to `722.9 s`

## Why The Existing Python Heuristic Was Not Enough

The existing `hdcv_decoder.py` script correctly finds and parses the metadata block, but its current-matrix inference is heuristic. On the sample file, the guessed offset lands too early and folds waveform-template bytes into the leading rows.

The C reader avoids that by:

1. using metadata-derived `SampRate`, `CVF`, and `Data points per scan`
2. locating the four full-cycle waveform blocks directly
3. locating the current matrix only after those blocks
4. validating that the resulting scan count matches run timing

## Units

The current matrix values are already float32 values in the file. No extra integer ADC scaling was identified in the sample. The existing Python tool labels them as current, and the magnitudes look consistent with nA-scale FSCV traces, but the file itself does not expose an extra scaling field used by the reader.

## Uncertainties

The following remain uncertain without more files or vendor documentation:

- whether the four waveform blocks correspond strictly to four `Wavespecs`, four runs, or both
- the meaning of several non-ASCII fields in the waveform and current headers
- whether all HDCV v1001 exports use the same partial first-wave header behavior at the metadata boundary
- whether multichannel acquisitions store additional current matrices or alternative interleaving schemes

The implementation is therefore conservative:

- it validates size and offsets before reading
- it uses the metadata and repeated block structure together
- it fails with a clear error if the expected block pattern is not found
