# How to Process LAS Data:
1. Extract LAS steps from GSL
2. Bring LAS file into CloudCompare to perform Ground Classification using CSF (Cloth Simulation Filter)
      ###### Cloth Simulation Filter (CSF) is a tool to extract of ground points in discrete return LiDAR pointclouds. The detailed theory and algorithms could be found in the following paper: Zhang W, Qi J, Wan P, Wang H, Xie D, Wang X, Yan G. An Easy-to-Use Airborne LiDAR Data Filtering Method Based on Cloth Simulation. Remote Sensing. 2016; 8(6):501.
3. Recommended Settings for CSF:
   * Cloth Resolutin: 0.5m
   * Max iterations: 500
   * Classification Threshold: 0.5
4. Save and Export Ground Points
5. Open Ground Points and original LAS file in ArcGIS
#### The following steps are further Outlined in the LiDAR Workflow File
7. Create LAS Dataset for each file
8. Extract LAS Dataset to crop dataset to smaller region
9. For the Ground Points file: LAS Dataset to Raster
