# scripts/

- `bpines_process_gedi.py` — parses a GEDI L2A HDF5 file into a filtered GeoDataFrame of shot points.
- `compare_heights_within_footprints.py` — matches segmented tree heights (`outputs/tree_heights_*.csv`) to the "Biomass Calcs" sheet within GEDI footprints and writes a comparison workbook.
- `compare_segmentation_to_treeplotter.py` — matches segmented tree heights to the "TreePlotter Data" sheet (full-plot census) and writes a comparison workbook.
- `plot_rasters.R` — generates publication-ready comparison figures from DSM/DTM/CHM GeoTIFFs.
