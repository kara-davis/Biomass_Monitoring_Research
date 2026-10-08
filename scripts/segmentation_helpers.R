# Shared helpers for the single-resolution segmentation notebooks
# (tree_segmentation_dalponte.ipynb, tree_segmentation_watershed.ipynb).
# Everything here works on a crown-ID raster (terra SpatRaster) + treetops (sf points).

suppressPackageStartupMessages({ library(terra); library(sf); library(dplyr) })

# Crown polygons + per-crown stats from a crown-ID raster
crown_polygons <- function(crowns, chm, ttops) {
  names(crowns) <- "treeID"
  polys <- st_as_sf(as.polygons(crowns, dissolve = TRUE))
  polys$area_m2   <- as.numeric(st_area(polys))
  polys$diam_m    <- 2 * sqrt(polys$area_m2 / pi)            # equivalent circular diameter
  polys$max_h_m   <- terra::extract(chm, vect(polys), fun = max, na.rm = TRUE)[, 2]
  polys$n_treetops <- lengths(st_intersects(polys, ttops))    # >1 means an ID was split/merged oddly
  polys
}

# For every pair of touching crowns, find the "saddle" (highest pass between them along
# the shared boundary) and the prominence of the shorter tree above that saddle.
# Low prominence + short distance between tops = probably ONE tree split into two.
adjacent_pairs <- function(crowns, chm, ttops) {
  id <- as.matrix(crowns, wide = TRUE)
  h  <- as.matrix(chm,    wide = TRUE)
  nr <- nrow(id); nc <- ncol(id)

  collect <- function(a, b, ha, hb) {
    keep <- !is.na(a) & !is.na(b) & a != b
    data.frame(a = pmin(a[keep], b[keep]), b = pmax(a[keep], b[keep]),
               pass = pmin(ha[keep], hb[keep]))
  }
  pairs <- bind_rows(
    collect(id[, -nc], id[, -1],  h[, -nc], h[, -1]),    # horizontal neighbours
    collect(id[-nr, ], id[-1, ],  h[-nr, ], h[-1, ])     # vertical neighbours
  )
  if (!nrow(pairs)) return(pairs)

  saddle <- pairs |> group_by(a, b) |>
    summarise(saddle_h = max(pass, na.rm = TRUE), boundary_cells = n(), .groups = "drop")

  tt <- data.frame(treeID = ttops$treeID, h = ttops$height, st_coordinates(ttops)[, 1:2])
  saddle |>
    left_join(tt, by = c("a" = "treeID")) |> rename(h_a = h, xa = X, ya = Y) |>
    left_join(tt, by = c("b" = "treeID")) |> rename(h_b = h, xb = X, yb = Y) |>
    mutate(dist_m     = sqrt((xa - xb)^2 + (ya - yb)^2),
           prominence = pmin(h_a, h_b) - saddle_h)
}

# Flag likely over-segmentation:
#   pair rule : touching crowns, tops < max_dist apart, shorter top rises < min_prom above the saddle
#   small rule: crown area below min_area_m2
flag_overseg <- function(polys, pairs, min_prom = 1.0, max_dist = 4.0, min_area_m2 = 3) {
  suspect_pairs <- pairs |> filter(prominence < min_prom, dist_m < max_dist)
  polys$small   <- polys$area_m2 < min_area_m2
  polys$in_suspect_pair <- polys$treeID %in% c(suspect_pairs$a, suspect_pairs$b)
  polys$flag <- case_when(polys$in_suspect_pair & polys$small ~ "suspect pair + small",
                          polys$in_suspect_pair ~ "suspect pair",
                          polys$small ~ "small crown",
                          TRUE ~ "ok")
  list(polys = polys, suspect_pairs = suspect_pairs)
}

