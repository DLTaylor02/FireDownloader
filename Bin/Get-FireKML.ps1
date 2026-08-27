# Get-FireKML.ps1
#
# Downloads a NIFC/WFIGS fire perimeter by OBJECTID
# and converts it to a Google Earth KMZ.
#
# Default:
#   Current WFIGS perimeter
#
# -Historical:
#   Historical WFIGS perimeter

param (
    [Parameter(Mandatory)]
    [int]$ObjectId,

    [switch]$Historical,

    [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"


# ------------------------------------------------------------
# Load configuration
# ------------------------------------------------------------

$configFile = Join-Path `
    $PSScriptRoot `
    "Config.ps1"

if (-not (Test-Path $configFile)) {

    throw "Could not find Config.ps1 at: $configFile"
}

. $configFile


# ------------------------------------------------------------
# Determine service
# ------------------------------------------------------------

if ($Historical) {

    $serviceUrl = $historicalServiceUrl
}
else {

    $serviceUrl = $currentServiceUrl
}


# ------------------------------------------------------------
# Determine output directory
# ------------------------------------------------------------

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {

    $OutputDirectory = $outputDirectory
}

if (-not (Test-Path $OutputDirectory)) {

    New-Item `
        -ItemType Directory `
        -Path $OutputDirectory `
        -Force |
        Out-Null
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

$response = Invoke-RestMethod `
    -Uri $url `
    -Method Get


# ------------------------------------------------------------
# Validate response
# ------------------------------------------------------------

if (
    -not $response.features -or
    $response.features.Count -eq 0
) {

    throw "No perimeter found for OBJECTID $ObjectId."
}

if ($response.features.Count -gt 1) {

    Write-Warning `
        "NIFC returned multiple features for OBJECTID $ObjectId."
}

$feature = $response.features[0]

$properties = $feature.properties

$geometry = $feature.geometry


# ------------------------------------------------------------
# Display fire information
# ------------------------------------------------------------

$fireName = $properties.poly_IncidentName

if ([string]::IsNullOrWhiteSpace($fireName)) {

    $fireName = "Unknown Fire"
}

Write-Host "Fire:        $fireName"
Write-Host "GIS Acres:   $($properties.poly_GISAcres)"
Write-Host "Containment: $($properties.attr_PercentContained)%"
Write-Host "Perimeter:   $($properties.poly_PolygonDateTime)"
Write-Host "Map Method:  $($properties.poly_MapMethod)"
Write-Host "Source:      $($properties.poly_Source)"
Write-Host "Incident ID: $($properties.attr_UniqueFireIdentifier)"
Write-Host ""


# ------------------------------------------------------------
# Convert GeoJSON ring to KML coordinates
# ------------------------------------------------------------

function ConvertTo-KmlText {
    param (
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return [System.Security.SecurityElement]::Escape(
        [string]$Value
    )
}


function ConvertTo-KmlDescriptionText {
    param (
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return ""
    }

    # Descriptions contain HTML inside CDATA.  HTML-encode data values so
    # upstream text is displayed as text instead of being interpreted as HTML.
    return [System.Net.WebUtility]::HtmlEncode(
        [string]$Value
    )
}


function Convert-CoordinateRingToKml {
    param (
        [Parameter(Mandatory)]
        $Ring
    )

    # GeoJSON:
    #   longitude, latitude
    #
    # KML:
    #   longitude, latitude, altitude

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

$kmlFireName = ConvertTo-KmlText $fireName

$descriptionFireName = ConvertTo-KmlDescriptionText $fireName
$descriptionGisAcres = ConvertTo-KmlDescriptionText `
    $properties.poly_GISAcres
$descriptionContainment = ConvertTo-KmlDescriptionText `
    $properties.attr_PercentContained
$descriptionPerimeterDate = ConvertTo-KmlDescriptionText `
    $properties.poly_PolygonDateTime
$descriptionMapMethod = ConvertTo-KmlDescriptionText `
    $properties.poly_MapMethod
$descriptionSource = ConvertTo-KmlDescriptionText `
    $properties.poly_Source
$descriptionIncidentId = ConvertTo-KmlDescriptionText `
    $properties.attr_UniqueFireIdentifier
$descriptionIrwinId = ConvertTo-KmlDescriptionText `
    $properties.poly_IRWINID

$placemarkParts = @()

foreach ($polygon in $polygons) {

    $outerRing = Convert-CoordinateRingToKml `
        -Ring $polygon[0]

    $innerRings = ""

    if ($polygon.Count -gt 1) {

        foreach ($hole in $polygon[1..($polygon.Count - 1)]) {

            $holeCoordinates = Convert-CoordinateRingToKml `
                -Ring $hole

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

            <name>$kmlFireName</name>

            <description><![CDATA[
                <b>Fire:</b> $descriptionFireName<br>
                <b>GIS Acres:</b> $descriptionGisAcres<br>
                <b>Containment:</b> $descriptionContainment%<br>
                <b>Perimeter Date:</b> $descriptionPerimeterDate<br>
                <b>Mapping Method:</b> $descriptionMapMethod<br>
                <b>Source:</b> $descriptionSource<br>
                <b>Incident ID:</b> $descriptionIncidentId<br>
                <b>IRWIN ID:</b> $descriptionIrwinId<br>
                <b>Historical:</b> $Historical<br>
                <b>Retrieved:</b> $(Get-Date)<br>
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

        <name>$kmlFireName - $timestamp</name>

        <description><![CDATA[
            <b>Fire:</b> $descriptionFireName<br>
            <b>GIS Acres:</b> $descriptionGisAcres<br>
            <b>Containment:</b> $descriptionContainment%<br>
            <b>Perimeter Date:</b> $descriptionPerimeterDate<br>
            <b>Mapping Method:</b> $descriptionMapMethod<br>
            <b>Source:</b> $descriptionSource<br>
            <b>Retrieved:</b> $(Get-Date)<br>
        ]]></description>

$($placemarkParts -join "`n")

    </Document>

</kml>
"@


# ------------------------------------------------------------
# Create temporary KML
# ------------------------------------------------------------

$safeFireName = $fireName -replace '[\\/:*?"<>|]', '_'

$tempKml = Join-Path `
    $env:TEMP `
    "${safeFireName}_${timestamp}.kml"


[System.IO.File]::WriteAllText(
    $tempKml,
    $kml,
    [System.Text.UTF8Encoding]::new($false)
)


# ------------------------------------------------------------
# Package as KMZ
# ------------------------------------------------------------

$tempDir = Join-Path `
    $env:TEMP `
    "FireKMZ_$([guid]::NewGuid().ToString())"

$tempZip = Join-Path `
    $env:TEMP `
    "${safeFireName}_${timestamp}.zip"

$outputKmz = Join-Path `
    $OutputDirectory `
    "${safeFireName}_${timestamp}.kmz"


New-Item `
    -ItemType Directory `
    -Path $tempDir `
    -Force |
    Out-Null


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

Remove-Item `
    $tempKml `
    -Force

Remove-Item `
    $tempDir `
    -Recurse `
    -Force


# ------------------------------------------------------------
# Done
# ------------------------------------------------------------

Write-Host ""
Write-Host "========================================"
Write-Host "Download complete!"
Write-Host "========================================"
Write-Host ""
Write-Host "Fire:"
Write-Host "  $fireName"
Write-Host ""

if ($Historical) {
    Write-Host "Perimeter:"
    Write-Host "  Historical"
}
else {
    Write-Host "Perimeter:"
    Write-Host "  Current"
}

Write-Host ""
Write-Host "Output:"
Write-Host "  $outputKmz"
Write-Host ""
