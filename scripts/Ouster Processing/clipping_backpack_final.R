library(lidR); library(sf)

base_dir <- "C:/Users/davisk10/OneDrive - Cal Poly/Tree Biomass Estimation Research - Documents/Bartleson Ranch"
in_dir   <- file.path(base_dir, "Ouster Backpack Final Files")
polys    <- st_make_valid(st_read(file.path(base_dir, "Drone and Bucket Georef at MASL", "6423_buffered_selected_footprints.gpkg"), quiet = TRUE))

out_dir <- file.path(in_dir, "clips")
dir.create(out_dir, showWarnings = FALSE)

# The computer is low on disk space, so push OneDrive files back to cloud-only once we are done with them
free_up <- function(path) {
  if (file.exists(path)) system2("attrib", c("+U", "-P", shQuote(normalizePath(path), type = "cmd")))
}

prev_clip <- NULL
for (i in 1:10) {
  in_path   <- file.path(in_dir, sprintf("O%d_clean_20261013.las", i))
  clip_path <- file.path(out_dir, sprintf("O%d_clip.las", i))

  if (!file.exists(clip_path)) {
    las  <- readLAS(in_path)
    poly <- st_transform(polys[polys$Label == i, ], st_crs(las))
    clip <- clip_roi(las, poly)
    if (!is.empty(clip)) writeLAS(clip, clip_path) else cat("O", i, ": empty clip\n", sep = "")
    cat("O", i, ": ", npoints(las), " -> ", npoints(clip), " points\n", sep = "")
    rm(las, clip, poly); invisible(gc())
  } else {
    cat("O", i, ": clip already exists, skipping\n", sep = "")
  }

  free_up(in_path)                       # drop the big input from local disk
  if (!is.null(prev_clip)) free_up(prev_clip)  # previous clip has had time to upload
  prev_clip <- clip_path
}
free_up(prev_clip)
