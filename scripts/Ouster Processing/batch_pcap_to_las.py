import subprocess
from pathlib import Path

folder = Path(r"D:\OusterData\Arboretum\Raw_Arb_Files_10_27_2026")
ouster_cli = r"C:\Users\kdavis99\AppData\Roaming\Python\Python313\Scripts\ouster-cli.exe"
min_range = "1.25m"   # clips returns closer than this to the sensor

failed = []
for pcap in sorted(folder.glob("*.pcap")):
    meta = pcap.with_suffix(".json")
    out = folder / f"125cm_min_range_{pcap.stem}.las"

    if not meta.exists():
        print(f"SKIP (no json): {pcap.name}")
        continue
    if out.exists():
        print(f"SKIP (already done): {out.name}")
        continue

    cmd = [
        ouster_cli, "source", "-m", str(meta), str(pcap),
        "clip", "RANGE", f"{min_range}:",
        "slam", "--voxel-size", "0.25", "--deskew-method", "imu_deskew",
        "save", str(out),
    ]
    print(f"Running SLAM on {pcap.name} ...")
    result = subprocess.run(cmd)
    if result.returncode == 0:
        print(f"Done: {out.name}")
    else:
        print(f"FAILED ({result.returncode}): {pcap.name}")
        failed.append(pcap.name)

print("\nFinished. Failed files:", failed if failed else "none")