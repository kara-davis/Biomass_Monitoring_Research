# Clip a CHM raster to the arboretum boundary (AOI).
# Same logic as section "7. Clip to AOI Boundary" in las_to_chm_workflow.ipynb,
# but runs headlessly -- no tk_choose.dir()/readline() pickers -- so it works
# on any machine as long as the paths below are edited to match that machine.
#
# Requires: terra, sf (install.packages(c("terra","sf")) if needed)

suppressPackageStartupMessages({
  library(terra)
  library(sf)
})

# ---- Edit these four lines for your machine ----
chm_path     <- "PASTE_PATH_TO_UNCLIPPED_CHM.tif"        # e.g. ".../chm_0.25m.tif"
gdb_path     <- "PASTE_PATH_TO_BOUNDARY.gdb"               # geodatabase containing the AOI polygon
layer_name   <- "arb_blob"                                 # AOI boundary layer name within the .gdb
out_path     <- "PASTE_OUTPUT_PATH_FOR_CLIPPED_CHM.tif"    # e.g. ".../chm_0.25m_clipped.tif"
# --------------------------------------------------

chm <- rast(chm_path)

boundary <- st_read(gdb_path, layer = layer_name, quiet = TRUE)
boundary <- st_transform(boundary, crs = terra::crs(chm))

chm_clipped <- mask(crop(chm, vect(boundary)), vect(boundary))

writeRaster(chm_clipped, out_path, overwrite = TRUE)
cat("Clipped CHM written to", out_path, "\n")

cat("\n-- CHM summary (clipped) --\n")
print(summary(values(chm_clipped), na.rm = TRUE))
