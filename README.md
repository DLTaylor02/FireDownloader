# FireDownloader

FireDownloader finds wildfires from the NIFC Wildfire API, downloads their geometry, and compiles that geometry into a `.kmz` file for use with applications such as Google Earth.

It also maintains a local cache of ZIP code coordinates and automatically refreshes the cache every 90 days.

## Getting Started

1. Open PowerShell and execute:

```powershell
.\Find_Fire.ps1
```

2. The interactive tool will guide you through searching for fires and downloading their perimeters.
   Downloaded `.kmz` files are placed in the `Output` folder.

3. Go to Google Earth. https://earth.google.com/web

4. Click File > Open local KML file

5. Navigate to your file.

## Features

- Search for fires by name
- Browse current NIFC fire perimeters
- Search for fires within a radius of a ZIP code
- Download individual fire perimeters as `.kmz`
- Download all current fire perimeters returned by a ZIP/radius search
- Optional historical perimeter support
- Automatic ZIP code database caching
- Automatic ZIP database refresh every 90 days

## Folder Structure

    FireDownloader\
    │
    ├── Find-Fire.ps1              ← Launcher
    │
    ├── Bin\
    │   ├── WildfireTool.ps1       ← Main application/menu
    │   ├── NifcFunctions.ps1      ← NIFC API/fire functions
    │   ├── ZipFunctions.ps1       ← ZIP database functions
    │   ├── Get-FireKML.ps1        ← KMZ generator
    │   └── Update-ZipDatabase.ps1 ← ZIP database updater
    │
    ├── Data\                      ← Cache and reference data
    │   └── zipcodes.csv           ← ZIP code coordinate database
    │
    └── Output\                    ← Directory of downloaded `.kmz` files
        └── *.kmz                  ← Discrete `.kmz` files

## Data Sources

### NIFC / WFIGS

Fire perimeter data is provided by the **National Interagency Fire Center (NIFC)** through the Wildland Fire Interagency Geospatial Services (WFIGS) ArcGIS services.

The tool uses the current interagency fire perimeter service to search for fires and retrieve their latest available perimeter geometry.

- NIFC Wildland Fire Open Data
  https://data-nifc.opendata.arcgis.com/

- WFIGS Current Interagency Fire Perimeters
  https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/services/WFIGS_Interagency_Perimeters_Current/FeatureServer/0

- WFIGS Interagency Perimeters
  https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/services/WFIGS_Interagency_Perimeters/FeatureServer/0

### U.S. Census Bureau

ZIP code coordinate data is derived from the **U.S. Census Bureau's ZIP Code Tabulation Area (ZCTA) Gazetteer**.

The tool downloads the national ZCTA dataset and maintains a local `zipcodes.csv` cache. The cache is automatically refreshed every 90 days.

- U.S. Census Bureau Geography
  https://www.census.gov/geographies/reference-files.html

- 2025 ZCTA Gazetteer
  https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2025_Gazetteer/
