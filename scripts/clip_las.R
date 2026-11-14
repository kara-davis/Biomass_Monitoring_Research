library(lidR)
library(sf)

# ---- FILL IN ----
las_in   <- "PATH/TO/rbg_point_cloud.las"
las_out  <- "PATH/TO/rbg_point_cloud_clipped.las"
boundary <- "PATH/TO/boundary.gpkg"   # .gpkg/.shp; set to NULL to use bbox below
layer    <- NULL                      # layer name if boundary has several
bbox     <- c(xmin = 0, ymin = 0, xmax = 0, ymax = 0)  # used only if boundary is NULL
# -----------------

las <- readLAS(las_in, select = "xyznrci")

if (!is.null(boundary)) {
  poly <- if (is.null(layer)) st_read(boundary, quiet = TRUE) else st_read(boundary, layer = layer, quiet = TRUE)
  poly <- st_transform(poly, st_crs(las))
  las_clip <- clip_roi(las, st_union(poly))
} else {
  las_clip <- clip_rectangle(las, bbox["xmin"], bbox["ymin"], bbox["xmax"], bbox["ymax"])
}

print(las_clip)
writeLAS(las_clip, las_out)
