"""
Score every segmentation-parameter combo produced by sweep_segmentation.R
(sweep_outputs/tree_heights_k*_*.csv) against field GT heights (Biomass
Calcs sheet only -- location, footprint, and height all come from that one
sheet), using the same nearest-neighbor matching logic as
compare_heights_within_footprints.py.

Reports match count and height error per combo, plus a combined score, so a
"sweet spot" between detection coverage and height accuracy can be picked.

Also reports under/over-segmentation: each combo's total segmented tree
count vs. the "TreePlotter Data" sheet's total tree count (the closest
thing to a whole-arboretum tree census in this workbook), since a combo
can match well within footprints while wildly over- or under-counting
trees across the full plot. A combined score folds this in alongside the
existing matches/MAE score.

Read-only with respect to existing project files: writes a new Excel
workbook only.
"""

import glob
import os
import re
import sys

import numpy as np
import pandas as pd
from pyproj import Transformer

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(SCRIPT_DIR)
ARBORETUM_XLSX = f"{REPO_DIR}\\WorkingTrees_Arboretum_Data.xlsx"
BIOMASS_SHEET = "Biomass Calcs"
TREEPLOTTER_SHEET = "TreePlotter Data"

# Usage: python compare_sweep_results.py [sweep_output_subfolder] [output_xlsx_name]
# Defaults match the original 0.4m CHM sweep. Sweep output folders and the
# result workbook both live alongside this script in Parameter_Sweep_Analysis/.
SWEEP_SUBDIR = sys.argv[1] if len(sys.argv) >= 2 else "sweep_outputs"
OUTPUT_NAME = sys.argv[2] if len(sys.argv) >= 3 else "sweep_results_summary.xlsx"
SWEEP_DIR = f"{SCRIPT_DIR}\\{SWEEP_SUBDIR}"
OUTPUT_XLSX = f"{SCRIPT_DIR}\\{OUTPUT_NAME}"

MAX_MATCH_DISTANCE_M = 5.0

# Reference for the "sweet spot" score: the original run (v1, 3x3 kernel,
# fixed ws=2.5) had 53 matched-with-GT and MAE 2.58m. v2 (5x5, variable
# window) had 36 matched-with-GT and MAE 2.15m. Score rewards more matches
# and lower MAE, roughly equally weighted around those observed ranges.
def score(n_matched_gt, mae):
    if n_matched_gt == 0 or np.isnan(mae):
        return -np.inf
    return n_matched_gt / mae


def count_treeplotter_total():
    tp = pd.read_excel(ARBORETUM_XLSX, sheet_name=TREEPLOTTER_SHEET)
    tp = tp.dropna(subset=["Latitude", "Longitude"])
    return len(tp)


def combined_score(base_score, abs_count_error_pct):
    # Penalize count fidelity: a combo that's 50% off on total tree count
    # roughly halves its base score; a combo dead-on the reference count
    # is unpenalized.
    if not np.isfinite(base_score):
        return -np.inf
    return base_score / (1.0 + abs_count_error_pct)


def load_field_with_gt():
    field = pd.read_excel(ARBORETUM_XLSX, sheet_name=BIOMASS_SHEET)
    field = field.rename(columns={
        "Spec.": "Species", "Tree": "Tree #", "Stem": "Stem #",
        "Lat": "lat", "Long": "lon",
        "WT Height": "WT_height_m", "GT Height": "GT_height_m",
    })
    field = field.dropna(subset=["Species", "Tree #", "Stem #", "Footprint", "lat", "lon"])
    field = field.drop_duplicates(subset=["Species", "Tree #", "Stem #", "Footprint"]).reset_index(drop=True)

    transformer = Transformer.from_crs("EPSG:4326", "EPSG:32610", always_xy=True)
    fx, fy = transformer.transform(field["lon"].values, field["lat"].values)
    field["field_x"] = fx
    field["field_y"] = fy
    return field


