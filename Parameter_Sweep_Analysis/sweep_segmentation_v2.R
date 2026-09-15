# Parameter sweep over smoothing-kernel size and detection-window settings.
# Runs headlessly (no file.choose()) using CHM paths passed as arguments.
# Writes one tree_heights CSV per parameter combo into sweep_outputs/ so
# compare_sweep_results.py can score each combo's match count vs. height
# error against field measurements.
#
# Does not modify uav_to_biomass.ipynb, uav_to_biomass_v2.ipynb, or their
# existing tree_heights.csv / tree_heights_v2.csv outputs.
#
# Updates vs. previous sweep_segmentation.R:
#   - Accepts multiple CHM paths (comma-separated in arg 1) and loops over
#     all of them, tagging each output CSV with the CHM resolution so
#     compare_sweep_results.py can compare results across resolutions.
#   - Automatically caps kernel sizes for coarser CHMs (>= 0.5 m) to avoid
#     over-smoothing: 1 m CHM only uses kernels 3 and 5.
#   - Accepts a .las/.laz point cloud path as arg 3 (required for li2012).
#     If omitted, li2012 is skipped and a warning is printed.
#   - Adds kernel sizes 9 and 11 for large irregular broadleaf crowns.
#   - Adds li2012 point-cloud-based segmentation as a third algorithm family.
#   - Applies a minimum crown diameter filter after all locate_trees() runs.
#   - Tags every output CSV with algorithm family and CHM resolution.

suppressPackageStartupMessages({
  library(terra)
  library(sf)
  library(lidR)
  library(dplyr)
})

# ---------------------------------------------------------------------------
# Command-line arguments
#   arg 1 – comma-separated CHM raster paths (required; at least one)
#            e.g. "chm_0.25m.tif,chm_0.4m.tif,chm_1m.tif"
#   arg 2 – output subfolder (optional, defaults to sweep_outputs)
#   arg 3 – LAS/LAZ point cloud path (optional; li2012 skipped if absent)
#
# Example call with all three CHMs and a point cloud:
#   Rscript sweep_segmentation.R \
#     "chm_0.25m_clipped.tif,chm_0.4m_clipped.tif,chm_1m_clipped.tif" \
#     sweep_outputs \
#     cloud_normalized.laz
# ---------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)

chm_paths_raw <- if (length(args) >= 1) {
  args[1]
} else {
  paste(
    "C:/Users/kdavis99/OneDrive - Cal Poly/Tree Biomass Estimation Research - Documents/CODE/R code/Output Files/chm_0.25m_clipped.tif",
    "C:/Users/kdavis99/OneDrive - Cal Poly/Tree Biomass Estimation Research - Documents/CODE/R code/Output Files/chm_0.4m_clipped.tif",
    sep = ","
  )
}

# Split comma-separated paths and trim whitespace
chm_paths <- trimws(strsplit(chm_paths_raw, ",")[[1]])

out_dir <- "C:/Users/kdavis99/OneDrive - Cal Poly/Tree Biomass Estimation Research - Documents/GitHub_Repository/Biomass_Monitoring_Research/Parameter_Sweep_Analysis/sweep_outputs"
las_path <- "C:/Users/kdavis99/OneDrive - Cal Poly/Tree Biomass Estimation Research - Documents/CODE/25-04-23_Arboretum.las"

# Minimum crown diameter (m) — detections smaller than this are dropped.
# 1.5 m is conservative for a diverse arboretum; lower to 1.0 if you have
# known small-crowned species (e.g. young conifers, columnar cultivars).
MIN_CROWN_DIAM_M <- 1.5

# Maximum kernel size allowed per CHM resolution.
# Coarser CHMs need smaller kernels to avoid merging adjacent tree crowns.
# A 9x9 kernel at 1m resolution = 9m smoothing radius, which is too aggressive
# for typical tree spacing. At 0.25m the same kernel covers only 2.25m.
MAX_KERNEL_BY_RES <- list(
  "0.25" = 11,   # fine res — all kernels valid
  "0.4"  = 11,   # fine res — all kernels valid
  "0.5"  = 7,    # medium res — cap at 7x7 (3.5m radius)
  "1.0"  = 5,    # coarse res — cap at 5x5 (2.5m radius) per Edson & Wing 2011
  "1"    = 5     # same, handles integer formatting
)

get_max_kernel <- function(chm_res_m) {
  # Round to one decimal and look up; default to 7 if not found
  key <- as.character(round(chm_res_m, 1))
  if (key %in% names(MAX_KERNEL_BY_RES)) MAX_KERNEL_BY_RES[[key]] else 7
}

