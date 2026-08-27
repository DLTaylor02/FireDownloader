param (
    [Parameter(Mandatory)]
    [int]$ObjectId,

    [string]$OutputDirectory = ".\Output"
)

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$serviceUrl = "https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/services/WFIGS_Interagency_Perimeters_Current/FeatureServer/0/query"

# ------------------------------------------------------------
# Prepare output directory
# ------------------------------------------------------------

if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

# ------------------------------------------------------------
# Query NIFC
# ------------------------------------------------------------

Write-Host ""
Write-Host "Querying NIFC/WFIGS..."
Write-Host ""

$params = @{
    where          = "OBJECTID = $ObjectId"
    outFields      = "*"
    returnGeometry = "true"
    outSR          = "4326"
    f              = "geojson"
}

$queryString = ($params.GetEnumerator() | ForEach-Object {
    "$($_.Key)=$([uri]::EscapeDataString([string]$_.Value))"
}) -join "&"

$url = "$serviceUrl`?$queryString"

$response = Invoke-RestMethod -Uri $url -Method Get

if (-not $response.features -or $response.features.Count -eq 0) {
    throw "No perimeter found for OBJECTID $ObjectId."
}

if ($response.features.Count -gt 1) {
    Write-Warning "NIFC returned multiple features for OBJECTID $ObjectId."
}

$feature = $response.features[0]
$properties = $feature.properties
$geometry = $feature.geometry

# ------------------------------------------------------------
# Display fire information
# ------------------------------------------------------------

$fireName = $properties.poly_IncidentName

Write-Host "Fire:       $fireName"
Write-Host "GIS Acres:  $($properties.poly_GISAcres)"
Write-Host "Containment:$($properties.attr_PercentContained)%"
Write-Host "Perimeter:  $($properties.poly_PolygonDateTime)"
Write-Host "Map Method: $($properties.poly_MapMethod)"
Write-Host "Source:     $($properties.poly_Source)"
Write-Host "Incident ID:$($properties.attr_UniqueFireIdentifier)"
Write-Host ""

# ------------------------------------------------------------
# Convert GeoJSON ring to KML coordinates
# ------------------------------------------------------------

function Convert-CoordinateRingToKml {
    param (
        [Parameter(Mandatory)]
        $Ring
    )

    return (($Ring | ForEach-Object {
        "$($_[0]),$($_[1]),0"
    }) -join " ")
}

# ------------------------------------------------------------
# Normalize Polygon / MultiPolygon
# ------------------------------------------------------------

$polygons = @()

switch ($geometry.type) {

    "Polygon" {
        $polygons += ,$geometry.coordinates
    }

    "MultiPolygon" {
        foreach ($polygon in $geometry.coordinates) {
            $polygons += ,$polygon
        }
    }

    default {
        throw "Unexpected geometry type: $($geometry.type)"
    }
}

# ------------------------------------------------------------
# Generate KML polygons
# ------------------------------------------------------------

$placemarkParts = @()

foreach ($polygon in $polygons) {

    $outerRing = Convert-CoordinateRingToKml -Ring $polygon[0]

    $innerRings = ""

    if ($polygon.Count -gt 1) {

        foreach ($hole in $polygon[1..($polygon.Count - 1)]) {

            $holeCoordinates = Convert-CoordinateRingToKml -Ring $hole

            $innerRings += @"
                <innerBoundaryIs>
                    <LinearRing>
                        <coordinates>$holeCoordinates</coordinates>
                    </LinearRing>
                </innerBoundaryIs>
"@
        }
    }

    $placemarkParts += @"
        <Placemark>
            <name>$fireName</name>

            <description><![CDATA[
                <b>Fire:</b> $fireName<br>
                <b>GIS Acres:</b> $($properties.poly_GISAcres)<br>
                <b>Containment:</b> $($properties.attr_PercentContained)%<br>
                <b>Perimeter Date:</b> $($properties.poly_PolygonDateTime)<br>
                <b>Mapping Method:</b> $($properties.poly_MapMethod)<br>
                <b>Source:</b> $($properties.poly_Source)<br>
                <b>Incident ID:</b> $($properties.attr_UniqueFireIdentifier)<br>
                <b>IRWIN ID:</b> $($properties.poly_IRWINID)<br>
            ]]></description>

            <Style>
                <LineStyle>
                    <color>ff0000ff</color>
                    <width>3</width>
                </LineStyle>

                <PolyStyle>
                    <color>400000ff</color>
                    <fill>1</fill>
                    <outline>1</outline>
                </PolyStyle>
            </Style>

            <Polygon>

                <outerBoundaryIs>
                    <LinearRing>
                        <coordinates>$outerRing</coordinates>
                    </LinearRing>
                </outerBoundaryIs>

$innerRings

            </Polygon>

        </Placemark>
"@
}

# ------------------------------------------------------------
# Build KML
# ------------------------------------------------------------

$timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"

$kml = @"
<?xml version="1.0" encoding="UTF-8"?>

<kml xmlns="http://www.opengis.net/kml/2.2">

    <Document>

        <name>$fireName - $timestamp</name>

        <description><![CDATA[
            <b>Fire:</b> $fireName<br>
            <b>GIS Acres:</b> $($properties.poly_GISAcres)<br>
            <b>Containment:</b> $($properties.attr_PercentContained)%<br>
            <b>Perimeter Date:</b> $($properties.poly_PolygonDateTime)<br>
            <b>Mapping Method:</b> $($properties.poly_MapMethod)<br>
            <b>Source:</b> $($properties.poly_Source)<br>
            <b>Retrieved:</b> $(Get-Date)<br>
        ]]></description>

$($placemarkParts -join "`n")

    </Document>

</kml>
"@

# ------------------------------------------------------------
# Create temporary KML
# ------------------------------------------------------------

$tempKml = Join-Path $env:TEMP "BugFire_$timestamp.kml"

[System.IO.File]::WriteAllText(
    $tempKml,
    $kml,
    [System.Text.UTF8Encoding]::new($false)
)

# ------------------------------------------------------------
# Package as KMZ
# ------------------------------------------------------------

$tempDir = Join-Path $env:TEMP "FireKMZ_$timestamp"
$tempZip = Join-Path $env:TEMP "$fireName`_$timestamp.zip"

$safeFireName = $fireName -replace '[\\/:*?"<>|]', '_'

$outputKmz = Join-Path `
    $OutputDirectory `
    "${safeFireName}_$timestamp.kmz"

New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

Copy-Item `
    $tempKml `
    (Join-Path $tempDir "doc.kml")

Compress-Archive `
    -Path (Join-Path $tempDir "doc.kml") `
    -DestinationPath $tempZip `
    -Force

Move-Item `
    $tempZip `
    $outputKmz `
    -Force

# ------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------

Remove-Item $tempKml -Force
Remove-Item $tempDir -Recurse -Force

# ------------------------------------------------------------
# Done
# ------------------------------------------------------------

Write-Host ""
Write-Host "========================================"
Write-Host "Download complete!"
Write-Host "========================================"
Write-Host ""
Write-Host "Output:"
Write-Host "  $outputKmz"
Write-Host ""