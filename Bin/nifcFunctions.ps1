# NifcFunctions.ps1
#
# Functions for interacting with the NIFC/WFIGS services.


# ------------------------------------------------------------
# Query current NIFC layer
# ------------------------------------------------------------

function Invoke-NifcQuery {
    param (
        [string]$Where = "1=1",

        [bool]$ReturnGeometry = $false,

        [int]$ResultRecordCount = 2000
    )

    $params = @{
        where             = $Where
        outFields         = $outFields
        returnGeometry    = $ReturnGeometry.ToString().ToLower()
        resultRecordCount = $ResultRecordCount
        orderByFields     = "poly_IncidentName ASC"
        f                 = "json"
    }

    $queryString = ($params.GetEnumerator() | ForEach-Object {
        "$($_.Key)=$([uri]::EscapeDataString([string]$_.Value))"
    }) -join "&"

    $url = "$currentServiceUrl`?$queryString"

    return Invoke-RestMethod `
        -Uri $url `
        -Method Get
}


# ------------------------------------------------------------
# Select historical perimeter
# ------------------------------------------------------------

function Select-HistoricalPerimeter {
    param (
        [Parameter(Mandatory)]
        $Fire
    )

    # --------------------------------------------------------
    # Build incident filter
    # --------------------------------------------------------

    if (
        -not [string]::IsNullOrWhiteSpace(
            $Fire.poly_IRWINID
        )
    ) {

        $escapedIrwinId = $Fire.poly_IRWINID.Replace(
            "'",
            "''"
        )

        $where = "poly_IRWINID = '$escapedIrwinId'"
    }
    elseif (
        -not [string]::IsNullOrWhiteSpace(
            $Fire.attr_UniqueFireIdentifier
        )
    ) {

        $escapedIncidentId =
            $Fire.attr_UniqueFireIdentifier.Replace(
                "'",
                "''"
            )

        $where =
            "attr_UniqueFireIdentifier = '$escapedIncidentId'"
    }
    else {

        $escapedName =
            $Fire.poly_IncidentName.Replace(
                "'",
                "''"
            )

        $where =
            "UPPER(poly_IncidentName) = '$($escapedName.ToUpper())'"
    }

    # --------------------------------------------------------
    # Historical fields
    # --------------------------------------------------------

    $historicalFields = @(
        "OBJECTID",
        "poly_IncidentName",
        "poly_GISAcres",
        "poly_PolygonDateTime",
        "poly_MapMethod",
        "poly_Source",
        "poly_IRWINID",
        "poly_CreateDate",
        "poly_DateCurrent",
        "attr_UniqueFireIdentifier"
    ) -join ","

    # --------------------------------------------------------
    # Query historical layer
    # --------------------------------------------------------

    $params = @{
        where          = $where
        outFields      = $historicalFields
        returnGeometry = "false"
        orderByFields  = "poly_PolygonDateTime ASC"
        f              = "json"
    }

    $queryString = ($params.GetEnumerator() | ForEach-Object {
        "$($_.Key)=$([uri]::EscapeDataString([string]$_.Value))"
    }) -join "&"

    $url = "$historicalServiceUrl`?$queryString"

    Write-Host ""
    Write-Host "Loading historical perimeters..."
    Write-Host ""

    try {

        $response = Invoke-RestMethod `
            -Uri $url `
            -Method Get
    }
    catch {

        Write-Host ""
        Write-Host "Historical perimeter query failed:"
        Write-Host $_.Exception.Message

        return $null
    }

    if (
        -not $response.features -or
        $response.features.Count -eq 0
    ) {

        Write-Host ""
        Write-Host "No historical perimeters were found for:"
        Write-Host "  $($Fire.poly_IncidentName)"
        Write-Host ""

        return $null
    }

    $perimeters = @(
        $response.features |
        ForEach-Object {
            $_.attributes
        }
    )

    # --------------------------------------------------------
    # Display historical records
    # --------------------------------------------------------

    while ($true) {

        Write-Host ""
        Write-Host "Historical perimeters for $($Fire.poly_IncidentName)"
        Write-Host "========================================"
        Write-Host ""

        for ($i = 0; $i -lt $perimeters.Count; $i++) {

            $perimeter = $perimeters[$i]

            Write-Host ("[{0,3}] {1}" -f `
                ($i + 1),
                (Format-NifcDate `
                    $perimeter.poly_PolygonDateTime))

            Write-Host ("      {0,8} acres | {1} | {2}" -f `
                (Format-Acres $perimeter.poly_GISAcres),
                $perimeter.poly_MapMethod,
                $perimeter.poly_Source)
        }

        Write-Host ""
        Write-Host "A. Download all historical perimeters"
        Write-Host "0. Back"
        Write-Host ""

        $selection = Read-Host "Select a perimeter"

        # ----------------------------------------------------
        # Back
        # ----------------------------------------------------

        if (
            $selection -eq "0" -or
            [string]::IsNullOrWhiteSpace($selection)
        ) {

            return $null
        }

        # ----------------------------------------------------
        # Download all historical perimeters
        # ----------------------------------------------------

        if ($selection -match "^[Aa]$") {

            Write-Host ""
            Write-Host "You are about to download $($perimeters.Count) historical perimeter(s)."
            Write-Host ""

            $downloadAll = Read-Host "Continue? [Y/n]"

            if (
                $downloadAll -ne "" -and
                $downloadAll -notmatch "^[Yy]$"
            ) {

                continue
            }

            if (-not (Test-Path $downloader)) {

                Write-Error "Could not find Get-FireKML.ps1 at:"
                Write-Error $downloader

                return $null
            }

            $fireOutputDirectory = Join-Path `
                $toolRoot `
                "Output\$($Fire.poly_IncidentName)"

            Write-Host ""
            Write-Host "========================================"
            Write-Host " Downloading historical perimeters"
            Write-Host "========================================"
            Write-Host ""

            $successful = 0
            $failed = 0

            foreach ($perimeter in $perimeters) {

                try {

                    Write-Host ""
                    Write-Host "Downloading: $(Format-NifcDate `
                        $perimeter.poly_PolygonDateTime)..."

                    & $downloader `
                        -ObjectId $perimeter.OBJECTID `
                        -Historical `
                        -OutputDirectory $fireOutputDirectory

                    if ($LASTEXITCODE -eq 0) {
                        $successful++
                    }
                    else {
                        $failed++
                    }
                }
                catch {

                    Write-Host ""
                    Write-Host "Failed to download perimeter:"
                    Write-Host $_.Exception.Message
                    Write-Host ""

                    $failed++
                }
            }

            Write-Host ""
            Write-Host "========================================"
            Write-Host " Historical batch complete"
            Write-Host "========================================"
            Write-Host ""
            Write-Host "Successful: $successful"
            Write-Host "Failed:     $failed"
            Write-Host ""

            Wait-ForEnter "Press Enter to return to the main menu"

            return $null
        }

        # ----------------------------------------------------
        # Select one historical perimeter
        # ----------------------------------------------------

        $selectedNumber = 0

        if (
            -not [int]::TryParse(
                $selection,
                [ref]$selectedNumber
            )
        ) {

            Write-Host ""
            Write-Host "Invalid selection."

            continue
        }

        if (
            $selectedNumber -lt 1 -or
            $selectedNumber -gt $perimeters.Count
        ) {

            Write-Host ""
            Write-Host "Invalid selection."

            continue
        }

        return $perimeters[$selectedNumber - 1]
    }
}