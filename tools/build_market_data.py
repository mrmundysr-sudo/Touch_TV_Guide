#!/usr/bin/env python3
"""Regenerates app/src/main/assets/markets.csv and zips.csv.

Inputs (not committed):
  --readme   EPGTalk README.md (its "US Local Coverage" section lists the markets, e.g. "Abilene TX")
  --zips     US zip JSON (github.com/millbj92/US-Zip-Codes-JSON, MIT; Census-derived zip centroids)
Market position = mean centroid of the zip codes of the market's city. Zip -> market is "nearest market"
(a heuristic, NOT the Nielsen DMA); the app tells the user so and lets them pick another market.
"""
import argparse, collections, json, re

ap = argparse.ArgumentParser()
ap.add_argument('--readme', required=True); ap.add_argument('--zips', required=True)
ap.add_argument('--out', default='app/src/main/assets')
a = ap.parse_args()

readme = open(a.readme, encoding='utf8').read()
sec = readme.split('US Local Coverage')[1].split('</details>')[0]
markets = re.findall(r"📡 ([A-Za-z.' ]+?) ([A-Z]{2})\s*(?=\||$)", sec, re.M)
def num(v):
    try: return float(v)
    except (TypeError, ValueError): return None
zs = []
for z in json.load(open(a.zips)):
    la, lo = num(z.get('latitude')), num(z.get('longitude'))
    if la and lo and z.get('zip_code') is not None:
        zs.append({'zip_code': int(z['zip_code']), 'latitude': la, 'longitude': lo, 'city': z['city'], 'state': z['state']})
cities = collections.defaultdict(list)
for z in zs:
    cities[(z['city'].lower().replace('saint ', 'st. '), z['state'])].append(z)
FALLBACK = {('Hawaii', 'HI'): ('Honolulu', 'HI'), ('Rhode Island', 'RI'): ('Providence', 'RI')}
rows = []
for name, st in markets:
    key = FALLBACK.get((name, st), (name, st))
    pts = cities.get((key[0].lower(), key[1]))
    if not pts:
        print('no coordinates for', name, st); continue
    lat = sum(p['latitude'] for p in pts) / len(pts); lon = sum(p['longitude'] for p in pts) / len(pts)
    mid = re.sub(r'[^a-z0-9]+', '-', f'{name}-{st}'.lower()).strip('-')
    rows.append((mid, name, st, round(lat, 4), round(lon, 4)))
with open(f'{a.out}/markets.csv', 'w', encoding='utf8') as f:
    f.write('id,name,state,lat,lon\n')
    for r in sorted(rows, key=lambda r: r[1]): f.write(','.join(map(str, r)) + '\n')
n = 0
with open(f'{a.out}/zips.csv', 'w', encoding='utf8') as f:
    f.write('zip,lat,lon\n')
    for z in zs:
        f.write(f"{z['zip_code']:05d},{z['latitude']:.3f},{z['longitude']:.3f}\n"); n += 1
print(len(rows), 'markets,', n, 'zips')
