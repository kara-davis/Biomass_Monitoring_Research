"""
Compare UAV-segmented tree heights (tree_heights_04m.csv / tree_heights_025m.csv,
from uav_to_biomass.ipynb) to field-measured heights within the six GEDI footprints.

Location (Lat/Long), Footprint membership, and height (GT Height, WT Height)
all come solely from the "Biomass Calcs" sheet of WorkingTrees_Arboretum_Data.xlsx
-- no other sheet in that workbook is read.

No footprint polygon file exists in the repo, so footprint membership is
taken directly from the sheet's "Footprint" column (1-6) rather than a
spatial polygon test.

Read-only with respect to existing project files: writes a new Excel
workbook only.

Matching: each field tree/stem (by Lat/Long) is paired with its nearest
segmented treetop (by planar distance in meters, EPSG:32610), capped at
MAX_MATCH_DISTANCE_M, one-to-one greedy nearest-neighbor (closest pairs
assigned first, matching restricted per footprint).

Usage: python compare_heights_within_footprints.py [04m|025m]
Defaults to 04m (the overall best combo: kernel 3x3, fixed ws=3.0).
"""

import sys
from pathlib import Path

import numpy as np
import pandas as pd
from pyproj import Transformer

REPO_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = REPO_DIR / "data"
OUTPUT_DIR = REPO_DIR / "outputs"

CHM_SUFFIX = sys.argv[1] if len(sys.argv) >= 2 else "04m"
if CHM_SUFFIX not in ("04m", "025m"):
    raise SystemExit('CHM suffix must be "04m" or "025m"')

SEGMENTATION_CSV = str(OUTPUT_DIR / f"tree_heights_{CHM_SUFFIX}.csv")
ARBORETUM_XLSX = str(DATA_DIR / "WorkingTrees_Arboretum_Data.xlsx")
BIOMASS_SHEET = "Biomass Calcs"
OUTPUT_XLSX = str(OUTPUT_DIR / f"height_comparison_within_footprints_{CHM_SUFFIX}.xlsx")

MAX_MATCH_DISTANCE_M = 5.0

def main():
    seg = pd.read_csv(SEGMENTATION_CSV)
    seg = seg.rename(columns={"treeID": "seg_treeID", "x": "seg_x", "y": "seg_y", "height_m": "seg_height_m"})

    field = pd.read_excel(ARBORETUM_XLSX, sheet_name=BIOMASS_SHEET)
    field = field.rename(columns={
        "Spec.": "Species", "Tree": "Tree #", "Stem": "Stem #",
        "Lat": "lat", "Long": "lon",
        "WT Height": "WT_height_m", "GT Height": "GT_height_m",
    })
    # drop trailing blank/junk rows below the real data table (no key values)
    field = field.dropna(subset=["Species", "Tree #", "Stem #", "Footprint", "lat", "lon"])
    field = field.drop_duplicates(subset=["Species", "Tree #", "Stem #", "Footprint"]).reset_index(drop=True)

    transformer = Transformer.from_crs("EPSG:4326", "EPSG:32610", always_xy=True)
    fx, fy = transformer.transform(field["lon"].values, field["lat"].values)
    field["field_x"] = fx
    field["field_y"] = fy

    all_matches = []
    unmatched_field_parts = []

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
        pairs = []
        for i, j in flat_order:
            d = dist[i, j]
            if d > MAX_MATCH_DISTANCE_M:
                break
            if seg_used[i] or field_used[j]:
                continue
            seg_used[i] = True
            field_used[j] = True
            pairs.append((i, j, d))

        for i, j, d in pairs:
            row = {
                "Footprint": fp_id,
                "Species": group.loc[j, "Species"],
                "Sci. Species Name": group.loc[j, "Sci. Species Name"],
                "Tree #": group.loc[j, "Tree #"],
                "Stem #": group.loc[j, "Stem #"],
                "seg_treeID": seg.loc[i, "seg_treeID"],
                "distance_m": d,
                "seg_height_m": seg.loc[i, "seg_height_m"],
                "WT_height_m": group.loc[j, "WT_height_m"],
                "GT_height_m": group.loc[j, "GT_height_m"],
                "seg_minus_GT_height_m": seg.loc[i, "seg_height_m"] - group.loc[j, "GT_height_m"]
                    if pd.notna(group.loc[j, "GT_height_m"]) else np.nan,
                "seg_minus_WT_height_m": seg.loc[i, "seg_height_m"] - group.loc[j, "WT_height_m"]
                    if pd.notna(group.loc[j, "WT_height_m"]) else np.nan,
            }
            all_matches.append(row)

        unmatched = group.loc[~field_used].copy()
        unmatched["Footprint"] = fp_id
        unmatched_field_parts.append(unmatched)

    matched_df = pd.DataFrame(all_matches).sort_values(["Footprint", "distance_m"]).reset_index(drop=True)
    unmatched_field_df = pd.concat(unmatched_field_parts, ignore_index=True) if unmatched_field_parts else pd.DataFrame()

    have_gt = matched_df["seg_minus_GT_height_m"].dropna()
    have_wt = matched_df["seg_minus_WT_height_m"].dropna()

    summary_rows = [
        ("field tree/stem records with Lat/Long + Footprint", len(field)),
        ("matched pairs (segmented <-> field)", len(matched_df)),
        ("unmatched field records", len(unmatched_field_df)),
        ("match distance cap (m)", MAX_MATCH_DISTANCE_M),
        ("matched pairs with GT Height available", len(have_gt)),
        ("mean (seg_height - GT_height), m", have_gt.mean() if len(have_gt) else np.nan),
        ("mean abs error vs GT_height, m", have_gt.abs().mean() if len(have_gt) else np.nan),
        ("RMSE vs GT_height, m", np.sqrt((have_gt ** 2).mean()) if len(have_gt) else np.nan),
        ("matched pairs with WT Height available", len(have_wt)),
        ("mean (seg_height - WT_height), m", have_wt.mean() if len(have_wt) else np.nan),
        ("mean abs error vs WT_height, m", have_wt.abs().mean() if len(have_wt) else np.nan),
        ("RMSE vs WT_height, m", np.sqrt((have_wt ** 2).mean()) if len(have_wt) else np.nan),
    ]
    summary = pd.DataFrame(summary_rows, columns=["metric", "value"])

    per_footprint = matched_df.groupby("Footprint").agg(
        n_matched=("seg_treeID", "count"),
        mean_seg_height_m=("seg_height_m", "mean"),
        mean_GT_height_m=("GT_height_m", "mean"),
        mean_error_vs_GT_m=("seg_minus_GT_height_m", "mean"),
        mae_vs_GT_m=("seg_minus_GT_height_m", lambda s: s.abs().mean()),
    ).reset_index()

    with pd.ExcelWriter(OUTPUT_XLSX, engine="openpyxl") as writer:
        summary.to_excel(writer, sheet_name="Summary", index=False)
        per_footprint.to_excel(writer, sheet_name="Per-Footprint Summary", index=False)
        matched_df.to_excel(writer, sheet_name="Matched Heights", index=False)
        unmatched_field_df.to_excel(writer, sheet_name="Unmatched Field Trees", index=False)

    print(f"Wrote {OUTPUT_XLSX}")
    print(summary.to_string(index=False))
    print()
    print(per_footprint.to_string(index=False))

if __name__ == "__main__":
    main()
