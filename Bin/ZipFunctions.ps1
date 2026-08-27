# ZipFunctions.ps1
#
# Functions for managing and reading the local ZIP/ZCTA
# coordinate database.


# ------------------------------------------------------------
# Check ZIP database age
# ------------------------------------------------------------

function Test-ZipDatabaseFresh {

    if (-not (Test-Path $zipDatabase)) {
        return $false
    }

    $file = Get-Item $zipDatabase

    $age = (Get-Date) - $file.LastWriteTime

    return $age.TotalDays -lt $zipDatabaseMaxAgeDays
}


# ------------------------------------------------------------
# Update ZIP database
# ------------------------------------------------------------

function Update-ZipDatabase {

    $updater = Join-Path `
        $binDirectory `
        "Update-ZipDatabase.ps1"

    if (-not (Test-Path $updater)) {

        throw "Could not find Update-ZipDatabase.ps1 at: $updater"
    }

    Write-Host ""
    Write-Host "Updating ZIP coordinate database..."
    Write-Host ""

    & $updater

    if (-not (Test-Path $zipDatabase)) {

        throw "ZIP database update completed, but the database file was not found."
    }
}


# ------------------------------------------------------------
# Ensure ZIP database is available and fresh
# ------------------------------------------------------------

function Ensure-ZipDatabase {

    if (Test-ZipDatabaseFresh) {
        return $true
    }

    # --------------------------------------------------------
    # Database missing
    # --------------------------------------------------------

    if (-not (Test-Path $zipDatabase)) {

        Write-Host ""
        Write-Host "ZIP coordinate database is not installed."
        Write-Host ""

        $update = Read-Host "Download it now? [Y/n]"

        if (
            $update -ne "" -and
            $update -notmatch "^[Yy]$"
        ) {

            return $false
        }
    }

    # --------------------------------------------------------
    # Database expired
    # --------------------------------------------------------

    else {

        $file = Get-Item $zipDatabase
        $age = (Get-Date) - $file.LastWriteTime

        Write-Host ""
        Write-Host "The ZIP coordinate database is $([math]::Floor($age.TotalDays)) days old."
        Write-Host "The refresh interval is $zipDatabaseMaxAgeDays days."
        Write-Host ""

        $update = Read-Host "Update it now? [Y/n]"

        if (
            $update -ne "" -and
            $update -notmatch "^[Yy]$"
        ) {

            return $false
        }
    }

    # --------------------------------------------------------
    # Perform update
    # --------------------------------------------------------

    try {

        Update-ZipDatabase

        return $true
    }
    catch {

        Write-Host ""
        Write-Host "ZIP database update failed:"
        Write-Host $_.Exception.Message
        Write-Host ""

        # Fall back to an existing database if one exists.

        if (Test-Path $zipDatabase) {

            $useOld = Read-Host "Use the existing ZIP database anyway? [Y/n]"

            if (
                $useOld -eq "" -or
                $useOld -match "^[Yy]$"
            ) {

                return $true
            }
        }

        return $false
    }
}


# ------------------------------------------------------------
# Get coordinates from local ZIP database
# ------------------------------------------------------------

function Get-ZipCoordinates {
    param (
        [Parameter(Mandatory)]
        [string]$ZipCode
    )

    if (-not (Ensure-ZipDatabase)) {

        throw "The ZIP coordinate database is unavailable."
    }

    try {

        $record = Import-Csv `
            -Path $zipDatabase |
            Where-Object {
                $_.ZIP -eq $ZipCode
            } |
            Select-Object -First 1
    }
    catch {

        throw "Unable to read the ZIP coordinate database. $($_.Exception.Message)"
    }

    if (-not $record) {

        throw "ZIP code '$ZipCode' was not found in the local ZIP database."
    }

    return [PSCustomObject]@{
        Latitude  = [double]$record.Latitude
        Longitude = [double]$record.Longitude
    }
}