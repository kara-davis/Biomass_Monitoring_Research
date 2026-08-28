# Headless clip of the unclipped 0.25m CHM to the arboretum boundary.
# Same logic as section "7. Clip to AOI Boundary" in las_to_chm_workflow.ipynb,
# but with the interactive tk_choose.dir()/readline() pickers replaced by the
# paths/layer already identified for this project (arb_blob layer in
# CODE/kdavMyProject.gdb), so it can run non-interactively.
#
# Does not modify las_to_chm_workflow.ipynb or any existing CHM files.

suppressPackageStartupMessages({
  library(terra)
  library(sf)
})

chm_path     <- "C:/Users/davisk10/OneDrive - Cal Poly/Tree Biomass Estimation Research - Documents/CODE/R code/Output Files/chm_0.25m.tif"
gdb_path     <- "C:/Users/davisk10/OneDrive - Cal Poly/Tree Biomass Estimation Research - Documents/CODE/kdavMyProject.gdb"
layer_name   <- "arb_blob"
out_dir      <- "C:/Users/davisk10/OneDrive - Cal Poly/Tree Biomass Estimation Research - Documents/CODE/R code/Output Files"
out_filename <- "chm_0.25m_clipped.tif"

chm <- rast(chm_path)

boundary <- st_read(gdb_path, layer = layer_name, quiet = TRUE)
boundary <- st_transform(boundary, crs = terra::crs(chm))

chm_clipped <- mask(crop(chm, vect(boundary)), vect(boundary))

out_path <- file.path(out_dir, out_filename)
writeRaster(chm_clipped, out_path, overwrite = TRUE)
cat("Clipped CHM written to", out_path, "\n")

cat("\n-- CHM summary (clipped) --\n")
print(summary(values(chm_clipped), na.rm = TRUE))
