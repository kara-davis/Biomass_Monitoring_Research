library(lidR); library(sf)

base_dir <- "C:/Users/davisk10/OneDrive - Cal Poly/Tree Biomass Estimation Research - Documents/Arboretum Info"
in_dir   <- file.path(base_dir, "Arb Ouster Files")
out_dir  <- file.path(in_dir, "clips")
dir.create(out_dir, showWarnings = FALSE)

buffer_m <- 10
polys <- st_make_valid(st_read(file.path(base_dir, "arb_bio_test_2_gedi_footprints_clipped.geojson"), quiet = TRUE))
# Buffer in a metric CRS (UTM 10N), then transform to each scan's CRS when clipping
polys <- st_buffer(st_transform(polys, 32610), buffer_m)

# The computer is low on disk space, so push OneDrive files back to cloud-only once we are done with them
free_up <- function(path) {
  if (file.exists(path)) system2("attrib", c("+U", "-P", shQuote(normalizePath(path), type = "cmd")))
}

# Scan files are named like drone_georef_O1_arb__clean_20261027_leveled.las; scan number = footprint reading_order_id
files <- list.files(in_dir, pattern = "^drone_georef_O[0-9]+_.*\\.las$", full.names = TRUE)
ids   <- as.integer(sub("^drone_georef_O([0-9]+)_.*$", "\\1", basename(files)))
files <- files[order(ids)]; ids <- sort(ids)

# Scans O5 and O6 are swapped relative to the footprint reading_order_id (scan O5 = footprint 6, scan O6 = footprint 5).
# Every other scan number equals its footprint id. Clips are named by FOOTPRINT id (e.g. scan O5 -> O6_clip.las).
scan_to_fp <- c("5" = 6L, "6" = 5L)

prev_clip <- NULL
for (k in seq_along(files)) {
  scan      <- ids[k]
  i         <- if (as.character(scan) %in% names(scan_to_fp)) scan_to_fp[[as.character(scan)]] else scan  # footprint id
  in_path   <- files[k]
  clip_path <- file.path(out_dir, sprintf("O%d_clip.las", i))

  if (!file.exists(clip_path)) {
    poly <- polys[polys$reading_order_id == i, ]
    if (nrow(poly) == 0) {
      cat("O", i, ": no footprint with reading_order_id ", i, ", skipping\n", sep = "")
      next
    }
    # Read only the footprint area from disk via a catalog (full scans are too big to load into RAM)
    ctg <- readLAScatalog(in_path, progress = FALSE)
    # These scans have no CRS in the header; their coordinates are UTM 10N (EPSG:32610) metres
    if (is.na(st_crs(ctg))) st_crs(ctg) <- 32610
    poly <- st_transform(poly, st_crs(ctg))
    clip <- clip_roi(ctg, poly)
    if (!is.empty(clip)) writeLAS(clip, clip_path) else cat("O", i, ": empty clip\n", sep = "")
    cat("O", i, ": ", ctg@data$Number.of.point.records, " -> ", npoints(clip), " points\n", sep = "")
    rm(ctg, clip, poly); invisible(gc())
  } else {
    cat("O", i, ": clip already exists, skipping\n", sep = "")
  }

  free_up(in_path)                       # drop the big input from local disk
  if (!is.null(prev_clip)) free_up(prev_clip)  # previous clip has had time to upload
  prev_clip <- clip_path
}
if (!is.null(prev_clip)) free_up(prev_clip)
