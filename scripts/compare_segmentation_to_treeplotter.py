"""
Compare UAV tree-segmentation output (tree_heights_04m.csv / tree_heights_025m.csv,
from uav_to_biomass.ipynb) to the arboretum field inventory
(WorkingTrees_Arboretum_Data.xlsx, sheet "TreePlotter Data").

Read-only with respect to existing project files: writes a new Excel workbook,
does not modify the tree_heights_*.csv / treetops_*.gpkg segmentation outputs
or WorkingTrees_Arboretum_Data.xlsx.

Matching: each segmented treetop is paired with its nearest TreePlotter Data
tree (by planar distance in meters), capped at MAX_MATCH_DISTANCE_M. Matching
is one-to-one (greedy nearest-neighbor, closest pairs assigned first).

Coordinate systems:
  - tree_heights_*.csv: x, y in EPSG:32610 (WGS84 UTM Zone 10N), confirmed from
    treetops_*.gpkg's gpkg_geometry_columns / gpkg_spatial_ref_sys tables.
  - TreePlotter Data: Latitude/Longitude in EPSG:4326, reprojected to EPSG:32610
    here for distance comparison.

Usage: python compare_segmentation_to_treeplotter.py [04m|025m]
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
ARBORETUM_SHEET = "TreePlotter Data"
OUTPUT_XLSX = str(OUTPUT_DIR / f"segmentation_vs_treeplotter_comparison_{CHM_SUFFIX}.xlsx")

MAX_MATCH_DISTANCE_M = 5.0

def main():
    seg = pd.read_csv(SEGMENTATION_CSV)
    seg = seg.rename(columns={"treeID": "seg_treeID", "x": "seg_x", "y": "seg_y", "height_m": "seg_height_m"})

    ref = pd.read_excel(ARBORETUM_XLSX, sheet_name=ARBORETUM_SHEET)
    ref = ref.dropna(subset=["Latitude", "Longitude"]).reset_index(drop=True)

    transformer = Transformer.from_crs("EPSG:4326", "EPSG:32610", always_xy=True)
    ref_x, ref_y = transformer.transform(ref["Longitude"].values, ref["Latitude"].values)
    ref["ref_x"] = ref_x
    ref["ref_y"] = ref_y

    # pairwise distance matrix (segmented x reference)
    sx = seg["seg_x"].values[:, None]
    sy = seg["seg_y"].values[:, None]
    rx = ref["ref_x"].values[None, :]
    ry = ref["ref_y"].values[None, :]
    dist = np.sqrt((sx - rx) ** 2 + (sy - ry) ** 2)

    # greedy nearest-neighbor one-to-one matching, closest pairs first
    n_seg, n_ref = dist.shape
    flat_order = np.dstack(np.unravel_index(np.argsort(dist, axis=None), dist.shape))[0]
    seg_used = np.zeros(n_seg, dtype=bool)
    ref_used = np.zeros(n_ref, dtype=bool)
    matches = []
    for i, j in flat_order:
        d = dist[i, j]
        if d > MAX_MATCH_DISTANCE_M:
            break
        if seg_used[i] or ref_used[j]:
            continue
        seg_used[i] = True
        ref_used[j] = True
        matches.append((i, j, d))

    match_rows = []
    for i, j, d in matches:
        row = {
            "seg_treeID": seg.loc[i, "seg_treeID"],
            "seg_x": seg.loc[i, "seg_x"],
            "seg_y": seg.loc[i, "seg_y"],
            "seg_height_m": seg.loc[i, "seg_height_m"],
            "distance_m": d,
            "ref_fid": ref.loc[j, "fid"],
            "ref_Common_Name": ref.loc[j, "Common Name"],
            "ref_Latin_Name": ref.loc[j, "Latin Name"],
            "ref_DBH_in": ref.loc[j, "DBH (in)"],
            "ref_Condition": ref.loc[j, "Condition"],
            "ref_Latitude": ref.loc[j, "Latitude"],
            "ref_Longitude": ref.loc[j, "Longitude"],
        }
        match_rows.append(row)
    matched_df = pd.DataFrame(match_rows).sort_values("distance_m").reset_index(drop=True)

    unmatched_seg_df = seg.loc[~seg_used].reset_index(drop=True)
    unmatched_ref_df = ref.loc[~ref_used].drop(columns=["ref_x", "ref_y"]).reset_index(drop=True)

    summary = pd.DataFrame({
        "metric": [
            "segmented treetops (total)",
            "TreePlotter Data rows with coordinates (total)",
            "matched pairs",
            "unmatched segmented treetops",
            "unmatched TreePlotter Data rows",
            "match distance cap (m)",
            "mean match distance (m)",
            "median match distance (m)",
            "max match distance (m)",
        ],
        "value": [
            n_seg,
            n_ref,
            len(matched_df),
            len(unmatched_seg_df),
            len(unmatched_ref_df),
            MAX_MATCH_DISTANCE_M,
            matched_df["distance_m"].mean() if len(matched_df) else np.nan,
            matched_df["distance_m"].median() if len(matched_df) else np.nan,
            matched_df["distance_m"].max() if len(matched_df) else np.nan,
        ],
    })

    with pd.ExcelWriter(OUTPUT_XLSX, engine="openpyxl") as writer:
        summary.to_excel(writer, sheet_name="Summary", index=False)
        matched_df.to_excel(writer, sheet_name="Matched Pairs", index=False)
        unmatched_seg_df.to_excel(writer, sheet_name="Unmatched Segmented", index=False)
        unmatched_ref_df.to_excel(writer, sheet_name="Unmatched TreePlotter", index=False)

    print(f"Wrote {OUTPUT_XLSX}")
    print(summary.to_string(index=False))

if __name__ == "__main__":
    main()
