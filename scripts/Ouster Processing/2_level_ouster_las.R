library(lidR)

f <- "D:\\OusterData\\Bartleson\\Raw_Bartleson_Files_10_13_2026\\125cm_min_range_O10_20261013_1335_03.las"
las <- suppressWarnings(readTLSLAS(f))

xyz <- as.matrix(las@data[, c("X", "Y", "Z")])
ctr <- apply(xyz, 2, median)
p   <- sweep(xyz, 2, ctr)

cross <- function(a, b) c(a[2]*b[3]-a[3]*b[2], a[3]*b[1]-a[1]*b[3], a[1]*b[2]-a[2]*b[1])

# RANSAC ground plane, fit on core points only
core <- p[rowSums(p[, 1:2]^2) < 40^2, ]
set.seed(1)
sub  <- core[sample(nrow(core), min(50000, nrow(core))), ]
best <- 0; n_best <- c(0, 0, 1)
for (i in 1:2000) {
  s <- sub[sample(nrow(sub), 3), ]
  n <- cross(s[2, ] - s[1, ], s[3, ] - s[1, ])
  len <- sqrt(sum(n^2)); if (len == 0) next
  n <- n / len
  inl <- sum(abs(sweep(sub, 2, s[1, ]) %*% n) < 0.05)
  if (inl > best) { best <- inl; n_best <- n }
}
if (n_best[3] < 0) n_best <- -n_best
cat("Tilt (deg):", round(acos(n_best[3]) * 180 / pi, 2), "\n")

# Rotate whole cloud so ground normal = straight up
z <- c(0, 0, 1)
v <- cross(n_best, z); sn <- sqrt(sum(v^2)); cs <- sum(n_best * z)
if (sn > 1e-8) {
  vx <- matrix(c(0, -v[3], v[2],  v[3], 0, -v[1],  -v[2], v[1], 0), 3, byrow = TRUE)
  R  <- diag(3) + vx + vx %*% vx * ((1 - cs) / sn^2)
  q  <- sweep(p %*% t(R), 2, ctr, "+")
  las@data$X <- q[, 1]; las@data$Y <- q[, 2]; las@data$Z <- q[, 3]
  las <- las_update(las)
  las <- las_quantize(las)
}

writeLAS(las, sub("\\.las$", "_leveled.las", f))
