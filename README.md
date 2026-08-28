# Biomass_Monitoring_Research
This repository contains code and information regarding using and processing LiDAR data from GEDI and UAVs.

## Repo layout
- `notebooks/` — Jupyter notebooks (GEDI footprint processing, LAS→CHM workflow, UAV→biomass segmentation)
- `scripts/` — standalone Python/R scripts (GEDI processing, segmentation comparison, raster plotting)
- `Parameter_Sweep_Analysis/` — self-contained tree-segmentation parameter sweep (scripts + summary outputs)
- `data/` — source data tracked in git (e.g. `WorkingTrees_Arboretum_Data.xlsx`)
- `outputs/` — generated results (CSVs, GeoPackages, comparison workbooks/HTML); gitignored, regenerate via the notebooks/scripts above
- `docs/` — supporting documentation (LiDAR workflow writeup, Ouster processing notes)

## Future Edits to be Made: (Reference NASA CoLab Notebook)
  * Pull corresponding waveforms of the footprints
  * Print reference map
  * Pull corresponding L4 products for biomass
  * Create universal variable names that can be easily updated at top of file to allow for new AOI's to be run more easily
<img width="1286" height="856" alt="image" src="https://github.com/user-attachments/assets/a918ae6d-bd42-4791-a2de-b6659aca8784" />
<img width="1286" height="859" alt="image" src="https://github.com/user-attachments/assets/130a70e7-db4f-455d-8e33-3cca5a80fa89" />
