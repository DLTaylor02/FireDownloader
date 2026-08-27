# WildfireTool.ps1
#
# Main application for the NIFC Wildfire Tool.
#
# This script loads the supporting function libraries and
# provides the interactive menu/workflow.

$ErrorActionPreference = "Stop"


# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------

$toolRoot = Split-Path $PSScriptRoot -Parent

$binDirectory = $PSScriptRoot

$currentServiceUrl = "https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/services/WFIGS_Interagency_Perimeters_Current/FeatureServer/0/query"

$historicalServiceUrl = "https://services3.arcgis.com/T4QMspbfLg3qTGWY/arcgis/rest/services/WFIGS_Interagency_Perimeters/FeatureServer/0/query"

$downloader = Join-Path `
    $binDirectory `
    "Get-FireKML.ps1"

$zipDatabase = Join-Path `
    $toolRoot `
    "Data\zipcodes.csv"

$zipDatabaseMaxAgeDays = 90

# Enable historical perimeter selection.
#
# $true  = offer current and historical perimeter options (this feature is WIP and doesn't always work as intended)
# $false = always download the most recent perimeter
$makeHistoryAvailable = $false

# Fields used by current NIFC searches.
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


# ------------------------------------------------------------
# Load supporting function libraries
# ------------------------------------------------------------

$nifcFunctions = Join-Path `
    $binDirectory `
    "NifcFunctions.ps1"

$zipFunctions = Join-Path `
    $binDirectory `
    "ZipFunctions.ps1"

if (-not (Test-Path $nifcFunctions)) {

    throw "Could not find NifcFunctions.ps1 at: $nifcFunctions"
}

if (-not (Test-Path $zipFunctions)) {

    throw "Could not find ZipFunctions.ps1 at: $zipFunctions"
}

. $nifcFunctions
. $zipFunctions


# ------------------------------------------------------------
# Helper: Format acres
# ------------------------------------------------------------

function Format-Acres {
    param (
        $Acres
    )

    if ($null -eq $Acres -or $Acres -eq "") {
        return "N/A"
    }

    return ([double]$Acres).ToString("N0")
}


# ------------------------------------------------------------
# Helper: Format NIFC date
# ------------------------------------------------------------

function Format-NifcDate {
    param (
        $DateValue
    )

    if ($null -eq $DateValue -or $DateValue -eq "") {
        return "N/A"
    }

    try {

        if (
            $DateValue -is [long] -or
            $DateValue -is [int] -or
            $DateValue -is [double]
        ) {

            return [DateTimeOffset]::FromUnixTimeMilliseconds(
                [int64]$DateValue
            ).ToLocalTime().ToString("MMM dd yyyy HH:mm")
        }

        return ([datetime]$DateValue).ToLocalTime().ToString(
            "MMM dd yyyy HH:mm"
        )
    }
    catch {

        return [string]$DateValue
    }
}


# ------------------------------------------------------------
# Helper: Display fire details
# ------------------------------------------------------------

function Show-FireDetails {
    param (
        $Fire
    )

    Write-Host ""
    Write-Host "========================================"
    Write-Host " $($Fire.poly_IncidentName)"
    Write-Host "========================================"
    Write-Host ""

    Write-Host "Acres:          $(Format-Acres $Fire.poly_GISAcres)"
    Write-Host "Containment:    $($Fire.attr_PercentContained)%"
    Write-Host "State:          $($Fire.attr_POOState)"
    Write-Host "Last perimeter: $(Format-NifcDate $Fire.poly_PolygonDateTime)"
    Write-Host "Map method:     $($Fire.poly_MapMethod)"
    Write-Host "Source:         $($Fire.poly_Source)"
    Write-Host "Incident ID:    $($Fire.attr_UniqueFireIdentifier)"
    Write-Host "IRWIN ID:       $($Fire.poly_IRWINID)"
    Write-Host "OBJECTID:       $($Fire.OBJECTID)"
    Write-Host ""
}


# ------------------------------------------------------------
# Helper: Get menu selection
# ------------------------------------------------------------

function Get-MenuSelection {
    param (
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter(Mandatory)]
        [int]$Maximum
    )

    while ($true) {

        $selection = Read-Host $Prompt

        if ($selection -eq "0") {
            return 0
        }

        $number = 0

        if (
            [int]::TryParse($selection, [ref]$number) -and
            $number -ge 1 -and
            $number -le $Maximum
        ) {
            return $number
        }

        Write-Host ""
        Write-Host "Please enter a number between 1 and $Maximum, or 0 to go back."
        Write-Host ""
    }
}


