# Ouster Processing Key Considerations:
* Ouster OS0 is NOT inherently georeferenced. It provides LiDAR and a low-grade IMU only. Without GNSS/INS, data is in a local SLAM coordinate frame (relative, not global).
* To make data processing / comparison / or combination easier between platforms, it may be beneficial to acquire external GNSS/IMU for the Ouster
  * One such example product is the APX-15 (single GNSS antenna, $6-12,000) or APX-18 (dual GNSS antennas, designed for LiDAR payloads, $12-20,000) which the drone set-up Dr. Marc has uses
  * Or the SBG Ellipse-D, $3k–6k, RTK + dual antenna heading, accuracy: 1–3 cm position
## Combining Ouster + YellowScan (With GNSS/INS)
1. Process YellowScan in POSPac (SmartBase/RTX)
 2. Process Ouster with GNSS/INS trajectory (e.g., APX-18)
 3. Export both as georeferenced LAS
 4. CloudCompare:
    - Initial alignment (same CRS)
    - ICP refinement on overlap
 5. Validate alignment (check stem offsets)
 
Key references:
 - Glennie et al. 2013 (LiDAR boresight calibration)
 - Wallace et al. 2016 (Forestry LiDAR accuracy)
 - Bienert et al. 2018 (QSM + TLS accuracy)
## Ouster-Only Workflow (No GNSS)
1. Run SLAM (KissICP / LOAM / LIO-SAM)
 2. Export merged point cloud
 3. CloudCompare:
    - Noise filtering
    - Ground removal (CSF)
    - Segment trees
 4. Export trees
 5. R (TreeQSM):
    - Fit cylinders
    - Compute volume
 6. rTwig:
    - Correct overestimation
 7. Biomass:
    - Apply allometric equations
 
Notes:
 - Best for small plots
 - Drift increases with path length
 
## R Scripts for Tree Volume (TreeQSM + rTwig)
Install packages:
install.packages(c('lidR','rTwig'))
  TreeQSM is typically installed separately from source
Load libraries:
library(lidR)
 library(rTwig)
Load point cloud:
las <- readLAS('tree.las')
 plot(las)
Preprocess:
las <- lasfilter(las, Z > 0)
 las <- lasnoise(las)
Run TreeQSM (conceptual call):
 qsm <- treeqsm(las)
  volume <- sum(qsm$cylinders$volume)
Apply rTwig correction:
 corrected <- correct_qsm(qsm)
  corrected_volume <- sum(corrected$cylinders$volume)
Biomass estimation:
 biomass <- corrected_volume * wood_density
  print(biomass)
## Fully Working TreeQSM + rTwig Script
Install TreeQSM from GitHub:
install.packages('devtools')
 devtools::install_github('InverseTampere/TreeQSM')
Load libraries:
library(lidR)
 library(rTwig)
 library(TreeQSM)
Load LAS file:
las <- readLAS('tree.las')
 if (is.empty(las)) stop('LAS file is empty')
Preprocess point cloud:
las <- lasfilter(las, Z > 0)
 las <- lasnormalize(las, knnidw())
Convert to matrix for TreeQSM:
pts <- as.matrix(las@data[, c('X','Y','Z')])
Run TreeQSM:
qsm <- treeqsm(pts,
   patchdiam1 = 0.05,
   patchdiam2 = 0.02,
   lcyl = 3,
   FilRad = 3
 )
Extract volume:
volume <- sum(qsm$cylinder$Volume)
 print(volume)
Apply rTwig correction:
corrected <- correct_qsm(qsm)
 corrected_volume <- sum(corrected$cylinder$Volume)
 print(corrected_volume)
Estimate biomass:
wood_density <- 600  # kg/m3 (example)
 biomass <- corrected_volume * wood_density
 print(biomass)
## Parameter Tuning for Ouster OS0 (Recommended)
OS0 typically has lower density and more noise than TLS. Use slightly larger patches and stronger filtering.
Recommended TreeQSM parameters for OS0:
qsm <- treeqsm(pts,
   patchdiam1 = 0.08,   # larger initial patch
   patchdiam2 = 0.03,   # finer secondary patch
   lcyl = 4,            # smoother cylinders
   FilRad = 4           # stronger filtering
 )
Additional preprocessing tips:
- Downsample to uniform density (voxel ~1–2 cm)
 - Remove isolated points (statistical outlier removal)
 - Ensure good stem coverage (walk around trees)
Why this matters:
- Larger patches reduce noise sensitivity
 - Higher filtering prevents overfitting branches
 - Improves volume stability for QSM
 
## QSM Diagnostic Checklist (Quality Control)
Use this to verify your TreeQSM output is reliable:
- Stem straightness: main trunk should be continuous, not zig-zag
 - Cylinder overlap: minimal gaps or floating segments
 - Radius realism: no sudden spikes in diameter
 - Branch sanity: small branches not over-thickened
 - Volume stability: rerun with slight parameter changes → similar volume
 - Visual check: overlay cylinders on point cloud (CloudCompare)
Common failure signs:
- Inflated volume → too much noise / poor filtering
 - Broken stem → insufficient point coverage
 - Excess branches → overfitting (patch size too small)
Quick fixes:
- Increase patchdiam1/2
 - Increase FilRad
 - Improve preprocessing (denoise, downsample)
