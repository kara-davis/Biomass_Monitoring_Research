# Side-by-side footprint visualizations: Dalponte (left) vs watershed (right).
# Uses the saved outputs of notebooks 7 and 8, so no segmentation is re-run.
# Run from the scripts/ folder. Writes one PNG per footprint (named by new footprint number) to outputs/.
suppressPackageStartupMessages({ library(terra); library(sf); library(lidR); library(dplyr) })   # lidR provides height.colors()

# Paths below are relative to scripts/; when sourced from elsewhere, switch to this file's folder (restored at the end)
old_wd     <- getwd()
script_dir <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) NULL)
if (!is.null(script_dir) && nzchar(script_dir)) setwd(script_dir)

res        <- "0.5m"
smooth_k   <- 3
pad        <- 8
fp_rename  <- c("9" = 1, "10" = 2, "8" = 3, "7" = 4, "6" = 5, "5" = 6, "11" = 7, "12" = 8, "3" = 9, "4" = 10)   # old footprint label -> new title number

seg_dir <- "../outputs/Bartleson Tree Segmentation"
dir_dal <- file.path(seg_dir, paste0("dalponte_",  res))
dir_ws  <- file.path(seg_dir, paste0("watershed_", res))

chm        <- rast(sprintf("../../Rasters/bart_chm_%s_clipped.tif", res))
chm[chm > 7] <- NA
chm_smooth <- focal(chm, w = matrix(1, smooth_k, smooth_k), fun = median, na.rm = TRUE)
footprints <- st_read("../../selected_v3_footprints_10.gpkg", quiet = TRUE) |> st_transform(st_crs(chm))

load_method <- function(d) list(
  polys = st_read(file.path(d, "crowns.gpkg"),   quiet = TRUE),
  ttops = st_read(file.path(d, "treetops.gpkg"), quiet = TRUE),
  cmp   = read.csv(file.path(d, "ground_height_comparison.csv"), stringsAsFactors = FALSE)
)
methods <- list(Dalponte = load_method(dir_dal), Watershed = load_method(dir_ws))

plot_panel <- function(m, name, prefix, e, bb) {
  g <- m$cmp[!is.na(m$cmp$gt_x) & grepl(paste0("^", prefix, "\\."), m$cmp$label), ]
  n_match <- sum(g$matched)
  plot(crop(chm_smooth, e), col = height.colors(50), range = c(0, 6),
       main = sprintf("%s  (%d of %d trees matched)", name, n_match, nrow(g)), cex.main = 1.1)

  tt_w <- m$ttops[st_intersects(m$ttops, st_as_sfc(bb), sparse = FALSE)[, 1], ]
  plot(st_geometry(tt_w), add = TRUE, pch = 3, col = adjustcolor("blue", 0.3))
  plot(st_geometry(m$polys[m$polys$treeID %in% g$seg_treeID, ]), border = "white", col = NA, lwd = 2, add = TRUE)
  plot(st_geometry(footprints), border = "yellow", col = NA, lwd = 2, add = TRUE)

  mt <- g[g$matched, ]
  segments(mt$gt_x, mt$gt_y, mt$seg_x, mt$seg_y, col = "black", lwd = 1.5)
  points(mt$seg_x, mt$seg_y, pch = 3, col = "blue", lwd = 3, cex = 1.5)
  points(g$gt_x, g$gt_y, pch = 4, col = "red", lwd = 3, cex = 1.5)
  text(g$gt_x, g$gt_y, g$label, pos = 3, col = "white", cex = 1, font = 2)
}

out_dir <- file.path(seg_dir, "footprint_dalponte_vs_watershed")
dir.create(out_dir, showWarnings = FALSE)
unlink(list.files(out_dir, pattern = "^footprint_.*png$", full.names = TRUE))
for (p in names(sort(fp_rename))) {
  g <- methods$Dalponte$cmp[!is.na(methods$Dalponte$cmp$gt_x) & grepl(paste0("^", p, "\\."), methods$Dalponte$cmp$label), ]
  if (!nrow(g)) next   # no surveyed trees in this footprint
  png(file.path(out_dir, sprintf("footprint_%02d.png", fp_rename[[p]])), width = 2000, height = 1000, res = 100)
  e  <- ext(min(g$gt_x) - pad, max(g$gt_x) + pad, min(g$gt_y) - pad, max(g$gt_y) + pad)
  bb <- st_bbox(c(xmin = xmin(e), xmax = xmax(e), ymin = ymin(e), ymax = ymax(e)), crs = st_crs(chm))

  layout(matrix(c(1, 1, 2, 3), nrow = 2, byrow = TRUE), heights = c(0.08, 0.92))
  par(mar = c(0, 0, 0, 0)); plot.new()
  text(0.5, 0.5, sprintf("Footprint %d", fp_rename[[p]]), cex = 2, font = 2)
  par(mar = c(3, 3, 3, 1))
  for (nm in names(methods)) plot_panel(methods[[nm]], nm, p, e, bb)
  par(fig = c(0, 1, 0, 1), mar = c(0, 0, 0, 0), new = TRUE); plot.new()
  legend("bottom", horiz = TRUE, bty = "n", bg = "white",
         legend = c("Ground-measured", "Segmented treetop", "Other treetops", "Matched crown", "GEDI footprint"),
         pch = c(4, 3, 3, NA, NA), col = c("red", "blue", adjustcolor("blue", 0.3), "white", "yellow"),
         lty = c(NA, NA, NA, 1, 1), lwd = c(3, 3, 1, 2, 2))
  dev.off()
}
cat("Saved to", normalizePath(out_dir), "\n")
setwd(old_wd)