# ------------------------------------------------------------
# Helper: Pause
# ------------------------------------------------------------

function Wait-ForEnter {
    param (
        [string]$Message = "Press Enter to continue"
    )

    Write-Host ""
    Read-Host $Message
}


# ------------------------------------------------------------
# Download fire perimeter
# ------------------------------------------------------------

function Download-FirePerimeter {
    param (
        [Parameter(Mandatory)]
        $Fire,

        [switch]$SkipConfirmation
    )

    # --------------------------------------------------------
    # Confirmation and perimeter selection
    # --------------------------------------------------------

    if (-not $SkipConfirmation) {

        Write-Host ""

        $download = Read-Host "Download this perimeter? [Y/n]"

        if (
            $download -ne "" -and
            $download -notmatch "^[Yy]$"
        ) {
            return $false
        }

        # ----------------------------------------------------
        # Historical functionality enabled
        # ----------------------------------------------------

        if ($makeHistoryAvailable) {

            Write-Host ""
            Write-Host "Which perimeter would you like to download?"
            Write-Host ""
            Write-Host "1. Most recent perimeter"
            Write-Host "2. Historical perimeter"
            Write-Host "0. Back"
            Write-Host ""

            $perimeterChoice = Read-Host "Selection"

            switch ($perimeterChoice) {

                "0" {
                    return $false
                }

                "1" {
                    $perimeterId = $Fire.OBJECTID
                    $historical = $false
                }

                "2" {

                    $historicalPerimeter = Select-HistoricalPerimeter `
                        -Fire $Fire

                    if ($null -eq $historicalPerimeter) {
                        return $false
                    }

                    $perimeterId = $historicalPerimeter.OBJECTID
                    $historical = $true
                }

                default {

                    Write-Host ""
                    Write-Host "Invalid selection."

                    return $false
                }
            }
        }

        # ----------------------------------------------------
        # Historical functionality disabled
        # ----------------------------------------------------

        else {

            $perimeterId = $Fire.OBJECTID
            $historical = $false
        }
    }

    # --------------------------------------------------------
    # Batch operations always use current perimeter.
    # --------------------------------------------------------

    else {

        $perimeterId = $Fire.OBJECTID
        $historical = $false
    }

    # --------------------------------------------------------
    # Verify downloader
    # --------------------------------------------------------

    if (-not (Test-Path $downloader)) {

        Write-Error "Could not find Get-FireKML.ps1 at:"
        Write-Error $downloader

        return $false
    }

    # --------------------------------------------------------
    # Download
    # --------------------------------------------------------

    Write-Host ""

    if ($historical) {

        Write-Host "Downloading historical perimeter..."

        & $downloader `
            -ObjectId $perimeterId `
            -Historical
    }
    else {

        Write-Host "Downloading current perimeter..."

        & $downloader `
            -ObjectId $perimeterId
    }

    return $true
}


# ------------------------------------------------------------
# Search by fire name
# ------------------------------------------------------------

function Search-Fires {

    Write-Host ""
    Write-Host "Enter a fire name or partial name."
    Write-Host "Examples: Bug, Davis, Mosquito"
    Write-Host ""

    $search = Read-Host "Search"

    if ([string]::IsNullOrWhiteSpace($search)) {
        return
    }

    $escapedSearch = $search.Replace("'", "''")

    $where = "UPPER(poly_IncidentName) LIKE '%$($escapedSearch.ToUpper())%'"

    Write-Host ""
    Write-Host "Searching NIFC..."
    Write-Host ""

    $response = Invoke-NifcQuery -Where $where

    if (
        -not $response.features -or
        $response.features.Count -eq 0
    ) {

        Write-Host "No fires found matching '$search'."

        return
    }

    $fires = @(
        $response.features |
        ForEach-Object {
            $_.attributes
        }
    )

    Write-Host ""
    Write-Host "Found $($fires.Count) fire(s):"
    Write-Host ""

    for ($i = 0; $i -lt $fires.Count; $i++) {

        $fire = $fires[$i]

        Write-Host ("[{0}] {1}" -f `
            ($i + 1),
            $fire.poly_IncidentName)

        Write-Host ("    Acres:       {0}" -f `
            (Format-Acres $fire.poly_GISAcres))

        Write-Host ("    Containment: {0}%" -f `
            $fire.attr_PercentContained)

        Write-Host ("    State:       {0}" -f `
            $fire.attr_POOState)

        Write-Host ("    Updated:     {0}" -f `
            (Format-NifcDate $fire.poly_PolygonDateTime))

        Write-Host ""
    }

    $selectedNumber = Get-MenuSelection `
        -Prompt "Select a fire" `
        -Maximum $fires.Count

    if ($selectedNumber -eq 0) {
        return
    }

    $selectedFire = $fires[$selectedNumber - 1]

    Show-FireDetails $selectedFire

    Download-FirePerimeter -Fire $selectedFire
}


# ------------------------------------------------------------
# Show all current fires
# ------------------------------------------------------------

function Show-ActiveFires {

    Write-Host ""
    Write-Host "Querying current NIFC fire perimeters..."
    Write-Host ""

    $response = Invoke-NifcQuery

    if (-not $response.features) {

        Write-Host "No fires returned."

        return
    }

    $fires = @(
        $response.features |
        ForEach-Object {
            $_.attributes
        }
    )

    # Sort by acres descending.
    $fires = @(
        $fires |
        Sort-Object {
            if ($_.poly_GISAcres) {
                [double]$_.poly_GISAcres
            }
            else {
                0
            }
        } -Descending
    )

    while ($true) {

        Write-Host ""
        Write-Host "Current NIFC Perimeters"
        Write-Host "========================================"
        Write-Host ""

        for ($i = 0; $i -lt $fires.Count; $i++) {

            $fire = $fires[$i]

            Write-Host ("[{0,3}] {1}" -f `
                ($i + 1),
                $fire.poly_IncidentName)

            Write-Host ("      {0,8} acres | {1}% contained | {2}" -f `
                (Format-Acres $fire.poly_GISAcres),
                $fire.attr_PercentContained,
                $fire.attr_POOState)
        }

        Write-Host ""
        Write-Host "0. Back"
        Write-Host ""

        $selectedNumber = Get-MenuSelection `
            -Prompt "Select a fire" `
            -Maximum $fires.Count

        if ($selectedNumber -eq 0) {
            return
        }

        $selectedFire = $fires[$selectedNumber - 1]

        Show-FireDetails $selectedFire

        if (Download-FirePerimeter -Fire $selectedFire) {

            Wait-ForEnter "Press Enter to return to the main menu"

            return
        }
    }
}


# ------------------------------------------------------------
# Find fires by ZIP code
# ------------------------------------------------------------

function Find-FiresByZip {

    Write-Host ""
    Write-Host "Find fires by ZIP code"
    Write-Host "========================================"
    Write-Host ""

    # --------------------------------------------------------
    # ZIP code
    # --------------------------------------------------------

    while ($true) {

        $zipCode = Read-Host "ZIP code"

        if ($zipCode -match '^\d{5}$') {
            break
        }

        Write-Host ""
        Write-Host "Please enter a valid 5-digit ZIP code."
        Write-Host ""
    }

    # --------------------------------------------------------
    # Radius
    # --------------------------------------------------------

    while ($true) {

        $radiusInput = Read-Host "Radius (miles)"

        $radius = 0

        if (
            [double]::TryParse(
                $radiusInput,
                [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$radius
            ) -and
            $radius -gt 0
        ) {

            break
        }

        Write-Host ""
        Write-Host "Please enter a radius greater than zero."
        Write-Host ""
    }

    # --------------------------------------------------------
    # Get ZIP coordinates
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Locating ZIP code $zipCode..."

    try {

        $location = Get-ZipCoordinates `
            -ZipCode $zipCode
    }
    catch {

        Write-Host ""
        Write-Host $_.Exception.Message

        return
    }

    Write-Host ("Location: {0:N5}, {1:N5}" -f `
        $location.Latitude,
        $location.Longitude)

    # --------------------------------------------------------
    # Query NIFC using actual perimeter geometry
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Searching for fire perimeters..."

    $params = @{
        where          = "1=1"
        geometry       = "$($location.Longitude),$($location.Latitude)"
        geometryType   = "esriGeometryPoint"
        inSR           = "4326"
        spatialRel     = "esriSpatialRelIntersects"
        distance       = $radius
        units          = "esriSRUnit_StatuteMile"
        outFields      = $outFields
        returnGeometry = "false"
        orderByFields  = "poly_IncidentName ASC"
        f              = "json"
    }

    $queryString = ($params.GetEnumerator() | ForEach-Object {
        "$($_.Key)=$([uri]::EscapeDataString([string]$_.Value))"
    }) -join "&"

    $url = "$currentServiceUrl`?$queryString"

    try {

        $response = Invoke-RestMethod `
            -Uri $url `
            -Method Get
    }
    catch {

        Write-Host ""
        Write-Host "NIFC spatial query failed:"
        Write-Host $_.Exception.Message

        return
    }

    if (
        -not $response.features -or
        $response.features.Count -eq 0
    ) {

        Write-Host ""
        Write-Host "No fire perimeters found within $radius miles of ZIP $zipCode."
        Write-Host ""

        return
    }

    $fires = @(
        $response.features |
        ForEach-Object {
            $_.attributes
        }
    )

    # --------------------------------------------------------
    # Display results
    # --------------------------------------------------------

    Write-Host ""
    Write-Host "Fires within $radius miles of ZIP $zipCode"
    Write-Host "========================================"
    Write-Host ""

    for ($i = 0; $i -lt $fires.Count; $i++) {

        $fire = $fires[$i]

        Write-Host ("[{0,3}] {1}" -f `
            ($i + 1),
            $fire.poly_IncidentName)

        Write-Host ("      {0,8} acres | {1}% contained | {2}" -f `
            (Format-Acres $fire.poly_GISAcres),
            $fire.attr_PercentContained,
            $fire.attr_POOState)

        Write-Host ("      Perimeter: {0}" -f `
            (Format-NifcDate $fire.poly_PolygonDateTime))

        Write-Host ""
    }

    # --------------------------------------------------------
    # Selection
    # --------------------------------------------------------

    Write-Host "A. Download all fires"
    Write-Host "0. Back"
    Write-Host ""

    $selection = Read-Host "Select a fire"

    if (
        $selection -eq "0" -or
        [string]::IsNullOrWhiteSpace($selection)
    ) {

        return
    }

    # --------------------------------------------------------
    # Download all current fire perimeters
    # --------------------------------------------------------

    if ($selection -match "^[Aa]$") {

        Write-Host ""
        Write-Host "You are about to download $($fires.Count) fire perimeter(s)."
        Write-Host ""

        $downloadAll = Read-Host "Continue? [Y/n]"

        if (
            $downloadAll -ne "" -and
            $downloadAll -notmatch "^[Yy]$"
        ) {

            return
        }

        Write-Host ""
        Write-Host "========================================"
        Write-Host " Downloading all current perimeters"
        Write-Host "========================================"
        Write-Host ""

        $successful = 0
        $failed = 0

        foreach ($fire in $fires) {

            try {

                if (
                    Download-FirePerimeter `
                        -Fire $fire `
                        -SkipConfirmation
                ) {

                    $successful++
                }
                else {

                    $failed++
                }
            }
            catch {

                Write-Host ""
                Write-Host "Failed to download $($fire.poly_IncidentName):"
                Write-Host $_.Exception.Message
                Write-Host ""

                $failed++
            }
        }

        Write-Host ""
        Write-Host "========================================"
        Write-Host " Batch download complete"
        Write-Host "========================================"
        Write-Host ""
        Write-Host "Successful: $successful"
        Write-Host "Failed:     $failed"
        Write-Host ""

        return
    }

    # --------------------------------------------------------
    # Download one fire
    # --------------------------------------------------------

    $selectedNumber = 0

    if (
        -not [int]::TryParse(
            $selection,
            [ref]$selectedNumber
        )
    ) {

        Write-Host ""
        Write-Host "Invalid selection."

        return
    }

    if (
        $selectedNumber -lt 1 -or
        $selectedNumber -gt $fires.Count
    ) {

        Write-Host ""
        Write-Host "Invalid selection."

        return
    }

    $selectedFire = $fires[$selectedNumber - 1]

    Show-FireDetails $selectedFire

    if (Download-FirePerimeter -Fire $selectedFire) {
        return
    }
}


# ------------------------------------------------------------
# Main menu
# ------------------------------------------------------------

function Show-MainMenu {

    Clear-Host

    Write-Host "========================================"
    Write-Host "       NIFC WILDFIRE TOOL"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "1. Search for a fire"
    Write-Host "2. Show current fires"
    Write-Host "3. Find fires by ZIP code"
    Write-Host "4. Exit"
    Write-Host ""

    return Read-Host "Selection"
}


# ------------------------------------------------------------
# Main application loop
# ------------------------------------------------------------

while ($true) {

    $choice = Show-MainMenu

    switch ($choice) {

        "1" {

            Search-Fires

            Wait-ForEnter
        }

        "2" {

            Show-ActiveFires
        }

        "3" {

            Find-FiresByZip

            Wait-ForEnter
        }

        "4" {

            Clear-Host

            exit
        }

        default {

            Write-Host ""
            Write-Host "Invalid selection."

            Start-Sleep -Seconds 1
        }
    }
}