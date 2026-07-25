[CmdletBinding()]
param(
    [string]$WowPath
)

$ErrorActionPreference = "Stop"

$addonName = "RunestoneTracker"
$sourceDir = $PSScriptRoot

if (-not (Test-Path (Join-Path $sourceDir "RunestoneTracker.toc")) -or
    -not (Test-Path (Join-Path $sourceDir "RunestoneTracker.lua"))) {
    throw "Run this script from the RunestoneTracker repository folder."
}

function Get-RetailFolder {
    param([string]$ExplicitWowPath)

    if ($ExplicitWowPath) {
        $resolved = $ExplicitWowPath
        if ((Split-Path $resolved -Leaf) -ne "_retail_") {
            $resolved = Join-Path $resolved "_retail_"
        }

        if (-not (Test-Path $resolved)) {
            throw "Retail folder not found: $resolved"
        }

        return (Resolve-Path $resolved).Path
    }

    $relativeCandidates = @(
        "World of Warcraft\_retail_",
        "Games\World of Warcraft\_retail_",
        "Program Files (x86)\World of Warcraft\_retail_",
        "Program Files\World of Warcraft\_retail_"
    )

    $candidates = foreach ($drive in Get-PSDrive -PSProvider FileSystem) {
        foreach ($relativePath in $relativeCandidates) {
            $candidate = Join-Path $drive.Root $relativePath
            if (Test-Path $candidate) {
                (Resolve-Path $candidate).Path
            }
        }
    }

    $candidates = @($candidates | Sort-Object -Unique)

    if ($candidates.Count -eq 0) {
        throw "World of Warcraft Retail was not found on any mounted drive. Re-run with: .\Install.ps1 -WowPath 'E:\World of Warcraft'"
    }

    if ($candidates.Count -eq 1) {
        return $candidates[0]
    }

    Write-Host "Multiple Retail installations were found:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $candidates.Count; $i++) {
        Write-Host "[$($i + 1)] $($candidates[$i])"
    }

    do {
        $selection = Read-Host "Choose an installation (1-$($candidates.Count))"
        $index = 0
        $valid = [int]::TryParse($selection, [ref]$index) -and $index -ge 1 -and $index -le $candidates.Count
    } until ($valid)

    return $candidates[$index - 1]
}

$retailDir = Get-RetailFolder -ExplicitWowPath $WowPath
$addonsDir = Join-Path $retailDir "Interface\AddOns"
$destination = Join-Path $addonsDir $addonName

New-Item -ItemType Directory -Path $destination -Force | Out-Null

Copy-Item (Join-Path $sourceDir "RunestoneTracker.toc") $destination -Force
Copy-Item (Join-Path $sourceDir "RunestoneTracker.lua") $destination -Force

Write-Host "Installed $addonName to:" -ForegroundColor Green
Write-Host $destination
Write-Host "Restart World of Warcraft or run /reload if the addon was already installed."
