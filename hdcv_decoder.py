#!/usr/bin/env python3
"""Best-effort decoder and viewer for Pine HDCV FSCV files.

This script reverse-engineers HDCV files by:
1) Extracting the embedded text metadata block.
2) Detecting the voltage waveform vector.
3) Heuristically locating and decoding the current matrix payload.
4) Exporting decoded outputs and launching an interactive FSCV viewer.

The format is proprietary and can vary by software version, so this tool is
intentionally defensive and transparent about detection choices.
"""

from __future__ import annotations

import argparse
import json
import re
import struct
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import numpy as np


def _is_printable(byte: int) -> bool:
    return byte in (9, 10, 13) or 32 <= byte <= 126


def extract_metadata_block(raw: bytes) -> Tuple[str, int]:
    """Return decoded metadata text and its end offset in the file."""
    start = raw.find(b"[Core Cluster]")
    if start < 0:
        raise ValueError("Could not find '[Core Cluster]' metadata marker.")

    # Metadata is typically ASCII text until the first NUL byte after cluster lines.
    end = raw.find(b"\x00", start)
    if end < 0:
        end = min(len(raw), start + 200_000)

    # Expand slightly if we cut too early due to uncommon embedded bytes.
    scan_end = end
    while scan_end + 1 < len(raw) and _is_printable(raw[scan_end + 1]):
        scan_end += 1

    text = raw[start:scan_end].decode("utf-8", errors="ignore")
    return text, end


def parse_metadata(text: str) -> Dict[str, Dict[str, str]]:
    """Parse sectioned key/value metadata into nested dicts."""
    sections: Dict[str, Dict[str, str]] = {}
    current = "ROOT"
    sections[current] = {}

    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1].strip()
            sections.setdefault(current, {})
            continue

        if "=" in line:
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"')
            sections.setdefault(current, {})[key] = value

    return sections


def _get_first_numeric(metadata: Dict[str, Dict[str, str]], pattern: str) -> Optional[float]:
    regex = re.compile(pattern)
    for section in metadata.values():
        for k, v in section.items():
            if regex.search(k):
                try:
                    return float(v)
                except ValueError:
                    continue
    return None


def infer_points_per_scan(metadata: Dict[str, Dict[str, str]]) -> int:
    value = _get_first_numeric(metadata, r"Data points per scan")
    if value is None:
        raise ValueError("Could not infer 'Data points per scan' from metadata.")
    return int(round(value))


def infer_cvf_hz(metadata: Dict[str, Dict[str, str]]) -> Optional[float]:
    return _get_first_numeric(metadata, r"^CVF$")


def infer_v_bounds(metadata: Dict[str, Dict[str, str]]) -> Tuple[Optional[float], Optional[float]]:
    v1 = _get_first_numeric(metadata, r"^Wavespecs 0\.V1$")
    v2 = _get_first_numeric(metadata, r"^Wavespecs 0\.V2$")
    return v1, v2


def infer_waveform_count(metadata: Dict[str, Dict[str, str]]) -> int:
    value = _get_first_numeric(metadata, r"^Wavespecs\.<size\(s\)>$")
    if value is None:
        return 1
    return max(1, int(round(value)))


def find_waveform(payload: bytes, points_per_scan: int, v1: Optional[float], v2: Optional[float]) -> Tuple[int, np.ndarray]:
    """Find waveform start offset in payload and decode as big-end float32."""
    v1_bytes = None
    if v1 is not None:
        v1_bytes = struct.pack(">f", float(v1))

    candidate_offsets: List[int] = []
    if v1_bytes is not None:
        pat = re.escape(v1_bytes)
        # Look for a run of at least 8 repeated V1 points as a strong anchor.
        for match in re.finditer(rb"(?:" + pat + rb"){8,}", payload):
            candidate_offsets.append(match.start())
            if len(candidate_offsets) >= 200:
                break

    # Fallback scan near the beginning if no V1 anchor found.
    if not candidate_offsets:
        candidate_offsets = list(range(0, min(20000, max(0, len(payload) - 4 * points_per_scan))))

    best_score = -np.inf
    best_offset = None
    best_wave = None

    for off in candidate_offsets:
        need = off + 4 * points_per_scan
        if need > len(payload):
            continue

        wave = np.frombuffer(payload, dtype=">f4", count=points_per_scan, offset=off).astype(np.float32)
        if not np.isfinite(wave).all():
            continue

        # Score waveform candidates by realistic voltage behavior.
        wmin = float(np.min(wave))
        wmax = float(np.max(wave))
        d = np.diff(wave)
        smoothness = float(np.median(np.abs(d)))

        score = 0.0
        if v1 is not None:
            score -= abs(wmin - v1) * 20.0
        if v2 is not None:
            score -= abs(wmax - v2) * 20.0

        # Prefer bounded, smooth-ish waveforms with both rising/falling segments.
        frac_up = float(np.mean(d > 0))
        frac_down = float(np.mean(d < 0))
        score += 5.0 * min(frac_up, 0.4)
        score += 5.0 * min(frac_down, 0.4)
        score -= 50.0 * max(0.0, smoothness - 0.05)
        score -= max(0.0, (wmax - wmin) - 3.0) * 20.0

        if score > best_score:
            best_score = score
            best_offset = off
            best_wave = wave

    if best_offset is None or best_wave is None:
        raise ValueError("Could not locate a plausible waveform block.")

    return best_offset, best_wave


