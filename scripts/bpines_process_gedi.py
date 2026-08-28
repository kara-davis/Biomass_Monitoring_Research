import h5py
import numpy as np
import pandas as pd
import geopandas as gpd
from shapely.geometry import Point
import os
import datetime

# ── Configuration ────────────────────────────────────────────────────────────
data_folder = r'C:\Users\davisk10\OneDrive - Cal Poly\Tree Biomass Estimation Research - Documents\CODE\BPINES CODE'

LAT_MIN, LAT_MAX = 35.2370862829615774, 35.2565592752942294
LON_MIN, LON_MAX = -120.8913353741043437, -120.8617454851847839

csv_path     = os.path.join(data_folder, 'gedi_bpines_shots.csv')
geojson_path = os.path.join(data_folder, 'gedi_bpines_shots.geojson')

# ── Load existing data if it exists ──────────────────────────────────────────
if os.path.exists(csv_path):
    existing = pd.read_csv(csv_path)
    existing_shots = set(existing['shot_number'].astype(str))
    print(f'Loaded {len(existing)} existing shots from CSV')
else:
    existing = pd.DataFrame()
    existing_shots = set()
    print('No existing CSV found — starting fresh')

# ── Process each .h5 file ────────────────────────────────────────────────────
all_shots = []

h5_files = [f for f in os.listdir(data_folder) if f.endswith('.h5')]
print(f'Found {len(h5_files)} .h5 files to process')

for filename in h5_files:
    filepath = os.path.join(data_folder, filename)
    print(f'Processing: {filename}')

    try:
        with h5py.File(filepath, 'r') as f:
            beams = [k for k in f.keys() if k.startswith('BEAM')]

            for beam in beams:
                try:
                    lat = f[beam]['lat_lowestmode'][:]
                    lon = f[beam]['lon_lowestmode'][:]

                    mask = (
                        (lat >= LAT_MIN) & (lat <= LAT_MAX) &
                        (lon >= LON_MIN) & (lon <= LON_MAX)
                    )

                    if mask.sum() == 0:
                        continue

                    print(f'  {beam}: {mask.sum()} shots in bpines')

                    rh = f[beam]['rh'][mask]

                    # Date from filename
                    try:
                        year = int(filename[9:13])
                        doy  = int(filename[13:16])
                        date = datetime.datetime(year, 1, 1) + datetime.timedelta(doy - 1)
                        date_str = date.strftime('%Y-%m-%d')
                    except:
                        date_str = 'unknown'

                    shot_numbers = f[beam]['shot_number'][mask].astype(str)

                    # Skip shots already in existing CSV
                    new_mask = [s not in existing_shots for s in shot_numbers]
                    if sum(new_mask) == 0:
                        print(f'  All shots already processed, skipping')
                        continue

                    print(f'  {sum(new_mask)} new shots to add')

                    shot_data = {
                        'filename':     filename,
                        'beam':         beam,
                        'date':         date_str,
                        'lat':          lat[mask][new_mask],
                        'lon':          lon[mask][new_mask],
                        'rh25':         rh[:, 25][new_mask],
                        'rh50':         rh[:, 50][new_mask],
                        'rh75':         rh[:, 75][new_mask],
                        'rh98':         rh[:, 98][new_mask],
                        'sensitivity':  f[beam]['sensitivity'][mask][new_mask],
                        'quality_flag': f[beam]['quality_flag'][mask][new_mask],
                        'degrade_flag': f[beam]['degrade_flag'][mask][new_mask],
                        'shot_number':  shot_numbers[new_mask],
                    }

                    all_shots.append(pd.DataFrame(shot_data))

                except KeyError as e:
                    print(f'  Skipping {beam} — missing field: {e}')
                    continue

    except Exception as e:
        print(f'Error reading {filename}: {e}')
        continue

# ── Combine new + existing shots ─────────────────────────────────────────────
if len(all_shots) == 0:
    print('No new shots found in bpines area')
    combined_quality = existing[
        (existing['quality_flag'] == 1) &
        (existing['degrade_flag'] == 0)
    ] if len(existing) > 0 else pd.DataFrame()
else:
    new_shots = pd.concat(all_shots, ignore_index=True)
    print(f'\nNew shots found: {len(new_shots)}')

    combined = pd.concat([existing, new_shots], ignore_index=True)
    print(f'Total shots (all): {len(combined)}')

    combined_quality = combined[
        (combined['quality_flag'] == 1) &
        (combined['degrade_flag'] == 0)
    ].copy()
    print(f'Total high quality shots: {len(combined_quality)}')

    # Save updated CSV
    combined_quality.to_csv(csv_path, index=False)
    print(f'CSV updated: {csv_path}')
    
    #new to change shot number to string to allow arcpro to read file
    df = pd.read_csv('gedi_bpines_shots.csv', dtype={'shot_number': str})
    df.to_csv('gedi_bpines_shots_fixed.csv', index=False)
    # Save updated GeoJSON
    geometry = [Point(lon, lat) for lon, lat in zip(combined_quality['lon'], combined_quality['lat'])]
    gdf = gpd.GeoDataFrame(combined_quality, geometry=geometry, crs='EPSG:4326')
    gdf.to_file(geojson_path, driver='GeoJSON')
    print(f'GeoJSON updated: {geojson_path}')

print('\nDone! Safe to delete .h5 files and download next batch.')