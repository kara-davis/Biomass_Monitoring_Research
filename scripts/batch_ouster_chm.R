library(terra)
library(sf)
library(RCSF)
library(lidR)

base_dir    <- "C:/Users/davisk10/OneDrive - Cal Poly/Tree Biomass Estimation Research - Documents/Bartleson Ranch"
clips_dir   <- file.path(base_dir, "Drone and Bucket Georef at MASL", "clips")
polys_path  <- file.path(base_dir, "Drone and Bucket Georef at MASL", "6423_selected_footprints.gpkg")
rasters_dir <- file.path(base_dir, "Rasters")

res_m    <- 0.25   # DTM and CHM pixel size (m)
max_z    <- 6      # drop points above this height (m); trees here are <= ~5 m
polys    <- st_make_valid(st_read(polys_path, quiet = TRUE))

files <- list.files(clips_dir, pattern = "^O\\d+_clip\\.las$", full.names = TRUE)
files <- files[order(as.integer(sub("^O(\\d+)_clip\\.las$", "\\1", basename(files))))]
failed <- character()

for (f in files) {
  fp  <- as.integer(sub("^O(\\d+)_clip\\.las$", "\\1", basename(f)))
  tag <- sprintf("F%d", fp)
  out_dir <- file.path(rasters_dir, sprintf("Footprint %d", fp))
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  clipped_path <- file.path(out_dir, sprintf("oust_%s_chm_%sm_clipped.tif", tag, res_m))
  if (file.exists(clipped_path)) {
    cat("Skipping", tag, "(already done)\n")
    next
  }

  cat("\n=== Footprint", fp, "===\n")
  res <- tryCatch({
    # 1. Load (Ouster has no return info, so set it and drop duplicates)
    las <- suppressWarnings(readLAS(f, select = "xyzrcin"))
    data.table::set(las@data, j = "ReturnNumber",    value = 1L)
    data.table::set(las@data, j = "NumberOfReturns", value = 1L)
    las <- filter_duplicates(las)

    # 2. Ground classification (CSF)
    las <- classify_ground(las, algorithm = csf(
      sloop_smooth     = FALSE,
      class_threshold  = 0.15,
      cloth_resolution = 1,
      rigidness        = 3,
      iterations       = 500,
      time_step        = 0.65
    ))

    # 3. DTM (TIN)
    dtm <- rasterize_terrain(las, res = res_m, algorithm = tin())
    writeRaster(dtm, file.path(out_dir, sprintf("oust_%s_dtm_%sm.tif", tag, res_m)), overwrite = TRUE)

    # 4. Height-normalise and cap heights
    las_norm <- normalize_height(las, dtm)
    las_norm <- filter_poi(las_norm, Z >= 0 & Z <= max_z)

    # 5. CHM from the normalised cloud
    chm <- rasterize_canopy(las_norm, res = res_m, algorithm = p2r(subcircle = 0.1))
    writeRaster(chm, file.path(out_dir, sprintf("oust_%s_chm_%sm.tif", tag, res_m)), overwrite = TRUE)

    # 6. Clip to this footprint's polygon
    poly <- st_transform(polys[polys$Label == fp, ], crs = terra::crs(chm))
    if (nrow(poly) == 0) stop("no polygon with Label == ", fp)
    chm_clipped <- mask(crop(chm, vect(poly)), vect(poly))
    writeRaster(chm_clipped, clipped_path, overwrite = TRUE)

    cat("Done:", tag, "->", out_dir, "\n")
    TRUE
  }, error = function(e) {
    cat("FAILED", tag, ":", conditionMessage(e), "\n")
    FALSE
  })
  if (!res) failed <- c(failed, tag)

  # free memory before the next file
  rm(list = intersect(c("las", "dtm", "las_norm", "chm", "chm_clipped", "poly"), ls()))
  invisible(gc())
}

# Combine every footprint into one raster (unclipped and clipped), saved in Rasters/
combine <- function(pattern, out_name) {
  tifs <- list.files(rasters_dir, pattern = pattern, recursive = TRUE, full.names = TRUE)
  if (length(tifs) == 0) return(invisible(NULL))
  cat("Combining", length(tifs), "rasters ->", out_name, "\n")
  merged <- merge(sprc(lapply(tifs, rast)))
  writeRaster(merged, file.path(rasters_dir, out_name), overwrite = TRUE)
}
combine(sprintf("^oust_F\\d+_chm_%sm\\.tif$", res_m),         sprintf("oust_all_chm_%sm.tif", res_m))
combine(sprintf("^oust_F\\d+_chm_%sm_clipped\\.tif$", res_m), sprintf("oust_all_chm_%sm_clipped.tif", res_m))

cat("\nFinished. Failed footprints:", if (length(failed)) paste(failed, collapse = ", ") else "none", "\n")