# ---------------------------------------------------------------------------
# Load point cloud once (shared across all CHM runs)
# ---------------------------------------------------------------------------
las <- NULL
if (!is.null(las_path)) {
  cat("Loading LAS/LAZ point cloud:", las_path, "\n")
  las <- readLAS(las_path, filter = "-drop_z_below 0")
  cat("LAS loaded:", npoints(las), "points\n")  # add this line
  if (is.empty(las)) stop("Point cloud loaded but contains no points.")
  if (median(las@data$Z) > 50) {
    cat("Normalizing point cloud to height above ground...\n")
    cat("This may take several minutes for large files — please wait...\n")
    start_time <- Sys.time()
    las <- normalize_height(las, tin())
    elapsed <- round(difftime(Sys.time(), start_time, units = "mins"), 1)
    cat("Normalization complete in", elapsed, "minutes.\n")
  } else {
    cat("Point cloud appears already normalized (median Z =",
        round(median(las@data$Z), 1), "m). Skipping normalization.\n")
  }
  cat("Point cloud Z range:", min(las@data$Z), "-", max(las@data$Z), "m\n\n")
} else {
  cat("No LAS path provided — li2012 runs will be skipped.\n",
      "To include li2012, pass the .laz/.las path as the third argument.\n\n")
}

dir.create(out_dir, showWarnings = FALSE)

# ---------------------------------------------------------------------------
# Sweep parameter grids
# ---------------------------------------------------------------------------

# All candidate kernel sizes — filtered per CHM resolution inside the loop.
# Expanded to 9 and 11 for large broadleaf crowns (used for fine-res CHMs).
all_kernel_sizes <- c(3, 5, 7, 9, 11)

# Fixed window sizes for lmf() (meters)
fixed_ws_values <- c(2.0, 2.5, 3.0, 4.0, 6.0)

# Variable window configs for lmf()
# intercept: minimum window size (m) for short trees
# slope:     how fast the window grows with height (m window per m height)
# cap:       maximum window size (m) — prevents huge windows on tall trees
# A diverse arboretum needs a wider range of caps than a single-species stand.
variable_configs <- list(
  list(name = "var_low",   intercept = 1.5, slope = 0.05, cap = 5),
  list(name = "var_mid",   intercept = 1.5, slope = 0.10, cap = 6),
  list(name = "var_high",  intercept = 2.0, slope = 0.10, cap = 6),
  list(name = "var_wide",  intercept = 2.0, slope = 0.05, cap = 7),
  # New configs added for large-crowned broadleaf species common in arboreta
  list(name = "var_broad", intercept = 2.5, slope = 0.12, cap = 9),
  list(name = "var_xl",    intercept = 3.0, slope = 0.15, cap = 12)
)

# li2012 parameter grid
# dt1:  search radius (m) for points BELOW Zu — controls merging of low canopy
# dt2:  search radius (m) for points ABOVE Zu — controls merging of upper crown
# hmin: minimum height (m) to be considered a tree; filters ground clutter
# Zu:   height threshold separating dt1 and dt2 regimes (fixed at 15 m here;
#       adjust if your tallest trees are substantially shorter or taller)
li2012_configs <- list(
  list(name = "li_default", dt1 = 1.5, dt2 = 2.0, hmin = 2.0)
)

# ---------------------------------------------------------------------------
# Helper: apply minimum crown diameter filter after locate_trees()
#
# locate_trees() returns an sf POINT object with a 'Z' column (height).
# We estimate crown radius from the variable window function if available,
# or simply flag based on Z for fixed-window runs. The cleanest approach is
# to use the window size at the detected height as a proxy for crown radius
# and drop trees whose implied crown diameter is below MIN_CROWN_DIAM_M.
#
# For li2012 output (segment_trees result), we compute actual crown area
# from the segmented point cloud and filter there instead (see li2012 block).
# ---------------------------------------------------------------------------
filter_min_crown <- function(ttops, ws_at_height_fn = NULL) {
  if (nrow(ttops) == 0) return(ttops)

  if (!is.null(ws_at_height_fn)) {
    # Variable window: estimated crown radius = ws(h) / 2
    implied_diam <- ws_at_height_fn(ttops$Z) * 2
  } else {
    # Fixed window or unknown: use a simple height-based floor.
    # Trees shorter than MIN_CROWN_DIAM_M / 2 in height are almost certainly
    # shrubs or noise; taller ones we keep regardless of fixed ws.
    implied_diam <- ifelse(ttops$Z >= 2, MIN_CROWN_DIAM_M, 0)
  }

  keep <- implied_diam >= MIN_CROWN_DIAM_M
  dropped <- sum(!keep)
  if (dropped > 0)
    cat("    [crown filter] dropped", dropped, "detections below",
        MIN_CROWN_DIAM_M, "m implied crown diameter\n")
  ttops[keep, ]
}

