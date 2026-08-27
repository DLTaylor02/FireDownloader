# Update-ZipDatabase.ps1
#
# Downloads the current national Census ZCTA Gazetteer file
# and converts it into the lightweight local ZIP coordinate
# database used by Find-Fire.ps1.
#
# Source:
# U.S. Census Bureau 2025 ZCTA Gazetteer
#
# The resulting CSV contains:
#   ZIP
#   Latitude
#   Longitude
#
# The source data is national and approximately 1 MB compressed.

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$dataDirectory = Join-Path `
    (Split-Path $PSScriptRoot -Parent) `
    "Data"

$outputFile = Join-Path `
    $dataDirectory `
    "zipcodes.csv"

$downloadUrl = "https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2025_Gazetteer/2025_Gaz_zcta_national.zip"

# ------------------------------------------------------------
# Prepare working directory
# ------------------------------------------------------------

if (-not (Test-Path $dataDirectory)) {

    New-Item `
        -ItemType Directory `
        -Path $dataDirectory `
        -Force |
        Out-Null
}

$tempDirectory = Join-Path `
    ([System.IO.Path]::GetTempPath()) `
    "WildfireTools_ZCTA"

$tempZip = Join-Path `
    $tempDirectory `
    "zcta.zip"

$tempExtract = Join-Path `
    $tempDirectory `
    "Extracted"

# Clean up any previous temporary data.
if (Test-Path $tempDirectory) {
    Remove-Item `
        $tempDirectory `
        -Recurse `
        -Force
}

New-Item `
    -ItemType Directory `
    -Path $tempExtract `
    -Force |
    Out-Null

# ------------------------------------------------------------
# Download Census data
# ------------------------------------------------------------

Write-Host ""
Write-Host "Downloading Census ZCTA database..."
Write-Host ""
Write-Host "Source:"
Write-Host $downloadUrl
Write-Host ""

try {

    Invoke-WebRequest `
        -Uri $downloadUrl `
        -OutFile $tempZip
}
catch {

    throw "Unable to download the Census ZCTA file. $($_.Exception.Message)"
}

# ------------------------------------------------------------
# Extract archive
# ------------------------------------------------------------

Write-Host "Extracting Census data..."

try {

    Expand-Archive `
        -Path $tempZip `
        -DestinationPath $tempExtract `
        -Force
}
catch {

    throw "Unable to extract the Census ZCTA archive. $($_.Exception.Message)"
}

# ------------------------------------------------------------
# Find ZCTA text file
# ------------------------------------------------------------

$sourceFile = Get-ChildItem `
    -Path $tempExtract `
    -Filter "*.txt" `
    -File |
    Where-Object {
        $_.Name -match "zcta"
    } |
    Select-Object -First 1

if (-not $sourceFile) {

    throw "Could not find the ZCTA text file inside the Census archive."
}

Write-Host "Source file:"
Write-Host "  $($sourceFile.FullName)"
Write-Host ""

# ------------------------------------------------------------
# Parse Census data
# ------------------------------------------------------------

Write-Host "Building local ZIP database..."

try {

    $records = Import-Csv `
        -Path $sourceFile.FullName `
        -Delimiter "|"
}
catch {

    throw "Unable to parse the Census ZCTA file. $($_.Exception.Message)"
}

if (-not $records -or $records.Count -eq 0) {

    throw "The Census ZCTA file contained no records."
}

# ------------------------------------------------------------
# Create lightweight CSV
# ------------------------------------------------------------

$zipRecords = foreach ($record in $records) {

    if (
        [string]::IsNullOrWhiteSpace($record.GEOID) -or
        [string]::IsNullOrWhiteSpace($record.INTPTLAT) -or
        [string]::IsNullOrWhiteSpace($record.INTPTLONG)
    ) {
        continue
    }

    [PSCustomObject]@{
        ZIP       = $record.GEOID
        Latitude  = $record.INTPTLAT.Trim()
        Longitude = $record.INTPTLONG.Trim()
    }
}

if (-not $zipRecords -or $zipRecords.Count -eq 0) {

    throw "No usable ZIP coordinates were found in the Census data."
}

# ------------------------------------------------------------
# Write CSV
# ------------------------------------------------------------

$zipRecords |
    Sort-Object {
        [int]$_.ZIP
    } |
    Export-Csv `
        -Path $outputFile `
        -NoTypeInformation `
        -Encoding UTF8

# ------------------------------------------------------------
# Validate output
# ------------------------------------------------------------

if (-not (Test-Path $outputFile)) {

    throw "The ZIP database was not created successfully."
}

$fileInfo = Get-Item $outputFile

# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------

Remove-Item `
    $tempDirectory `
    -Recurse `
    -Force

# ------------------------------------------------------------
# Done
# ------------------------------------------------------------

Write-Host ""
Write-Host "========================================"
Write-Host " ZIP database updated!"
Write-Host "========================================"
Write-Host ""
Write-Host "Records:   $($zipRecords.Count)"
Write-Host "File:      $outputFile"
Write-Host "Size:      $([math]::Round($fileInfo.Length / 1KB, 1)) KB"
Write-Host "Updated:   $($fileInfo.LastWriteTime)"
Write-Host ""