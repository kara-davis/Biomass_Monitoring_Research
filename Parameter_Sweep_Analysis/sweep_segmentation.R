# Parameter sweep over smoothing-kernel size and detection-window settings.
# Runs headlessly (no file.choose()) using the CHM path recorded in
# uav_to_biomass_v2.ipynb's saved output. Writes one tree_heights CSV per
# parameter combo into sweep_outputs/ so compare_sweep_results.py can score
# each combo's match count vs. height error against field measurements.
#
# Does not modify uav_to_biomass.ipynb, uav_to_biomass_v2.ipynb, or their
# existing tree_heights.csv / tree_heights_v2.csv outputs.

suppressPackageStartupMessages({
  library(terra)
  library(sf)
  library(lidR)
  library(dplyr)
})

# Pass the CHM path and an output subfolder as command-line args, e.g.:
#   Rscript sweep_segmentation.R "C:/path/to/chm_0.25m_clipped.tif" sweep_outputs_025m
# Defaults to the 0.4m CHM used in the first sweep if no args are given.
args <- commandArgs(trailingOnly = TRUE)
chm_path <- if (length(args) >= 1) args[1] else
  "C:/Users/davisk10/OneDrive - Cal Poly/Tree Biomass Estimation Research - Documents/CODE/R code/Output Files/chm_0.4m_clipped.tif"
out_dir <- if (length(args) >= 2) args[2] else "sweep_outputs"

chm <- rast(chm_path)
dir.create(out_dir, showWarnings = FALSE)

kernel_sizes <- c(3, 5, 7)
fixed_ws_values <- c(2.0, 2.5, 3.0, 4.0, 6.0)
variable_configs <- list(
  list(name = "var_low",  intercept = 1.5, slope = 0.05, cap = 5),
  list(name = "var_mid",  intercept = 1.5, slope = 0.10, cap = 6),
  list(name = "var_high", intercept = 2.0, slope = 0.10, cap = 6),
  list(name = "var_wide", intercept = 2.0, slope = 0.05, cap = 7)
)

save_ttops <- function(ttops, fname) {
  df <- data.frame(
    treeID   = ttops$treeID,
    x        = st_coordinates(ttops)[, "X"],
    y        = st_coordinates(ttops)[, "Y"],
    height_m = st_coordinates(ttops)[, "Z"]
  )
  write.csv(df, fname, row.names = FALSE)
  cat("wrote", fname, "-", nrow(df), "trees\n")
}

for (k in kernel_sizes) {
  cat("=== kernel", k, "x", k, "===\n")
  kernel <- matrix(1, k, k)
  schm <- terra::focal(x = chm, w = kernel, fun = median, na.rm = TRUE)

  for (ws in fixed_ws_values) {
    ttops <- locate_trees(las = schm, algorithm = lmf(ws = ws))
    fname <- sprintf("%s/tree_heights_k%d_fixed%.1f.csv", out_dir, k, ws)
    save_ttops(ttops, fname)
  }

  for (vc in variable_configs) {
    intercept <- vc$intercept
    slope <- vc$slope
    cap <- vc$cap
    wsfun <- local({
      intercept <- intercept; slope <- slope; cap <- cap
      function(x) {
        y <- intercept + slope * x
        y[x < 2] <- intercept
        y[y > cap] <- cap
        return(y)
      }
    })
    ttops <- locate_trees(las = schm, algorithm = lmf(ws = wsfun))
    fname <- sprintf("%s/tree_heights_k%d_%s.csv", out_dir, k, vc$name)
    save_ttops(ttops, fname)
  }
}

cat("Sweep complete.\n")