# Four-panel view of one window: CHM + tops | crowns | crowns coloured by flag | suspect-pair links
plot_overseg_window <- function(chm, polys, ttops, suspect_pairs, window, title = "") {
  e <- ext(window); xr <- c(xmin(e), xmax(e)); yr <- c(ymin(e), ymax(e))
  bb <- st_bbox(c(xmin = xr[1], xmax = xr[2], ymin = yr[1], ymax = yr[2]), crs = st_crs(ttops))
  op <- par(mfrow = c(1, 3), mar = c(2, 2, 3, 3)); on.exit(par(op))
  chm_w <- crop(chm, e)
  tt_w  <- ttops[st_intersects(ttops, st_as_sfc(bb), sparse = FALSE)[, 1], ]
  pol_w <- suppressWarnings(st_crop(polys, bb))

  # 1. CHM + treetops
  plot(chm_w, col = hcl.colors(50, "Viridis"), main = paste(title, "CHM + treetops"))
  plot(st_geometry(tt_w), add = TRUE, pch = 3, col = "white", lwd = 2, cex = 1.2)

  # 2. crowns, each a distinct colour, thick black outline
  set.seed(1)
  cols <- sample(hcl.colors(max(nrow(pol_w), 2), "Set 3"))
  plot(chm_w, col = gray.colors(50, 0.3, 1), legend = FALSE, main = paste(title, "crowns"))
  plot(st_geometry(pol_w), col = adjustcolor(cols, 0.55), border = "black", lwd = 1.5, add = TRUE)
  plot(st_geometry(tt_w), add = TRUE, pch = 3, col = "black", lwd = 2)

  # 3. over-segmentation flags
  flag_cols <- c("ok" = "#cccccc", "small crown" = "#f4a300",
                 "suspect pair" = "#e03131", "suspect pair + small" = "#7b0000")
  plot(chm_w, col = gray.colors(50, 0.3, 1), legend = FALSE, main = paste(title, "over-segmentation flags"))
  plot(st_geometry(pol_w), col = adjustcolor(flag_cols[pol_w$flag], 0.6), border = "black", lwd = 1.5, add = TRUE)
  if (nrow(suspect_pairs)) {
    in_w <- suspect_pairs |> filter(xa >= xr[1], xa <= xr[2], ya >= yr[1], ya <= yr[2])
    if (nrow(in_w)) segments(in_w$xa, in_w$ya, in_w$xb, in_w$yb, col = "red", lwd = 3)
  }
  plot(st_geometry(tt_w), add = TRUE, pch = 3, col = "black", lwd = 2)
  legend("topright", legend = names(flag_cols), fill = adjustcolor(flag_cols, 0.6), bg = "white", cex = 0.8)
}

# ---------------------------------------------------------------------------
# Ground-truth height comparison
# ---------------------------------------------------------------------------

# Load surveyed trees, drop rows without a height and non-orchard "test" rows
# (wind turbine / tall eucalyptus etc.), and reproject to the CHM CRS.
read_ground_trees <- function(path, crs_target, sheet = "Left_Join",
                              height_col = "app_ground_truth_ht_m") {
  g <- readxl::read_excel(path, sheet = sheet, .name_repair = "minimal")
  g <- g[!is.na(g$ground_x) & !is.na(g[[height_col]]), ]            # needs ground coords + height
  g <- st_as_sf(g, coords = c("ground_x", "ground_y"), crs = 4326) |> st_transform(crs_target)
  g$Tree_Label  <- g$tree_label
  g$GT_DBH      <- g$`app_ground_truth_dbh_m` * 100                      # m to cm conversion
  g$gt_height_m <- g[[height_col]]
  g[!grepl("test", tolower(paste(g$tree_label, g$app_notes))), ]
}

# One-to-one nearest-neighbour matching (closest pairs first) within max_dist.
# Segmented height is reported two ways: treetop height from the SMOOTHED CHM, and the
# maximum RAW-CHM value inside the matched crown (smoothing lowers peaks).
match_ground_trees <- function(ground, ttops, polys, chm_raw, max_dist = 2.5) {
  d <- st_distance(ground, ttops); d <- matrix(as.numeric(d), nrow = nrow(ground))
  cand <- which(d <= max_dist, arr.ind = TRUE)
  cand <- cand[order(d[cand]), , drop = FALSE]
  g_used <- rep(FALSE, nrow(ground)); t_used <- rep(FALSE, nrow(ttops)); keep <- integer(0)
  for (k in seq_len(nrow(cand))) {
    i <- cand[k, 1]; j <- cand[k, 2]
    if (!g_used[i] && !t_used[j]) { g_used[i] <- TRUE; t_used[j] <- TRUE; keep <- c(keep, k) }
  }
  m <- cand[keep, , drop = FALSE]

  raw_max <- terra::extract(chm_raw, vect(polys), fun = max, na.rm = TRUE)[, 2]
  out <- data.frame(
    ground_row   = m[, 1], treeID = ttops$treeID[m[, 2]],
    label        = ground$Tree_Label[m[, 1]],
    dist_m       = d[m],
    gt_height_m  = ground$gt_height_m[m[, 1]],
    seg_height_m = ttops$height[m[, 2]],
    raw_max_m    = raw_max[match(ttops$treeID[m[, 2]], polys$treeID)],
    xg = st_coordinates(ground)[m[, 1], 1], yg = st_coordinates(ground)[m[, 1], 2],
    xt = st_coordinates(ttops)[m[, 2], 1],  yt = st_coordinates(ttops)[m[, 2], 2])
  out$err_seg <- out$seg_height_m - out$gt_height_m
  out$err_raw <- out$raw_max_m    - out$gt_height_m
  out
}

height_metrics <- function(est, obs) {
  e <- est - obs
  c(n = length(e), bias = mean(e), MAE = mean(abs(e)), RMSE = sqrt(mean(e^2)),
    R2 = suppressWarnings(cor(est, obs)^2))
}
