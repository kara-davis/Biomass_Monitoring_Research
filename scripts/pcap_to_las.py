import subprocess

pcap_path = r"D:\OusterData\Bartleson\Raw_Bartleson_Files_9_22_2026\bart_high_0cmrange_straight20260922_0957_17.pcap"
meta_path = r"D:\OusterData\Bartleson\Raw_Bartleson_Files_9_22_2026\bart_high_0cmrange_straight20260922_0957_17.json"
out_path  = r"D:\OusterData\Bartleson\Raw_Bartleson_Files_9_22_2026\125cm_min_range_bart_high_0cmrange_straight20260922_0957_17.las"
ouster_cli = r"C:\Users\kdavis99\AppData\Roaming\Python\Python313\Scripts\ouster-cli.exe"

cmd = [
    ouster_cli,
    "source",
    "-m", meta_path,
    pcap_path,
    "clip", "RANGE", "1.5m:", # clips the collection of point cloud data to start at 1.25m beyond the sensor and not any closer
    "slam",
    "--voxel-size", "0.25",
    "--deskew-method", "imu_deskew",
    "save", out_path
]

print("Running SLAM pipeline...")
result = subprocess.run(cmd, capture_output=False)

if result.returncode == 0:
    print(f"Done — saved to {out_path}")
else:
    print(f"Something went wrong — return code {result.returncode}")