@dataclass
class MatrixGuess:
    offset: int
    dtype: str
    itemsize: int
    scans: int
    score: float


def _matrix_score(block: np.ndarray) -> float:
    """Heuristic quality score for decoded current matrix candidates."""
    if block.ndim != 2 or block.shape[0] < 4 or block.shape[1] < 8:
        return -1e9
    if not np.isfinite(block).all():
        return -1e9

    # Clip extreme values to keep scoring stable even when header words leak into payload.
    x = np.clip(block.astype(np.float64), -1e6, 1e6)
    x = x - np.mean(x, axis=1, keepdims=True)
    x0 = x[:-1]
    x1 = x[1:]

    num = np.sum(x0 * x1, axis=1)
    den = np.sqrt(np.sum(x0 * x0, axis=1) * np.sum(x1 * x1, axis=1)) + 1e-12
    corr = np.nan_to_num(num / den, nan=0.0, posinf=0.0, neginf=0.0)
    corr_med = float(np.median(corr))

    row_std = float(np.median(np.std(x, axis=1)))
    if row_std <= 0:
        return -1e9

    rough = float(np.median(np.std(np.diff(x, axis=1), axis=1)))
    amp99 = float(np.percentile(np.abs(x), 99))

    # Encourage adjacent-scan similarity and smooth CV shape, penalize absurd amplitudes.
    score = 4.0 * corr_med
    score -= 0.01 * rough
    score -= 0.00001 * max(0.0, amp99 - 1e5)

    return score


def clean_extreme_outliers(matrix: np.ndarray) -> Tuple[np.ndarray, float, int]:
    """Replace extreme point outliers with NaN using robust percentile clipping."""
    finite = np.isfinite(matrix)
    if not np.any(finite):
        return matrix, 0.0, 0

    abs_vals = np.abs(matrix[finite])
    base = float(np.percentile(abs_vals, 99.9))
    clip = max(base * 10.0, 1e-9)

    cleaned = matrix.copy()
    mask = np.abs(cleaned) > clip
    removed = int(np.sum(mask))
    cleaned[mask] = np.nan
    return cleaned, clip, removed


def guess_current_matrix(
    payload: bytes,
    waveform_offset: int,
    points_per_scan: int,
    search_bytes: int = 16384,
) -> MatrixGuess:
    """Find likely current matrix encoding and start offset."""
    start = waveform_offset + points_per_scan * 4
    end = min(len(payload), start + search_bytes)

    dtypes = [
        (">f4", 4, 4),
        ("<f4", 4, 4),
        (">i2", 2, 2),
        ("<i2", 2, 2),
    ]

    best: Optional[MatrixGuess] = None

    for dtype, itemsize, align in dtypes:
        for off in range(start, end):
            if off % align != 0:
                continue
            scans = (len(payload) - off) // (points_per_scan * itemsize)
            if scans < 20:
                continue

            sample_scans = min(scans, 200)
            count = sample_scans * points_per_scan
            arr = np.frombuffer(payload, dtype=dtype, count=count, offset=off)
            if arr.size != count:
                continue

            block = arr.reshape(sample_scans, points_per_scan).astype(np.float32)
            score = _matrix_score(block)

            if dtype in (">f4", "<f4"):
                score += 0.5
            else:
                amp99 = float(np.percentile(np.abs(block), 99))
                if amp99 > 20000:
                    score -= 2.0

            if best is None or score > best.score:
                best = MatrixGuess(offset=off, dtype=dtype, itemsize=itemsize, scans=scans, score=score)

    if best is None:
        raise ValueError("Could not infer current matrix payload layout.")

    return best


def decode_matrix(payload: bytes, guess: MatrixGuess, points_per_scan: int) -> np.ndarray:
    count = guess.scans * points_per_scan
    arr = np.frombuffer(payload, dtype=guess.dtype, count=count, offset=guess.offset)
    return arr.reshape(guess.scans, points_per_scan).astype(np.float32)


