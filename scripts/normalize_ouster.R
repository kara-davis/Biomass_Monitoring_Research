library(lidR)
las <- readLAS("D:\\OusterData\\Bartleson\\Raw_Bartleson_Files_10_13_2026\\Registered - Post ICP\\O1_registered_20261013.las")
las <- classify_ground(las, csf(sloop_smooth = TRUE), last_returns = FALSE)
writeLAS(normalize_height(las, tin()), "D:\\OusterData\\Bartleson\\Raw_Bartleson_Files_10_13_2026\\Registered - Post ICP\\O1_normalized.las")