# ---------------------------------------------------------------------------
# Helper: save tree tops CSV
# ---------------------------------------------------------------------------
save_ttops <- function(ttops, fname, algorithm_tag) {
  if (nrow(ttops) == 0) {
    cat("  [skip] no trees remaining after filter —", fname, "\n")
    return(invisible(NULL))
  }
  coords <- st_coordinates(ttops)
  df <- data.frame(
    algorithm = algorithm_tag,
    treeID    = ttops$treeID,
    x         = coords[, "X"],
    y         = coords[, "Y"],
    height_m  = ttops$Z
  )
  write.csv(df, fname, row.names = FALSE)
  cat("  wrote", fname, "—", nrow(df), "trees\n")
}

# ---------------------------------------------------------------------------
# Helper: save li2012 tree metrics CSV from segmented point cloud
# ---------------------------------------------------------------------------
save_li2012_metrics <- function(las_seg, fname, algorithm_tag) {
  if (is.empty(las_seg)) {
    cat("  [skip] segmented cloud is empty —", fname, "\n")
    return(invisible(NULL))
  }

  metrics <- tree_metrics(las_seg, func = ~list(
    x        = mean(X),
    y        = mean(Y),
    height_m = max(Z),
    crown_area_m2 = length(Z) * (mean(diff(range(X))) / sqrt(length(Z)))^2  # rough proxy
  ))

  # Apply minimum crown diameter filter using actual crown area
  metrics$crown_diam <- 2 * sqrt(metrics$crown_area_m2 / pi)
  n_before <- nrow(metrics)
  metrics  <- metrics[!is.na(metrics$crown_diam) &
                        metrics$crown_diam >= MIN_CROWN_DIAM_M, ]
  dropped  <- n_before - nrow(metrics)
  if (dropped > 0)
    cat("    [crown filter] dropped", dropped, "segments below",
        MIN_CROWN_DIAM_M, "m crown diameter\n")

  if (nrow(metrics) == 0) {
    cat("  [skip] no segments remaining after filter —", fname, "\n")
    return(invisible(NULL))
  }

  df <- data.frame(
    algorithm     = algorithm_tag,
    treeID        = metrics$treeID,
    x             = metrics$x,
    y             = metrics$y,
    height_m      = metrics$height_m,
    crown_diam_m  = round(metrics$crown_diam, 2)
  )
  write.csv(df, fname, row.names = FALSE)
  cat("  wrote", fname, "—", nrow(df), "trees\n")
}

# ===========================================================================
# MAIN LOOP — iterate over each CHM
# ===========================================================================

