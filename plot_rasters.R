# ── plot_rasters.R ────────────────────────────────────────────────────────────
# Publication-ready figures comparing DSM, DTM, and CHM GeoTIFFs
#
# Required packages (run once):
#   install.packages(c("terra", "ggplot2", "tidyterra", "patchwork", "scales"))
# ─────────────────────────────────────────────────────────────────────────────

library(terra)
library(ggplot2)
library(tidyterra)
library(patchwork)
library(scales)

base_path <- "C:/Users/kdavis99/OneDrive - Cal Poly/Tree Biomass Estimation Research - Documents/GitHub_Repository"


# Clip all rasters to arboretum boundary
boundary <- vect(file.path(base_path, "boundary.shp"))

for (f in c("ogdsm1.tif", "dsm1.tif", "dsm04.tif",
            "ogdtm1.tif", "dtm1.tif", "dtm04.tif")) {
  r <- rast(file.path(base_path, f))
  b <- project(boundary, crs(r))
  r <- mask(crop(r, b), b)
  writeRaster(r, file.path(base_path, f), overwrite = TRUE, NAflag = -9999)
  cat(sprintf("Clipped %s\n", f))
}
output_dpi <- 300

# ── Colour palettes ───────────────────────────────────────────────────────────
chm_colours <- c("#1a6b1a", "#4aab1a", "#a8d400", "#ffff00", "#ffaa00", "#ff5500", "#cc0000")
dsm_colours <- c("#2166ac", "#4dac26", "#b8e186", "#f7f7f7", "#f1b6da", "#d01c8b", "#7b3294")
dtm_colours <- c("#543005", "#8c510a", "#bf812d", "#dfc27d", "#f6e8c3", "#c7eae5", "#35978f")

# ── Read & clean ──────────────────────────────────────────────────────────────
read_and_clean <- function(path) {
  r <- rast(path)
  cat(sprintf("\nFile: %s\n", basename(path)))
  cat(sprintf("  NoData : %s  |  range: %.3f – %.3f\n",
              NAflag(r),
              global(r, "min", na.rm = FALSE)[[1]],
              global(r, "max", na.rm = FALSE)[[1]]))
  r[r < -100] <- NA
  r[r == 0]   <- NA
  r
}

# ── Build one panel ───────────────────────────────────────────────────────────
bg_col    <- "white"
text_col  <- "black"
subtle    <- "#555555"
spine_col <- "#aaaaaa"

base_theme <- theme_minimal(base_size = 10) +
  theme(
    plot.background   = element_rect(fill = bg_col, colour = NA),
    panel.background  = element_rect(fill = bg_col, colour = NA),
    panel.grid        = element_blank(),
    panel.border      = element_rect(colour = spine_col, fill = NA, linewidth = 0.5),
    axis.text         = element_text(colour = subtle, size = 6, family = "mono"),
    axis.ticks        = element_line(colour = spine_col, linewidth = 0.3),
    axis.title        = element_blank(),
    plot.title        = element_text(colour = text_col, size = 10, face = "bold",
                                     hjust = 0.5, margin = margin(b = 5)),
    plot.tag          = element_text(colour = text_col, size = 12, face = "bold"),
    legend.position   = "bottom",
    legend.direction  = "horizontal",
    legend.background = element_rect(fill = bg_col, colour = NA),
    legend.key.height = unit(0.4, "cm"),
    legend.key.width  = unit(2.0, "cm"),
    legend.title      = element_text(colour = subtle, size = 8),
    legend.text       = element_text(colour = subtle, size = 7),
    plot.margin       = margin(6, 8, 6, 8)
  )

make_panel <- function(r, label, tag_letter, palette, vmin, vmax) {
  max_cells <- 1200 * 1200
  if (ncell(r) > max_cells) {
    fact <- ceiling(sqrt(ncell(r) / max_cells))
    r <- aggregate(r, fact = fact, fun = "mean", na.rm = TRUE)
  }
  ggplot() +
    geom_spatraster(data = r) +
    scale_fill_gradientn(
      colours  = palette,
      limits   = c(vmin, vmax),
      na.value = "white",
      name     = "Elevation (m)",
      labels   = label_number(accuracy = 1)
    ) +
    labs(title = label, tag = tag_letter) +
    guides(fill = guide_colorbar(title.position = "top", title.hjust = 0.5,
                                  ticks = TRUE, ticks.colour = subtle,
                                  frame.colour = spine_col)) +
    base_theme
}

