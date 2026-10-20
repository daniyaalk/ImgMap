# ImgMap

Georeference aeronautical charts (approach plates, STARs, SIDs, VFR charts) and
use them as a GPS moving map. Built with Flutter for Android, iOS, macOS,
Windows, Linux and the web.

**Not for navigation.** Positions are only as good as the control points you
enter and your device's GPS.

## How it works

1. Add an airport by ICAO code.
2. Add a chart image (photo, screenshot or scan) for it.
3. Zoom in and tap points on the chart whose coordinates you know, such as
   fixes, VORs or runway thresholds, then type their coordinates. Most chart
   notations are accepted: `N28°34.12'`, `283407N`, `28 34 07 N`, `28.5687`.
4. Open the chart. Your position and track are drawn on it.

Two points are enough to fix scale and rotation. With three or more, the app
fits a full affine transform, which also corrects skewed or unevenly scaled
scans, and shows the error at each point so a mistyped coordinate stands out.

## Charts from the AIP

For Indian airports (ICAO codes starting VA, VE, VI or VO), the app can
fetch charts straight from AIP India (aim-india.aai.aero). Add the airport
and the chart list opens. The edition in force is chosen by AIRAC date, and
the next one can be picked once it's published. Imported charts are tagged
with their edition, and importing a newer edition replaces them.

Each chart is rendered from its PDF and georeferenced automatically where
possible:

- **Grid labels** (e.g. `28°50'0"N` on the frame). The labels are fitted
  in both Mercator and UTM, and the projection that explains them best is
  kept. Stray labels are dropped, every label must be predicted by the
  others, and the result is checked against the chart's printed scale. On
  AAI's ILS and STAR charts this gives about ±15 m.
- **One meridian and one parallel plus the scale bar**, as most AAI SIDs
  and many STARs have. Position and rotation come from the grid lines, and
  scale from the bar, which must match the printed `1:N`. This can't check
  itself, so the app shows an estimated accuracy (about 1% of the distance
  across the chart).
- **Named fixes.** Waypoint and navaid names on the chart are matched to
  coordinates published in the eAIP (ENR 4.4 significant points, ENR 4.1
  navaids, the aerodrome's AD 2 page). Each label is paired with its symbol,
  read from the PDF's vector shapes. A consensus search (RANSAC) throws out
  wrong matches, and fixes displaced behind NOT TO SCALE breaks. Each fix
  is then looked for where its published position predicts, and the chart
  is fitted as a conformal (scale and rotation only) map in UTM. Fixes
  confirm a full grid, and the chart is refused if they disagree. They
  replace a one-line grid estimate, or georeference a chart with no grid.
  On AAI's SIDs and STARs this gives about ±5–25 m.
- **Parts marked NOT TO SCALE**, such as a shortened leg behind a break
  symbol or an enlarged inset, are allowed when the frame has a full
  coordinate grid. The marked places are outlined on the moving map, with a
  warning that fixes there aren't at their true positions. With only one
  grid line each way, a chart with such marks is refused.
- Anything else (charts with no grid, charts whose text was turned into
  outlines, tables and coding pages) isn't imported. Charts that fail are remembered for that edition and hidden from
  the AIP list, so only charts that work as a moving map are offered.

Always open an automatically georeferenced chart and check that its markers
sit on the grid lines before relying on it.

### Countries

Each country is one `EaipCountry` entry in `lib/src/aip/countries/`, listed
in `lib/src/aip/aip_countries.dart`. An entry holds:

- the country's name, ISO code and publishing authority;
- its ICAO prefixes (`VA`, `VE`, `VI`, `VO`), which decide which airports'
  charts come from it;
- where editions are announced, and how to read their effective dates;
- its eAIP page naming (`IN-` prefix, `en-GB`) and chart file conventions.

For a Eurocontrol-style eAIP, nothing else needs code. The en-route map
asks which country to show (once, then remembers), and can be switched
from the map. Each country's network is cached separately. AIP
fetching isn't available in the web build, because AIP sites don't allow
cross-origin requests.

## En-route map

The route button on the airports screen opens an airway map for the chosen
country, built directly from its AIP route tables (ENR 3.x), with no chart download or
georeferencing. For India that's 525 routes, 931 points and 2,161 segments.
The first download takes about a minute; after that it's cached (about
300 KB) and works offline.

- Routes are coloured by type (conventional or RNAV). Navaids, compulsory
  and on-request points have their own symbols, and labels thin out as you
  zoom out.
- Tap a segment for its track, distance, levels, MOCA, class and width, or
  a point for the routes through it. Search finds fixes, navaids and
  routes.
- Your position is shown with follow mode. The plane button simulates a
  flight along a route.
- **Self-checking.** Every segment's published length and track is
  compared with its coordinates; mismatches are drawn dashed red and
  explained when tapped. Amended text (the old value in `<del>`) is
  ignored, so an amended position is never mixed with its predecessor.
- When a newer AIRAC edition comes into force, the map says so and offers
  an update.

## Trying it without a phone

Run the web build and choose **Try the demo**, then **⋮ → Add demo chart**.
The demo chart is fictional and deliberately rotated. Each fix has its
coordinates printed next to it, so you can georeference the chart yourself.
On the map screen, the ✈ button flies a simulated aircraft around the chart.

```sh
flutter run -d chrome          # or: flutter build web && serve build/web
```

In the browser, charts are kept in memory only and are lost on reload.

## Development

```sh
flutter test       # geo math, coordinate parsing, storage, full UI flow
flutter analyze
```

Two opt-in tests use real AIP charts. These aren't stored in the repo,
because they're copyrighted. `libpdfium.so` for the host comes from
[pdfium-binaries](https://github.com/bblanchon/pdfium-binaries) (the
release pdfrx uses).

```sh
# Auto-georeference a folder of chart PDFs and print the results
IMGMAP_CHART_DIR=~/charts IMGMAP_PDFIUM=~/pdfium/lib/libpdfium.so \
  flutter test test/real_charts_test.dart
# Import a few charts for an airport from the live site
IMGMAP_LIVE=VIDP IMGMAP_PDFIUM=~/pdfium/lib/libpdfium.so \
  flutter test test/live_import_test.dart
```

| Path | What |
|---|---|
| `lib/src/aip/` | AIP sources (India), chart listing, download and import |
| `lib/src/pdf/` | PDF rendering and text extraction |
| `lib/src/georef/` | Automatic georeferencing from grid labels and scale bars |
| `lib/src/geo/` | Projections (Mercator, UTM), control-point fitting, coordinates |
| `lib/src/data/` | Chart library; file storage on native, memory on web |
| `lib/src/location/` | GPS permission/stream handling and the flight simulator |
| `lib/src/ui/` | Screens and the shared zoomable chart viewport |
| `tool/make_demo_chart.py` | Regenerates `assets/demo_chart.png` |

The original 2019 native Android (Java) version is in the git history before
the Flutter rewrite.

## Screenshots (original Android version)

STAR into Delhi Int'l Airport (VIDP):

![Screenshot 1](screenshots/Screenshot_20190526-185133_ImgMap.jpg)
![Screenshot 2](screenshots/Screenshot_20190526-185442_ImgMap.jpg)
![Screenshot 3](screenshots/Screenshot_20190526-185833_ImgMap.jpg)
![Screenshot 4](screenshots/Screenshot_20190721-191506_ImgMap.jpg)
![Screenshot 5](screenshots/Screenshot_20190721-191636_ImgMap.jpg)
![Screenshot 6](screenshots/Screenshot_20190721-192221_ImgMap.jpg)