def decode_hdcv(path: Path) -> Dict[str, Any]:
    raw = path.read_bytes()

    metadata_text, metadata_end = extract_metadata_block(raw)
    metadata = parse_metadata(metadata_text)

    points_per_scan = infer_points_per_scan(metadata)
    cvf_hz = infer_cvf_hz(metadata)
    v1, v2 = infer_v_bounds(metadata)
    waveform_count = infer_waveform_count(metadata)

    payload = raw[metadata_end:]

    waveform_offset, voltage = find_waveform(payload, points_per_scan, v1, v2)
    matrix_guess = guess_current_matrix(payload, waveform_offset, points_per_scan)
    current_raw = decode_matrix(payload, matrix_guess, points_per_scan)
    current, outlier_clip, outliers_removed = clean_extreme_outliers(current_raw)

    dt = 1.0 / cvf_hz if cvf_hz and cvf_hz > 0 else 1.0
    time_s = np.arange(current.shape[0], dtype=np.float32) * np.float32(dt)

    st = path.stat()
    summary = {
        "file": str(path),
        "file_size_bytes": len(raw),
        "input_mtime_ns": int(st.st_mtime_ns),
        "metadata_end_offset": metadata_end,
        "points_per_scan": points_per_scan,
        "waveform_count": waveform_count,
        "cvf_hz": cvf_hz,
        "v1": v1,
        "v2": v2,
        "waveform_offset_in_payload": waveform_offset,
        "matrix_guess": asdict(matrix_guess),
        "decoded_shape": list(current.shape),
        "outlier_clip_abs": outlier_clip,
        "outliers_removed_points": outliers_removed,
    }

    return {
        "metadata_text": metadata_text,
        "metadata": metadata,
        "summary": summary,
        "voltage": voltage,
        "time_s": time_s,
        "current_raw": current_raw,
        "current": current,
    }


def _open_file_dialog() -> Optional[Path]:
    try:
        import tkinter as tk
        from tkinter import filedialog

        root = tk.Tk()
        root.withdraw()
        root.update()
        chosen = filedialog.askopenfilename(
            title="Import HDCV file",
            filetypes=[("HDCV files", "*.hdcv"), ("All files", "*.*")],
        )
        root.destroy()
        if not chosen:
            return None
        return Path(chosen).expanduser().resolve()
    except Exception as exc:
        print(f"Import dialog unavailable: {exc}")
        return None


