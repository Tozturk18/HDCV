#!/usr/bin/env python3
"""Emit a strict reference bundle for validated HDCV v1001 files.

This is intentionally separate from `hdcv_decoder.py`.
The existing decoder is a useful reverse-engineering aid, but its current-matrix
offset for the sample file is heuristic. This script uses the sample-verified
layout that the C parser also follows:

- text metadata block
- four 10,000-point full-cycle waveform templates
- one current-matrix header
- big-endian float32 current matrix
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np


def extract_metadata_block(raw: bytes) -> Tuple[str, int, int]:
    start = raw.find(b"[Core Cluster]")
    if start < 0:
        raise ValueError("Could not locate [Core Cluster] metadata.")
    end = raw.find(b"\x00", start)
    if end < 0:
        raise ValueError("Could not locate metadata terminator.")
    return raw[start:end].decode("utf-8", errors="ignore"), start, end


def parse_metadata(text: str) -> Dict[str, Dict[str, str]]:
    sections: Dict[str, Dict[str, str]] = {}
    current = "ROOT"
    sections[current] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1].strip()
            sections.setdefault(current, {})
            continue
        if "=" in line:
            key, value = line.split("=", 1)
            sections.setdefault(current, {})[key.strip()] = value.strip().strip('"')
    return sections


def get_float(metadata: Dict[str, Dict[str, str]], section: str, key: str) -> float:
    return float(metadata[section][key])


def get_int(metadata: Dict[str, Dict[str, str]], section: str, key: str) -> int:
    return int(round(float(metadata[section][key])))


def find_layout(raw: bytes, metadata: Dict[str, Dict[str, str]], metadata_end: int) -> Dict[str, object]:
    sample_rate = get_float(metadata, "Core Cluster", "SampRate")
    cvf = get_float(metadata, "Core Cluster", "CVF")
    points_per_scan = get_int(metadata, "Setup Cluster", "Wavespecs 0.Data points per scan")
    waveform_count = get_int(metadata, "Setup Cluster", "Wavespecs.<size(s)>")
    run_count = get_int(metadata, "Experiment control cluster", "Runs")
    run_duration_s = get_float(metadata, "Experiment control cluster", "Run duration")
    delay_between_runs_s = get_float(metadata, "Experiment control cluster", "Delay between runs")

    full_wave_points = int(round(sample_rate / cvf))
    dt = 1.0 / sample_rate

    def find_full_wave_count(search_start: int, search_end: int) -> int:
        for off in range(search_start + 8, min(search_end, len(raw) - 4)):
            if int.from_bytes(raw[off:off + 4], "big") != full_wave_points:
                continue
            maybe_dt = struct.unpack(">d", raw[off - 8:off])[0]
            if abs(maybe_dt - dt) <= 1e-12:
                return off
        raise ValueError("Could not locate waveform count marker.")

    first_count_offset = find_full_wave_count(metadata_end, metadata_end + 256)
    wave_data_offsets: List[int] = [first_count_offset + 4]
    for _ in range(1, waveform_count):
        prev_end = wave_data_offsets[-1] + (full_wave_points * 4)
        count_offset = find_full_wave_count(prev_end, prev_end + 256)
        wave_data_offsets.append(count_offset + 4)

    last_wave_end = wave_data_offsets[-1] + (full_wave_points * 4)
    expected_scans_per_run = int(round(run_duration_s * cvf))
    expected_scan_count = expected_scans_per_run * run_count
    row_bytes = points_per_scan * 4

    best = None
    for off in range(last_wave_end, min(last_wave_end + 512, len(raw) - 4)):
        if int.from_bytes(raw[off:off + 4], "big") != points_per_scan:
            continue
        data_offset = off + 4
        remaining = len(raw) - data_offset
        if remaining % row_bytes != 0:
            continue
        scan_count = remaining // row_bytes
        sample = np.frombuffer(raw, dtype=">f4", count=min(2, scan_count) * points_per_scan, offset=data_offset)
        if sample.size < 2 * points_per_scan:
            continue
        sample = sample.reshape(min(2, scan_count), points_per_scan).astype(np.float64)
        corr = np.corrcoef(sample[0], sample[1])[0, 1]
        score = corr * 1000.0
        score += min(sample[0].std(), 1000.0) + min(sample[1].std(), 1000.0)
        if scan_count == expected_scan_count:
            score += 10000.0
        if best is None or score > best[0]:
            best = (score, off, data_offset, scan_count)

    if best is None:
        raise ValueError("Could not locate current matrix.")

    _, current_count_offset, current_matrix_offset, scan_count = best
    header_scans_per_run = int.from_bytes(raw[current_matrix_offset - 12:current_matrix_offset - 8], "big")
    header_run_count = int.from_bytes(raw[current_matrix_offset - 8:current_matrix_offset - 4], "big")
    header_points = int.from_bytes(raw[current_matrix_offset - 4:current_matrix_offset], "big")
    if header_points != points_per_scan:
        raise ValueError("Current header tail does not end with points-per-scan.")

    return {
        "sample_rate_hz": sample_rate,
        "cvf_hz": cvf,
        "points_per_scan": points_per_scan,
        "waveform_count": waveform_count,
        "full_wave_points": full_wave_points,
        "wave_data_offsets": wave_data_offsets,
        "current_count_offset": current_count_offset,
        "current_matrix_offset": current_matrix_offset,
        "scan_count": scan_count,
        "run_count": header_run_count,
        "scans_per_run": header_scans_per_run,
        "run_duration_s": run_duration_s,
        "delay_between_runs_s": delay_between_runs_s,
        "v1_v": get_float(metadata, "Setup Cluster", "Wavespecs 0.V1"),
        "v2_v": get_float(metadata, "Setup Cluster", "Wavespecs 0.V2"),
    }


def write_manifest(path: Path, values: Dict[str, object]) -> None:
    lines = [f"{key}={value}" for key, value in values.items()]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Export a strict validation bundle for an HDCV file.")
    parser.add_argument("input", type=Path, help="Path to the .hdcv file")
    parser.add_argument("--out", type=Path, required=True, help="Output directory")
    args = parser.parse_args()

    raw = args.input.read_bytes()
    metadata_text, metadata_start, metadata_end = extract_metadata_block(raw)
    metadata = parse_metadata(metadata_text)
    layout = find_layout(raw, metadata, metadata_end)

    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "metadata.txt").write_text(metadata_text, encoding="utf-8")

    voltage = np.frombuffer(
        raw,
        dtype=">f4",
        count=int(layout["points_per_scan"]),
        offset=int(layout["wave_data_offsets"][0]),
    ).astype("<f4")
    voltage.tofile(args.out / "voltage_active.f32")

    matrix = np.memmap(
        args.input,
        dtype=">f4",
        mode="r",
        offset=int(layout["current_matrix_offset"]),
        shape=(int(layout["scan_count"]), int(layout["points_per_scan"])),
    )

    first_idx = 0
    middle_idx = int(layout["scan_count"]) // 2
    last_idx = int(layout["scan_count"]) - 1
    matrix[first_idx].astype("<f4").tofile(args.out / "scan_first.f32")
    matrix[middle_idx].astype("<f4").tofile(args.out / "scan_middle.f32")
    matrix[last_idx].astype("<f4").tofile(args.out / "scan_last.f32")

    manifest = {
        "file": str(args.input.resolve()),
        "file_size_bytes": len(raw),
        "metadata_start_offset": metadata_start,
        "metadata_end_offset": metadata_end,
        "first_wave_data_offset": int(layout["wave_data_offsets"][0]),
        "current_matrix_offset": int(layout["current_matrix_offset"]),
        "waveform_count": int(layout["waveform_count"]),
        "waveform_full_points": int(layout["full_wave_points"]),
        "points_per_scan": int(layout["points_per_scan"]),
        "scan_count": int(layout["scan_count"]),
        "sample_rate_hz": float(layout["sample_rate_hz"]),
        "cvf_hz": float(layout["cvf_hz"]),
        "run_count": int(layout["run_count"]),
        "scans_per_run": int(layout["scans_per_run"]),
        "run_duration_s": float(layout["run_duration_s"]),
        "delay_between_runs_s": float(layout["delay_between_runs_s"]),
        "first_scan_index": first_idx,
        "middle_scan_index": middle_idx,
        "last_scan_index": last_idx,
        "first_scan_time_sequence_s": 0.0,
        "middle_scan_time_sequence_s": middle_idx / float(layout["cvf_hz"]),
        "last_scan_time_sequence_s": last_idx / float(layout["cvf_hz"]),
        "middle_scan_time_experiment_s": (middle_idx // int(layout["scans_per_run"])) * (
            float(layout["run_duration_s"]) + float(layout["delay_between_runs_s"])
        ) + (middle_idx % int(layout["scans_per_run"])) / float(layout["cvf_hz"]),
        "last_scan_time_experiment_s": (last_idx // int(layout["scans_per_run"])) * (
            float(layout["run_duration_s"]) + float(layout["delay_between_runs_s"])
        ) + (last_idx % int(layout["scans_per_run"])) / float(layout["cvf_hz"]),
    }
    write_manifest(args.out / "manifest.txt", manifest)


if __name__ == "__main__":
    main()
