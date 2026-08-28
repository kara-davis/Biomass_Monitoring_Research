# Parameter_Sweep_Analysis/

- `clip_chm.R` — headlessly clips the 0.4m CHM to the arboretum AOI boundary (non-interactive version of the notebook step).
- `clip_chm_025m.R` — headlessly clips the 0.25m CHM to the arboretum AOI boundary.
- `sweep_segmentation.R` — runs the parameter sweep over smoothing-kernel and detection-window settings, writing one tree_heights CSV per combo to `sweep_outputs*/`.
- `compare_sweep_results.py` — scores every sweep combo's output against field ground-truth heights and ranks them by match count and height error.
- `sweep_outputs/`, `sweep_outputs_025m/` — per-combo segmentation CSVs from the sweep, one directory per CHM resolution (gitignored, regenerate via `sweep_segmentation.R`).
- `sweep_results_summary.xlsx`, `sweep_results_summary_025m.xlsx` — scored/ranked summary of the sweep results per CHM resolution (gitignored, regenerate via `compare_sweep_results.py`).