def launch_viewer(
    time_s: np.ndarray,
    voltage_v: np.ndarray,
    current: np.ndarray,
    scan_phase_period: int = 1,
    source_path: Optional[Path] = None,
) -> None:
    import matplotlib.pyplot as plt
    from matplotlib.widgets import Button, CheckButtons, TextBox

    # Design-system colors
    C_BG = "#FAF5FF"
    C_CARD = "#FFFFFF"
    C_BORDER = "#E9D5FF"
    C_TEXT = "#1F2937"
    C_MUTED = "#6B7280"
    C_PURPLE = "#8B5CF6"
    C_VIOLET = "#A78BFA"
    C_PINK = "#EC4899"
    C_GREEN = "#22C55E"

    # Use waveform-point order on Y so cyclic ramps are shown as first->last
    # sample in the scan (e.g. -0.4 -> 1.1 -> -0.4), not as a monotonic axis.
    current_heat = current

    t_idx = min(len(time_s) // 2, len(time_s) - 1)
    v_idx = min(len(voltage_v) // 2, len(voltage_v) - 1)
    bg_idx = max(0, min(len(time_s) - 1, t_idx // 4))

    fig = plt.figure(figsize=(14, 8.8), facecolor=C_BG)
    gs = fig.add_gridspec(2, 2, width_ratios=[1.4, 1.0], height_ratios=[1.0, 1.0])
    ax_heat = fig.add_subplot(gs[:, 0])
    ax_time = fig.add_subplot(gs[0, 1])
    ax_cv = fig.add_subplot(gs[1, 1])

    for ax in (ax_heat, ax_time, ax_cv):
        ax.set_facecolor(C_CARD)
        for side in ax.spines.values():
            side.set_edgecolor(C_BORDER)
            side.set_linewidth(1.2)
        ax.tick_params(colors=C_MUTED, labelsize=9)

    finite_heat = current_heat[np.isfinite(current_heat)]
    if finite_heat.size > 0:
        cmin = float(np.percentile(finite_heat, 1.0))
        cmax = float(np.percentile(finite_heat, 99.0))
    else:
        cmin, cmax = -1.0, 1.0

    extent = [float(time_s[0]), float(time_s[-1]), 0.0, float(len(voltage_v) - 1)]
    im = ax_heat.imshow(
        current_heat.T,
        aspect="auto",
        origin="lower",
        extent=extent,
        interpolation="nearest",
        cmap="turbo",
        vmin=cmin,
        vmax=cmax,
    )
    cb = fig.colorbar(im, ax=ax_heat, label="Current (nA)", fraction=0.046, pad=0.03)
    cb.ax.yaxis.label.set_color(C_MUTED)
    cb.ax.tick_params(colors=C_MUTED, labelsize=8)
    ax_heat.set_title("Color Plot", loc="left", fontsize=12, fontweight="semibold", color=C_PURPLE)
    ax_heat.set_xlabel("Time (s)", color=C_MUTED, fontsize=10)
    ax_heat.set_ylabel("Voltage (V)", color=C_MUTED, fontsize=10)

    tick_count = min(9, len(voltage_v))
    tick_idx = np.linspace(0, len(voltage_v) - 1, num=tick_count, dtype=int)
    ax_heat.set_yticks(tick_idx)
    ax_heat.set_yticklabels([f"{float(voltage_v[i]):.2f}" for i in tick_idx])

    (line_time,) = ax_time.plot(time_s, current[:, v_idx], lw=0.7, color=C_PURPLE)
    ax_time.set_title("Current vs Time", loc="left", fontsize=12, fontweight="semibold", color=C_PURPLE)
    ax_time.set_xlabel("Time (s)", color=C_MUTED, fontsize=10)
    ax_time.set_ylabel("Current (nA)", color=C_MUTED, fontsize=10)
    ax_time.grid(True, color=C_BORDER, ls="--", lw=1.0, alpha=0.9)

    (line_cv,) = ax_cv.plot(voltage_v, current[t_idx, :] - current[bg_idx, :], lw=2.5, color=C_VIOLET)
    ax_cv.set_title("Cyclic Voltammogram", loc="left", fontsize=12, fontweight="semibold", color=C_PURPLE)
    ax_cv.set_xlabel("Voltage (V)", color=C_MUTED, fontsize=10)
    ax_cv.set_ylabel("Current (nA)", color=C_MUTED, fontsize=10)
    ax_cv.grid(True, color=C_BORDER, ls="--", lw=1.0, alpha=0.9)

    # Crosshair overlays for all plots.
    ht = ax_heat.axhline(float(v_idx), color="#C4B5FD", lw=2.0, ls="--", dashes=(6, 3))
    vt = ax_heat.axvline(time_s[t_idx], color="#A78BFA", lw=2.0, ls="--", dashes=(6, 3))
    bg_vt = ax_heat.axvline(time_s[bg_idx], color=C_PINK, lw=2.0, ls="--", dashes=(6, 3))
    t_vline = ax_time.axvline(time_s[t_idx], color=C_PURPLE, lw=2.0, ls="--", dashes=(6, 3))
    t_hline = ax_time.axhline(current[t_idx, v_idx], color=C_VIOLET, lw=1.2, ls="--", dashes=(6, 3))
    cv_vline = ax_cv.axvline(voltage_v[v_idx], color=C_VIOLET, lw=2.0, ls="--", dashes=(6, 3))
    cv_hline = ax_cv.axhline(current[t_idx, v_idx] - current[bg_idx, v_idx], color=C_PURPLE, lw=1.2, ls="--", dashes=(6, 3))

    fig.subplots_adjust(wspace=0.25, bottom=0.20, top=0.84)

    # Header styling similar to the provided prototype.
    fig.text(0.06, 0.95, "FSCV Analysis Suite", fontsize=20, fontweight="bold", color=C_PURPLE)
    fig.text(0.06, 0.925, "Fast Scan Cyclic Voltammetry | Clinical Grade", fontsize=11, color=C_MUTED)
    if source_path is not None:
        fig.text(0.06, 0.905, f"File: {source_path.name}", fontsize=9, color=C_MUTED)
    ax_import = fig.add_axes([0.78, 0.925, 0.11, 0.045])
    btn_import = Button(ax_import, "Import Data", color=C_CARD, hovercolor="#F3E8FF")
    btn_import.label.set_color(C_PURPLE)
    btn_import.label.set_fontsize(10)
    btn_import.label.set_fontweight("semibold")
    for side in ax_import.spines.values():
        side.set_edgecolor(C_BORDER)
        side.set_linewidth(1.0)
    fig.text(
        0.92,
        0.945,
        " Export Report ",
        fontsize=10,
        color="white",
        ha="left",
        va="center",
        bbox=dict(boxstyle="round,pad=0.45", facecolor=C_PURPLE, edgecolor=C_PURPLE),
    )

    # Controls:
    # - Checkbox toggles subtraction on/off.
    # - Text boxes allow direct coordinate entry for crosshair locations.
    ax_chk_bg = fig.add_axes([0.29, 0.845, 0.14, 0.05])
    check_bg = CheckButtons(ax_chk_bg, ["BG Subtract"], [True])
    bg_enabled = {"on": True}

    ax_filter = fig.add_axes([0.46, 0.845, 0.18, 0.045])
    btn_filter = Button(ax_filter, "I-t Filter: OFF", color=C_CARD, hovercolor="#F3E8FF")
    ax_filter.set_facecolor(C_CARD)
    for side in ax_filter.spines.values():
        side.set_edgecolor(C_BORDER)
        side.set_linewidth(1.0)
    filter_enabled = {"on": True}

    def _set_filter_label() -> None:
        state = "ON" if filter_enabled["on"] else "OFF"
        btn_filter.label.set_text(f"I-t Filter: {state}")
        btn_filter.label.set_color(C_PURPLE)
        btn_filter.label.set_fontsize(10)
        btn_filter.label.set_fontweight("semibold")

    _set_filter_label()
    ax_chk_bg.set_facecolor(C_CARD)
    for side in ax_chk_bg.spines.values():
        side.set_visible(False)
    for lbl in check_bg.labels:
        lbl.set_color(C_PURPLE)
        lbl.set_fontsize(10)
        lbl.set_fontweight("semibold")
    rectangles = getattr(check_bg, "rectangles", None)
    if rectangles is not None:
        for rec in rectangles:
            rec.set_edgecolor(C_PURPLE)
            rec.set_facecolor(C_CARD)
    lines = getattr(check_bg, "lines", None)
    if lines is not None:
        for pair in lines:
            for ln in pair:
                ln.set_color(C_PURPLE)

    tb_ax_heat_bg = fig.add_axes([0.06, 0.08, 0.12, 0.045])
    tb_ax_heat_h = fig.add_axes([0.19, 0.08, 0.12, 0.045])
    tb_ax_heat_v = fig.add_axes([0.32, 0.08, 0.12, 0.045])
    tb_ax_time_v = fig.add_axes([0.58, 0.08, 0.15, 0.045])
    tb_ax_cv_v = fig.add_axes([0.76, 0.08, 0.15, 0.045])

    tb_heat_bg = TextBox(tb_ax_heat_bg, "Background (s)", initial=f"{float(time_s[bg_idx]):.3f}")
    tb_heat_h = TextBox(tb_ax_heat_h, "Voltage (V)", initial=f"{float(voltage_v[v_idx]):.3f}")
    tb_heat_v = TextBox(tb_ax_heat_v, "Time (s)", initial=f"{float(time_s[t_idx]):.3f}")
    tb_time_v = TextBox(tb_ax_time_v, "Current/Time t", initial=f"{float(time_s[t_idx]):.3f}")
    tb_cv_v = TextBox(tb_ax_cv_v, "CV Voltage (V)", initial=f"{float(voltage_v[v_idx]):.3f}")
    for ta in (tb_ax_heat_bg, tb_ax_heat_h, tb_ax_heat_v, tb_ax_time_v, tb_ax_cv_v):
        ta.set_facecolor(C_CARD)
        for side in ta.spines.values():
            side.set_edgecolor(C_BORDER)
            side.set_linewidth(1.0)
    for tb in (tb_heat_bg, tb_heat_h, tb_heat_v, tb_time_v, tb_cv_v):
        tb.label.set_color(C_PURPLE)
        tb.label.set_fontsize(9)
        tb.text_disp.set_color(C_TEXT)
    widget_sync = {"busy": False}

    active_drag = {"mode": None, "axes": None}

    def _phase_aligned_bg_idx(raw_bg_idx: int, scan_idx: int) -> int:
        period = max(1, int(scan_phase_period))
        if period <= 1:
            return raw_bg_idx

        target_mod = scan_idx % period
        nearest = target_mod + int(round((raw_bg_idx - target_mod) / period)) * period
        nearest = int(np.clip(nearest, 0, len(time_s) - 1))

        # Prefer a background at or before the selected scan when possible.
        while nearest > scan_idx and nearest - period >= 0:
            nearest -= period
        return int(np.clip(nearest, 0, len(time_s) - 1))

    def background_idx(scan_idx: int) -> Tuple[int, int]:
        raw_idx = int(np.argmin(np.abs(time_s - float(bg_vt.get_xdata()[0]))))
        used_idx = _phase_aligned_bg_idx(raw_idx, scan_idx)
        return raw_idx, used_idx

    def _smooth_trace(y: np.ndarray) -> np.ndarray:
        # Lightweight low-pass smoothing to suppress high-frequency noise.
        if y.size < 5:
            return y
        win = 11
        if y.size <= win:
            win = max(3, int(y.size // 2) * 2 - 1)
        kernel = np.ones(win, dtype=np.float32) / float(win)
        return np.convolve(y, kernel, mode="same")

    def _set_textboxes(selected_t: float, selected_v: float, bg_raw_t: float) -> None:
        widget_sync["busy"] = True
        tb_heat_bg.set_val(f"{bg_raw_t:.3f}")
        tb_heat_h.set_val(f"{selected_v:.3f}")
        tb_heat_v.set_val(f"{selected_t:.3f}")
        tb_time_v.set_val(f"{selected_t:.3f}")
        tb_cv_v.set_val(f"{selected_v:.3f}")
        widget_sync["busy"] = False

    def update(scan_idx: int, volt_idx_local: int) -> None:
        scan_idx = int(np.clip(scan_idx, 0, current.shape[0] - 1))
        volt_idx_local = int(np.clip(volt_idx_local, 0, current.shape[1] - 1))
        bg_scan_raw_idx, bg_scan_idx = background_idx(scan_idx)
        selected_t = float(time_s[scan_idx])
        selected_v = float(voltage_v[volt_idx_local])
        selected_i = float(current[scan_idx, volt_idx_local])
        selected_i_sub = float(current[scan_idx, volt_idx_local] - current[bg_scan_idx, volt_idx_local])

        ht.set_ydata([float(volt_idx_local), float(volt_idx_local)])
        vt.set_xdata([selected_t, selected_t])
        # Keep the user-selected background marker as the visible reference.

        time_trace = current[:, volt_idx_local]
        if filter_enabled["on"]:
            time_trace = _smooth_trace(time_trace)
        line_time.set_ydata(time_trace)
        if bg_enabled["on"]:
            line_cv.set_ydata(current[scan_idx, :] - current[bg_scan_idx, :])
            cv_level = selected_i_sub
            cv_title = "Cyclic Voltammogram (BG Subtracted)"
        else:
            line_cv.set_ydata(current[scan_idx, :])
            cv_level = selected_i
            cv_title = "Cyclic Voltammogram (Raw)"

        t_vline.set_xdata([selected_t, selected_t])
        t_hline.set_ydata([selected_i, selected_i])
        cv_vline.set_xdata([selected_v, selected_v])
        cv_hline.set_ydata([cv_level, cv_level])
        ax_cv.set_title(cv_title)

        ax_time.relim()
        ax_time.autoscale_view()
        ax_cv.relim()
        ax_cv.autoscale_view()

        fig.suptitle(
            (
                f"Scan {scan_idx} | Time {selected_t:.3f} s | Voltage {selected_v:.3f} V"
                f" | BG Raw {float(time_s[bg_scan_raw_idx]):.3f} s"
                f" | BG Used {float(time_s[bg_scan_idx]):.3f} s"
            ),
            fontsize=10,
            color=C_MUTED,
        )
        _set_textboxes(selected_t, selected_v, float(time_s[bg_scan_raw_idx]))
        fig.canvas.draw_idle()

    def update_from_values(time_value: float, voltage_value: float) -> None:
        scan_idx = int(np.argmin(np.abs(time_s - float(time_value))))
        volt_idx_local = int(np.argmin(np.abs(voltage_v - float(voltage_value))))
        update(scan_idx, volt_idx_local)

    def update_from_wave_idx(time_value: float, wave_idx_value: float) -> None:
        scan_idx = int(np.argmin(np.abs(time_s - float(time_value))))
        volt_idx_local = int(np.clip(int(round(wave_idx_value)), 0, len(voltage_v) - 1))
        update(scan_idx, volt_idx_local)

    def update_background_time(time_value: float) -> None:
        bg_scan_idx = int(np.argmin(np.abs(time_s - float(time_value))))
        bg_t = float(time_s[bg_scan_idx])
        bg_vt.set_xdata([bg_t, bg_t])
        scan_idx, volt_idx_local = current_state()
        update(scan_idx, volt_idx_local)

    def current_state() -> Tuple[int, int]:
        scan_idx = int(np.argmin(np.abs(time_s - float(vt.get_xdata()[0]))))
        volt_idx_local = int(np.clip(int(round(float(ht.get_ydata()[0]))), 0, len(voltage_v) - 1))
        return scan_idx, volt_idx_local

    def on_press(event) -> None:
        if event.inaxes not in (ax_heat, ax_time, ax_cv):
            active_drag["mode"] = None
            active_drag["axes"] = None
            return
        active_drag["axes"] = event.inaxes

        if event.inaxes == ax_heat:
            if event.xdata is None or event.ydata is None:
                return
            x_tol = 0.02 * max(float(time_s[-1] - time_s[0]), 1e-9)
            y_tol = 0.02 * max(float(len(voltage_v) - 1), 1e-9)
            near_vline = abs(event.xdata - float(vt.get_xdata()[0])) <= x_tol
            near_bg_vline = abs(event.xdata - float(bg_vt.get_xdata()[0])) <= x_tol
            near_hline = abs(event.ydata - float(ht.get_ydata()[0])) <= y_tol

            if near_bg_vline and not near_hline:
                active_drag["mode"] = "bg_time"
            elif near_vline and near_hline:
                active_drag["mode"] = "both"
            elif near_vline:
                active_drag["mode"] = "time"
            elif near_hline:
                active_drag["mode"] = "voltage"
            else:
                active_drag["mode"] = "both"
                update_from_wave_idx(float(event.xdata), float(event.ydata))
        elif event.inaxes == ax_time:
            if event.xdata is None or event.ydata is None:
                return
            x_tol = 0.02 * max(float(time_s[-1] - time_s[0]), 1e-9)
            near_vline = abs(event.xdata - float(t_vline.get_xdata()[0])) <= x_tol
            if near_vline:
                active_drag["mode"] = "time"
            else:
                active_drag["mode"] = None
        elif event.inaxes == ax_cv:
            if event.xdata is None or event.ydata is None:
                return
            x0, x1 = ax_cv.get_xlim()
            x_tol = 0.02 * max(float(x1 - x0), 1e-9)
            near_vline = abs(event.xdata - float(cv_vline.get_xdata()[0])) <= x_tol
            if near_vline:
                active_drag["mode"] = "voltage"
            else:
                active_drag["mode"] = None

    def _nearest_orig_voltage_idx(v_value: float) -> int:
        return int(np.argmin(np.abs(voltage_v - float(v_value))))

    def _nearest_time_idx(t_value: float) -> int:
        return int(np.argmin(np.abs(time_s - float(t_value))))

    def _nearest_voltage_for_current(scan_idx: int, i_value: float) -> int:
        return int(np.argmin(np.abs(current[scan_idx, :] - float(i_value))))

    def _nearest_time_for_current(volt_orig_idx: int, i_value: float) -> int:
        return int(np.argmin(np.abs(current[:, volt_orig_idx] - float(i_value))))

    def _update_by_indices(scan_idx: int, volt_idx_local: int) -> None:
        update(int(scan_idx), int(np.clip(volt_idx_local, 0, len(voltage_v) - 1)))

    def on_motion(event) -> None:
        mode = active_drag["mode"]
        src = active_drag["axes"]
        if mode is None or src is None:
            return

        scan_idx, volt_idx_local = current_state()

        if src == ax_heat:
            if event.inaxes != ax_heat:
                return
            if mode == "bg_time":
                if event.xdata is not None:
                    update_background_time(float(event.xdata))
                return
            t_val = float(time_s[scan_idx])
            wave_idx_val = float(volt_idx_local)
            if mode in ("both", "time") and event.xdata is not None:
                t_val = float(event.xdata)
            if mode in ("both", "voltage") and event.ydata is not None:
                wave_idx_val = float(event.ydata)
            update_from_wave_idx(t_val, wave_idx_val)
            return

        if src == ax_time:
            if event.inaxes != ax_time:
                return
            if mode == "time" and event.xdata is not None:
                scan_idx = _nearest_time_idx(float(event.xdata))
            elif mode is None:
                return
            _update_by_indices(scan_idx, volt_idx_local)
            return

        if src == ax_cv:
            if event.inaxes != ax_cv:
                return
            if mode == "voltage" and event.xdata is not None:
                volt_idx_local = _nearest_orig_voltage_idx(float(event.xdata))
            elif mode is None:
                return
            _update_by_indices(scan_idx, volt_idx_local)

    def on_release(_event) -> None:
        active_drag["mode"] = None
        active_drag["axes"] = None

    def _parse_float(text: str) -> Optional[float]:
        try:
            return float(text)
        except ValueError:
            return None

    def on_toggle_bg(_label: str) -> None:
        bg_enabled["on"] = not bg_enabled["on"]
        scan_idx, volt_idx_local = current_state()
        update(scan_idx, volt_idx_local)

    def on_submit_heat_bg(text: str) -> None:
        if widget_sync["busy"]:
            return
        val = _parse_float(text)
        if val is None:
            return
        update_background_time(val)

    def on_submit_heat_h(text: str) -> None:
        if widget_sync["busy"]:
            return
        val = _parse_float(text)
        if val is None:
            return
        t_now = float(vt.get_xdata()[0])
        update_from_values(t_now, val)

    def on_submit_heat_v(text: str) -> None:
        if widget_sync["busy"]:
            return
        val = _parse_float(text)
        if val is None:
            return
        v_now = float(voltage_v[int(np.clip(int(round(float(ht.get_ydata()[0]))), 0, len(voltage_v) - 1))])
        update_from_values(val, v_now)

    def on_submit_time_v(text: str) -> None:
        on_submit_heat_v(text)

    def on_submit_cv_v(text: str) -> None:
        if widget_sync["busy"]:
            return
        val = _parse_float(text)
        if val is None:
            return
        t_now = float(vt.get_xdata()[0])
        update_from_values(t_now, val)

    def on_filter_toggle(_event) -> None:
        filter_enabled["on"] = not filter_enabled["on"]
        _set_filter_label()
        scan_idx, volt_idx_local = current_state()
        update(scan_idx, volt_idx_local)

    def on_import_click(_event) -> None:
        selected = _open_file_dialog()
        if selected is None:
            return
        try:
            decoded = decode_hdcv(selected)
        except Exception as exc:
            print(f"Failed to import {selected}: {exc}")
            return
        plt.close(fig)
        launch_viewer(
            decoded["time_s"],
            decoded["voltage"],
            decoded["current"],
            scan_phase_period=int(decoded["summary"].get("waveform_count", 1)),
            source_path=selected,
        )

    fig.canvas.mpl_connect("button_press_event", on_press)
    fig.canvas.mpl_connect("motion_notify_event", on_motion)
    fig.canvas.mpl_connect("button_release_event", on_release)
    btn_import.on_clicked(on_import_click)
    check_bg.on_clicked(on_toggle_bg)
    btn_filter.on_clicked(on_filter_toggle)
    tb_heat_bg.on_submit(on_submit_heat_bg)
    tb_heat_h.on_submit(on_submit_heat_h)
    tb_heat_v.on_submit(on_submit_heat_v)
    tb_time_v.on_submit(on_submit_time_v)
    tb_cv_v.on_submit(on_submit_cv_v)

    update(t_idx, v_idx)
    plt.show()
def decode_file(path: Path, out_dir: Path, open_viewer: bool, save_decoded: bool = False) -> None:
    decoded = decode_hdcv(path)

    metadata_text = decoded["metadata_text"]
    metadata = decoded["metadata"]
    summary = decoded["summary"]
    voltage = decoded["voltage"]
    time_s = decoded["time_s"]
    current_raw = decoded["current_raw"]
    current = decoded["current"]
    waveform_count = int(summary.get("waveform_count", 1))

    if save_decoded:
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / "metadata_raw.txt").write_text(metadata_text, encoding="utf-8")
        (out_dir / "metadata_parsed.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
        (out_dir / "decode_summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
        np.save(out_dir / "voltage_waveform.npy", voltage)
        np.save(out_dir / "time_axis_s.npy", time_s)
        np.save(out_dir / "current_matrix_raw.npy", current_raw)
        np.save(out_dir / "current_matrix.npy", current)
        print(f"Outputs written to: {out_dir}")

    print("Decode complete")
    print(json.dumps(summary, indent=2))

    if open_viewer:
        launch_viewer(
            time_s,
            voltage,
            current,
            scan_phase_period=waveform_count,
            source_path=path,
        )


def main() -> None:
    parser = argparse.ArgumentParser(description="Decode Pine HDCV FSCV files (best effort)")
    parser.add_argument("input", type=Path, help="Path to .hdcv file")
    parser.add_argument(
        "--out",
        type=Path,
        default=None,
        help="Output directory (default: ./<input_stem>_decoded)",
    )
    parser.add_argument(
        "--no-csv",
        action="store_true",
        help="Deprecated no-op: CSV export has been removed for performance",
    )
    parser.add_argument(
        "--no-viewer",
        action="store_true",
        help="Do not open interactive matplotlib viewer",
    )
    parser.add_argument(
        "--no-cache",
        action="store_true",
        help="Deprecated no-op: caching has been removed",
    )
    parser.add_argument(
        "--save-decoded",
        action="store_true",
        help="Persist decoded arrays/metadata to output directory",
    )

    args = parser.parse_args()

    input_path = args.input.resolve()
    if not input_path.exists():
        raise FileNotFoundError(f"Input not found: {input_path}")

    out_dir = args.out if args.out is not None else Path.cwd() / f"{input_path.stem}_decoded"
    decode_file(
        path=input_path,
        out_dir=out_dir,
        open_viewer=not args.no_viewer,
        save_decoded=args.save_decoded,
    )


if __name__ == "__main__":
    main()
