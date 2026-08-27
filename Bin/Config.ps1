# Config.ps1
#
# Central configuration for FireDownloader.

# ------------------------------------------------------------
# NIFC services
# ------------------------------------------------------------

$currentServiceUrl = "https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/services/WFIGS_Interagency_Perimeters_Current/FeatureServer/0/query"

$historicalServiceUrl = "https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/services/WFIGS_Interagency_Perimeters/FeatureServer/0/query"


# ------------------------------------------------------------
# Application paths
# ------------------------------------------------------------

$toolRoot = Split-Path $PSScriptRoot -Parent

$binDirectory = $PSScriptRoot

$dataDirectory = Join-Path $toolRoot "Data"

$outputDirectory = Join-Path $toolRoot "Output"

$downloader = Join-Path $binDirectory "Get-FireKML.ps1"

$zipDatabase = Join-Path $dataDirectory "zipcodes.csv"


# ------------------------------------------------------------
# ZIP database
# ------------------------------------------------------------

$zipDatabaseMaxAgeDays = 90


# ------------------------------------------------------------
# Census ZIP database
# ------------------------------------------------------------

$zipDatabaseMaxAgeDays = 90

$zipDatabaseDownloadUrl = "https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2025_Gazetteer/2025_Gaz_zcta_national.zip"


# ------------------------------------------------------------
# Feature flags
# ------------------------------------------------------------

# Enable historical perimeter selection.
#
# $true  = allow current/historical perimeter selection
# $false = always use the most recent perimeter
$makeHistoryAvailable = $false


# ------------------------------------------------------------
# NIFC query fields
# ------------------------------------------------------------

$outFields = @(
    "OBJECTID",
    "poly_IncidentName",
    "poly_GISAcres",
    "attr_PercentContained",
    "poly_PolygonDateTime",
    "poly_MapMethod",
    "poly_Source",
    "attr_UniqueFireIdentifier",
    "poly_IRWINID",
    "attr_POOState"
) -join ","