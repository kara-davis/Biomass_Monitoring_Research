import subprocess

pcap_path = r"D:\OusterData\Tomorro BDA\2026114_1252_06.pcap"
meta_path = r"D:\OusterData\Tomorro BDA\2026114_1252_06.json"
out_path  = r"D:\OusterData\Tomorro BDA\Tomorro_2026_11_4_06.las"
ouster_cli = r"C:\Users\kdavis99\AppData\Roaming\Python\Python313\Scripts\ouster-cli.exe"

cmd = [
    ouster_cli,
    "source",
    "-m", meta_path,
    pcap_path,
    "clip", "RANGE", "1.25m:", # clips the collection of point cloud data to start at 1.25m beyond the sensor and not any closer
    "slam",
    "--voxel-size", "0.1", #voxel size initially set to 25cm =, could be too coarse
    "--deskew-method", "imu_deskew",
    "save", out_path
]

print("Running SLAM pipeline...")
result = subprocess.run(cmd, capture_output=False)

if result.returncode == 0:
    print(f"Done — saved to {out_path}")
else:
    print(f"Something went wrong — return code {result.returncode}")