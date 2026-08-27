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

$configFile = Join-Path `
    $PSScriptRoot `
    "Config.ps1"

if (-not (Test-Path $configFile)) {
    throw "Could not find Config.ps1 at: $configFile"
}

. $configFile

$tempDirectory = $null
$temporaryZipDatabase = $null
$previousZipDatabase = $null

try {

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
    "WildfireTools_ZCTA_$([guid]::NewGuid().ToString('N'))"

$tempZip = Join-Path `
    $tempDirectory `
    "zcta.zip"

$tempExtract = Join-Path `
    $tempDirectory `
    "Extracted"

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
Write-Host $zipDatabaseDownloadUrl
Write-Host ""

try {

    Invoke-WebRequest `
        -Uri $zipDatabaseDownloadUrl `
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

$temporaryZipDatabase = Join-Path `
    $dataDirectory `
    ".zipcodes.$([guid]::NewGuid().ToString('N')).csv.tmp"

$zipRecords |
    Sort-Object {
        [int]$_.ZIP
    } |
    Export-Csv `
        -Path $temporaryZipDatabase `
        -NoTypeInformation `
        -Encoding UTF8

# ------------------------------------------------------------
# Validate and replace the active ZIP database
# ------------------------------------------------------------

if (
    -not (Test-Path $temporaryZipDatabase) -or
    (Get-Item $temporaryZipDatabase).Length -eq 0
) {

    throw "The temporary ZIP database was not created successfully."
}

$validationRecords = @(
    Import-Csv -Path $temporaryZipDatabase
)

if (
    $validationRecords.Count -ne $zipRecords.Count -or
    -not $validationRecords[0].PSObject.Properties.Name.Contains("ZIP") -or
    -not $validationRecords[0].PSObject.Properties.Name.Contains("Latitude") -or
    -not $validationRecords[0].PSObject.Properties.Name.Contains("Longitude")
) {

    throw "The temporary ZIP database failed validation."
}

if (Test-Path $zipDatabase) {

    # Replaces the file atomically when both files are on the same volume.
    $previousZipDatabase = Join-Path `
        $dataDirectory `
        ".zipcodes.$([guid]::NewGuid().ToString('N')).bak"

    [System.IO.File]::Replace(
        $temporaryZipDatabase,
        $zipDatabase,
        $previousZipDatabase
    )
}
else {

    Move-Item `
        -Path $temporaryZipDatabase `
        -Destination $zipDatabase
}

$temporaryZipDatabase = $null

if (-not (Test-Path $zipDatabase)) {

    throw "The ZIP database was not replaced successfully."
}

$fileInfo = Get-Item $zipDatabase

}
finally {

    # --------------------------------------------------------
    # Cleanup
    # --------------------------------------------------------

    if ($temporaryZipDatabase -and (Test-Path $temporaryZipDatabase)) {

        Remove-Item `
            -Path $temporaryZipDatabase `
            -Force `
            -ErrorAction SilentlyContinue
    }

    if ($previousZipDatabase -and (Test-Path $previousZipDatabase)) {

        Remove-Item `
            -Path $previousZipDatabase `
            -Force `
            -ErrorAction SilentlyContinue
    }

    if ($tempDirectory -and (Test-Path $tempDirectory)) {

        Remove-Item `
            -Path $tempDirectory `
            -Recurse `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------------------
# Done
# ------------------------------------------------------------

Write-Host ""
Write-Host "========================================"
Write-Host " ZIP database updated!"
Write-Host "========================================"
Write-Host ""
Write-Host "Records:   $($zipRecords.Count)"
Write-Host "File:      $zipDatabase"
Write-Host "Size:      $([math]::Round($fileInfo.Length / 1KB, 1)) KB"
Write-Host "Updated:   $($fileInfo.LastWriteTime)"
Write-Host ""
