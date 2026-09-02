import subprocess

pcap_path = r"D:\OusterData\test120260829_1325_19_OS-0-128_122619004070.pcap"
meta_path = r"D:\OusterData\test120260829_1325_19_OS-0-128_122619004070.json"
out_path  = r"D:\OusterData\0_output_slam.las"
ouster_cli = r"C:\Users\kdavis99\AppData\Roaming\Python\Python313\Scripts\ouster-cli.exe"

cmd = [
    ouster_cli,
    "source",
    "-m", meta_path,
    pcap_path,
    "slam",
    "--voxel-size", "1.0",
    "--deskew-method", "imu_deskew",
    "save", out_path
]

print("Running SLAM pipeline...")
result = subprocess.run(cmd, capture_output=False)

if result.returncode == 0:
    print(f"Done — saved to {out_path}")
else:
    print(f"Something went wrong — return code {result.returncode}")