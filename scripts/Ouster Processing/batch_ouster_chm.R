library(terra)
library(sf)
library(RCSF)
library(lidR)

base_dir    <- "C:/Users/davisk10/OneDrive - Cal Poly/Tree Biomass Estimation Research - Documents/Arboretum Info"
clips_dir   <- file.path(base_dir, "Arb Ouster Files", "clips")
polys_path  <- file.path(base_dir, "arb_bio_test_2_gedi_footprints_clipped.geojson")
rasters_dir <- file.path(base_dir, "Rasters")  # finished footprints are skipped on rerun, so delete a footprint's folder to redo it

res_m    <- 0.25   # DTM and CHM pixel size (m)
buffer_m <- 10     # buffer used for the buffered CHM (must match the clipping script)
max_z    <- Inf    # drop points above this height (m); Inf = no cap (noise already removed). Was 6; fall back to 20 if stray high points show up
polys    <- st_make_valid(st_read(polys_path, quiet = TRUE))
# Clip numbers are footprint reading_order_id values (clipping script names clips by footprint id).
# Buffer in a metric CRS (UTM 10N) first, then transform to the CHM's CRS later.
polys_utm <- st_transform(polys, 32610)

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

    # 6. Clip to this footprint's polygon (exact). The buffered version is built from the full-extent CHM at the end.
    poly_utm <- polys_utm[polys_utm$reading_order_id == fp, ]
    if (nrow(poly_utm) == 0) stop("no polygon with reading_order_id == ", fp)
    poly     <- st_transform(poly_utm, crs = terra::crs(chm))
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
  rm(list = intersect(c("las", "dtm", "las_norm", "chm", "chm_clipped", "poly", "poly_utm"), ls()))
  invisible(gc())
}

# Combine every footprint into one raster (exact-footprint and buffered), saved in Rasters/
# Where footprints overlap (e.g. 2/3 and 4/6), merge() keeps the first raster's value.
combine <- function(pattern, out_name) {
  tifs <- list.files(rasters_dir, pattern = pattern, recursive = TRUE, full.names = TRUE)
  if (length(tifs) == 0) return(invisible(NULL))
  cat("Combining", length(tifs), "rasters ->", out_name, "\n")
  merged <- merge(sprc(lapply(tifs, rast)))
  writeRaster(merged, file.path(rasters_dir, out_name), overwrite = TRUE)
}
combine(sprintf("^oust_F\\d+_chm_%sm_clipped\\.tif$", res_m),  sprintf("oust_all_chm_%sm_clipped.tif", res_m))

# Buffered combined raster: mask each footprint's full-extent CHM to its 10 m buffered polygon (in memory), then merge
full_tifs <- list.files(rasters_dir, pattern = sprintf("^oust_F\\d+_chm_%sm\\.tif$", res_m), recursive = TRUE, full.names = TRUE)
if (length(full_tifs) > 0) {
  buf_out <- sprintf("oust_all_chm_%sm_buffered.tif", res_m)
  cat("Combining", length(full_tifs), "rasters ->", buf_out, "\n")
  bufs <- lapply(full_tifs, function(p) {
    fp  <- as.integer(sub("^oust_F(\\d+)_.*$", "\\1", basename(p)))
    chm <- rast(p)
    pb  <- st_transform(st_buffer(polys_utm[polys_utm$reading_order_id == fp, ], buffer_m), crs = terra::crs(chm))
    mask(crop(chm, vect(pb)), vect(pb))
  })
  writeRaster(merge(sprc(bufs)), file.path(rasters_dir, buf_out), overwrite = TRUE)
}

cat("\nFinished. Failed footprints:", if (length(failed)) paste(failed, collapse = ", ") else "none", "\n")