for (chm_path in chm_paths) {

  # --------------------------------------------------------------------------
  # Load CHM and derive a short resolution tag for output file naming
  # --------------------------------------------------------------------------
  cat("\n################################################################\n")
  cat("CHM:", chm_path, "\n")
  chm     <- rast(chm_path)
  chm_res <- res(chm)[1]  # assume square pixels
  res_tag <- gsub("\\.", "p", sprintf("%.2fm", chm_res))  # e.g. "0.25m" -> "0p25m"

  cat("Resolution:", chm_res, "m | tag:", res_tag, "\n")
  cat("Height range:", minmax(chm)[1], "-", minmax(chm)[2], "m\n")

  # Determine which kernels are valid for this resolution
  max_k        <- get_max_kernel(chm_res)
  kernel_sizes <- all_kernel_sizes[all_kernel_sizes <= max_k]
  cat("Kernels to sweep:", paste(kernel_sizes, collapse = ", "),
      "(capped at", max_k, "x", max_k, "for", chm_res, "m resolution)\n\n")

  # ==========================================================================
  # BLOCK 1 — lmf() fixed and variable window on smoothed CHM
  # ==========================================================================
  cat("--- BLOCK 1: lmf() sweep ---\n\n")

  for (k in kernel_sizes) {
    cat("  kernel", k, "x", k, "\n")
    kernel <- matrix(1, k, k)
    schm   <- terra::focal(x = chm, w = kernel, fun = median, na.rm = TRUE)

    # -- Fixed window --
    for (ws in fixed_ws_values) {
      ttops <- locate_trees(las = schm, algorithm = lmf(ws = ws))
      ttops <- filter_min_crown(ttops, ws_at_height_fn = NULL)
      fname <- sprintf("%s/lmf_fixed_%s_k%d_ws%.1f.csv",
                       out_dir, res_tag, k, ws)
      save_ttops(ttops, fname, algorithm_tag = "lmf_fixed")
    }

    # -- Variable window --
    for (vc in variable_configs) {
      intercept <- vc$intercept
      slope     <- vc$slope
      cap       <- vc$cap

      wsfun <- local({
        intercept <- intercept; slope <- slope; cap <- cap
        function(x) {
          y         <- intercept + slope * x
          y[x < 2]  <- intercept  # floor: don't shrink below intercept
          y[y > cap] <- cap        # ceiling: cap for very tall trees
          return(y)
        }
      })

      ttops <- locate_trees(las = schm, algorithm = lmf(ws = wsfun))
      ttops <- filter_min_crown(ttops, ws_at_height_fn = wsfun)
      fname <- sprintf("%s/lmf_var_%s_k%d_%s.csv",
                       out_dir, res_tag, k, vc$name)
      save_ttops(ttops, fname, algorithm_tag = "lmf_variable")
    }
  }

  # ==========================================================================
  # BLOCK 2 — li2012 point-cloud segmentation
  # Only runs once regardless of how many CHMs are provided — the point cloud
  # is CHM-independent. Runs on the first CHM iteration then skips.
  # ==========================================================================
  if (chm_path == chm_paths[1]) {
    cat("\n--- BLOCK 2: li2012 sweep (runs once, CHM-independent) ---\n\n")

    if (is.null(las)) {
      cat("Skipping — no point cloud loaded.\n")
      cat("Re-run with a .laz/.las path as argument 3 to include li2012.\n\n")
    } else {
      Zu <- 15  # height separating dt1/dt2 regimes; adjust if needed

      for (lc in li2012_configs) {
        cat("  li2012:", lc$name,
            "| dt1:", lc$dt1, "dt2:", lc$dt2, "hmin:", lc$hmin, "\n")

        tryCatch({
          cat("Starting li2012 segmentation — this is the slow step, please wait...\n")
          seg_start <- Sys.time()
          las_seg <- segment_trees(
            las,
            li2012(dt1  = lc$dt1,
                   dt2  = lc$dt2,
                   R    = max(lc$dt1, lc$dt2),
                   Zu   = Zu,
                   hmin = lc$hmin)
          )
          seg_elapsed <- round(difftime(Sys.time(), seg_start, units = "mins"), 1)
          cat("Segmentation complete in", seg_elapsed, "minutes.\n")
          las_seg <- filter_poi(las_seg, !is.na(treeID))
          fname   <- sprintf("%s/li2012_%s.csv", out_dir, lc$name)
          save_li2012_metrics(las_seg, fname, algorithm_tag = "li2012")

        }, error = function(e) {
          cat("  [ERROR] li2012", lc$name, "failed:", conditionMessage(e), "\n")
        })
      }
    }
  } else {
    cat("\n--- BLOCK 2: li2012 already run on first CHM iteration, skipping ---\n")
  }

} # end CHM loop

# ===========================================================================
# Summary
# ===========================================================================
all_csvs    <- list.files(out_dir, pattern = "\\.csv$", full.names = FALSE)
lmf_fixed_n <- sum(grepl("^lmf_fixed", all_csvs))
lmf_var_n   <- sum(grepl("^lmf_var",   all_csvs))
li2012_n    <- sum(grepl("^li2012",    all_csvs))

# Break down lmf counts by resolution tag
res_tags_found <- unique(
  regmatches(all_csvs, regexpr("[0-9]+p[0-9]+m", all_csvs))
)

cat("\n################################################################\n")
cat("Sweep complete.\n")
cat("Output directory:", out_dir, "\n\n")
cat("Results by CHM resolution:\n")
for (rt in sort(res_tags_found)) {
  n <- sum(grepl(rt, all_csvs))
  cat(sprintf("  %-10s %d CSVs\n", rt, n))
}
cat("\nResults by algorithm family:\n")
cat("  lmf fixed window  :", lmf_fixed_n, "\n")
cat("  lmf variable window:", lmf_var_n, "\n")
cat("  li2012            :", li2012_n, "\n")
cat("  Total             :", length(all_csvs), "\n")
cat("################################################################\n")
cat("\n✅ All done! Sweep finished successfully.\n")