# ── Generic function to build & save a 3-panel comparison ────────────────────
make_comparison <- function(file_arc, file_r1, file_r04,
                             label_arc, label_r1, label_r04,
                             figure_title, palette,
                             out_combined, out_a, out_b, out_c,
                             legend_title = "Elevation (m)") {

  cat(sprintf("\n\n══ %s ══\n", figure_title))
  rasts <- lapply(c(file_arc, file_r1, file_r04), read_and_clean)

  vmin <- min(sapply(rasts, function(r) global(r, "min", na.rm = TRUE)[[1]]))
  vmax <- max(sapply(rasts, function(r) global(r, "max", na.rm = TRUE)[[1]]))
  cat(sprintf("Shared scale: %.1f – %.1f m\n", vmin, vmax))

  panels <- mapply(make_panel,
                   r          = rasts,
                   label      = c(label_arc, label_r1, label_r04),
                   tag_letter = c("A", "B", "C"),
                   MoreArgs   = list(palette = palette, vmin = vmin, vmax = vmax),
                   SIMPLIFY   = FALSE)

  for (i in 1:3) {
    fname <- c(out_a, out_b, out_c)[i]
    ggsave(fname, plot = panels[[i]], width = 6, height = 6, dpi = output_dpi, bg = bg_col)
    cat(sprintf("✓  Panel %s → %s\n", LETTERS[i], normalizePath(fname, mustWork = FALSE)))
  }

  combined <- (panels[[1]] | panels[[2]] | panels[[3]]) +
    plot_annotation(
      title   = figure_title,
      caption = paste(basename(c(file_arc, file_r1, file_r04)), collapse = "  |  "),
      theme   = theme(
        plot.background = element_rect(fill = bg_col, colour = NA),
        plot.title      = element_text(colour = text_col, size = 14, face = "bold",
                                       hjust = 0.5, margin = margin(t = 8, b = 6)),
        plot.caption    = element_text(colour = "#999999", size = 5.5,
                                       hjust = 0.5, margin = margin(t = 4, b = 4))
      )
    )

  ggsave(out_combined, plot = combined, width = 16, height = 6, dpi = output_dpi, bg = bg_col)
  cat(sprintf("✓  Combined → %s\n", normalizePath(out_combined, mustWork = FALSE))) # nolint: line_length_linter.
}

# ── DSM comparison ────────────────────────────────────────────────────────────
make_comparison(
  file_arc  = file.path(base_path, "ogdsm1.tif"),
  file_r1   = file.path(base_path, "dsm1.tif"),
  file_r04  = file.path(base_path, "dsm04.tif"),
  label_arc = "ArcGIS DSM",
  label_r1  = "R Developed DSM (1m)",
  label_r04 = "R Developed DSM (0.4m)",
  figure_title = "Digital Surface Model Comparison",
  palette      = dsm_colours,
  out_combined = "DSM_comparison_figure.png",
  out_a = "DSM_panel_A.png", out_b = "DSM_panel_B.png", out_c = "DSM_panel_C.png"
)

# ── DTM comparison ────────────────────────────────────────────────────────────
make_comparison(
  file_arc  = file.path(base_path, "ogdtm1.tif"),
  file_r1   = file.path(base_path, "dtm1.tif"),
  file_r04  = file.path(base_path, "dtm04.tif"),
  label_arc = "ArcGIS DTM",
  label_r1  = "R Developed DTM (1m)",
  label_r04 = "R Developed DTM (0.4m)",
  figure_title = "Digital Terrain Model Comparison",
  palette      = dtm_colours,
  out_combined = "DTM_comparison_figure.png",
  out_a = "DTM_panel_A.png", out_b = "DTM_panel_B.png", out_c = "DTM_panel_C.png"
)

# ── CHM comparison ────────────────────────────────────────────────────────────
make_comparison(
  file_arc  = file.path(base_path, "ogchm1.tif"),
  file_r1   = file.path(base_path, "chm1.tif"),
  file_r04  = file.path(base_path, "chm04.tif"),
  label_arc = "ArcGIS CHM",
  label_r1  = "R Developed CHM (1m)",
  label_r04 = "R Developed CHM (0.4m)",
  figure_title = "Canopy Height Model Comparison",
  palette      = chm_colours,
  out_combined = "CHM_comparison_figure.png",
  out_a = "CHM_panel_A.png", out_b = "CHM_panel_B.png", out_c = "CHM_panel_C.png"
)

cat("\n\nAll done!\n")