def match_and_score(seg, field):
    all_matches = []
    for fp_id, group in field.groupby("Footprint"):
        group = group.reset_index(drop=True)
        n_field = len(group)
        n_seg = len(seg)

        sx = seg["seg_x"].values[:, None]
        sy = seg["seg_y"].values[:, None]
        gx = group["field_x"].values[None, :]
        gy = group["field_y"].values[None, :]
        dist = np.sqrt((sx - gx) ** 2 + (sy - gy) ** 2)

        flat_order = np.dstack(np.unravel_index(np.argsort(dist, axis=None), dist.shape))[0]
        seg_used = np.zeros(n_seg, dtype=bool)
        field_used = np.zeros(n_field, dtype=bool)
        for i, j in flat_order:
            d = dist[i, j]
            if d > MAX_MATCH_DISTANCE_M:
                break
            if seg_used[i] or field_used[j]:
                continue
            seg_used[i] = True
            field_used[j] = True
            gt = group.loc[j, "GT_height_m"]
            all_matches.append({
                "distance_m": d,
                "seg_height_m": seg.loc[i, "seg_height_m"],
                "GT_height_m": gt,
                "seg_minus_GT_height_m": seg.loc[i, "seg_height_m"] - gt if pd.notna(gt) else np.nan,
            })

    matched_df = pd.DataFrame(all_matches)
    n_matched = len(matched_df)
    have_gt = matched_df["seg_minus_GT_height_m"].dropna() if n_matched else pd.Series(dtype=float)
    n_matched_gt = len(have_gt)
    mae = have_gt.abs().mean() if n_matched_gt else np.nan
    bias = have_gt.mean() if n_matched_gt else np.nan
    rmse = np.sqrt((have_gt ** 2).mean()) if n_matched_gt else np.nan
    return n_matched, n_matched_gt, mae, bias, rmse


def main():
    field = load_field_with_gt()
    treeplotter_total = count_treeplotter_total()

    rows = []
    for path in sorted(glob.glob(f"{SWEEP_DIR}\\tree_heights_*.csv")):
        fname = os.path.basename(path)
        m = re.match(r"tree_heights_k(\d+)_(.+)\.csv", fname)
        kernel = int(m.group(1))
        ws_label = m.group(2)

        seg = pd.read_csv(path)
        seg = seg.rename(columns={"treeID": "seg_treeID", "x": "seg_x", "y": "seg_y", "height_m": "seg_height_m"})
        n_seg_total = len(seg)

        n_matched, n_matched_gt, mae, bias, rmse = match_and_score(seg, field)

        count_error = n_seg_total - treeplotter_total
        count_error_pct = count_error / treeplotter_total
        abs_count_error_pct = abs(count_error_pct)
        base_score = score(n_matched_gt, mae)

        rows.append({
            "kernel": kernel,
            "ws_setting": ws_label,
            "n_segmented_total": n_seg_total,
            "n_treeplotter_reference": treeplotter_total,
            "count_error (seg-treeplotter)": count_error,
            "count_error_pct": count_error_pct,
            "segmentation_bias": "over" if count_error > 0 else ("under" if count_error < 0 else "exact"),
            "n_matched (<=5m)": n_matched,
            "n_matched_with_GT": n_matched_gt,
            "bias_m (seg-GT)": bias,
            "MAE_m": mae,
            "RMSE_m": rmse,
            "score (matches/MAE)": base_score,
            "combined_score (count-fidelity adj.)": combined_score(base_score, abs_count_error_pct),
        })

    results = pd.DataFrame(rows).sort_values("combined_score (count-fidelity adj.)", ascending=False).reset_index(drop=True)

    with pd.ExcelWriter(OUTPUT_XLSX, engine="openpyxl") as writer:
        results.to_excel(writer, sheet_name="Sweep Results", index=False)

    print(f"Wrote {OUTPUT_XLSX}\n")
    print(results.to_string(index=False))

if __name__ == "__main__":
    main()
