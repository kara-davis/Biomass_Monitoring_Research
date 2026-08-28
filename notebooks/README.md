# notebooks/

- `gedi_footprint_1_extract.ipynb` — pulls GEDI L2A shots over an AOI, filters to high-quality returns, and exports clipped point/footprint GeoJSONs (part 1 of 2).
- `gedi_footprint_2_analysis.ipynb` — loads the GeoJSONs from part 1 and runs the Monte Carlo simulation and CHM comparison analysis (part 2 of 2).
- `gedi_footprint_og.ipynb` — original single-notebook GEDI extraction workflow, superseded by the split `_1_extract`/`_2_analysis` pair.
- `las_to_chm_workflow.ipynb` — processes raw LAS point clouds into DSM/DTM/CHM rasters and clips them to the AOI boundary.
- `uav_biomass_fu2025_mapped_trees.ipynb` — self-contained, alternate end-to-end pipeline (adapted from Fu et al. 2025) that goes all the way from raw UAV point cloud to biomass estimates, calibrated tree-by-tree against the mapped/inventoried field trees (not yet using the sweep-selected segmentation parameters below).
- `uav_to_biomass.ipynb` — canonical, current pipeline notebook: segments trees from the CHM using the sweep-selected parameter combos (see `Parameter_Sweep_Analysis/`) and writes tree height/location outputs for both CHM resolutions; biomass estimation from these outputs is not yet implemented.
