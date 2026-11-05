library(lidR); library(sf)

dir   <- "C:/Users/kdavis99/OneDrive - Cal Poly/Tree Biomass Estimation Research - Documents/Bartleson Ranch/Drone and Bucket Georef at MASL"
polys <- st_make_valid(st_read(file.path(dir, "6423_buffered_selected_footprints.gpkg"), quiet = TRUE))

out_dir <- file.path(dir, "clips")
dir.create(out_dir, showWarnings = FALSE)

for (i in 1:10) {
  las  <- readLAS(file.path(dir, sprintf("O%d_done_20261013.las", i)))
  poly <- st_transform(polys[polys$Label == i, ], st_crs(las))
  clip <- clip_roi(las, poly)
  if (!is.empty(clip)) writeLAS(clip, file.path(out_dir, sprintf("O%d_clip.las", i)))
}