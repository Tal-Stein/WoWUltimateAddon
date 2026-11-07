# Links the repo's Ultimate/ folder into the WoW Forever AddOns folder.
# A directory junction means edits in the repo are live after /reload in game.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/deploy.ps1 [-Copy] [-WowRoot <path>]
param(
    [switch]$Copy,
    [string]$WowRoot = "C:\Program Files (x86)\World of Warcraft\_forever_"
)
$ErrorActionPreference = "Stop"
$source = Join-Path $PSScriptRoot "..\Ultimate" | Resolve-Path
$addons = Join-Path $WowRoot "Interface\AddOns"
$target = Join-Path $addons "Ultimate"

if (-not (Test-Path $addons)) { throw "AddOns folder not found: $addons" }

if (Test-Path $target) {
    $item = Get-Item $target -Force
    if ($item.LinkType -eq "Junction") {
        if ($item.Target -contains $source.Path) { Write-Output "Already linked: $target -> $source"; exit 0 }
        $item.Delete()
    } else {
        Remove-Item $target -Recurse -Force -Confirm:$false
    }
}

if ($Copy) {
    Copy-Item $source $target -Recurse
    Write-Output "Copied $source -> $target"
} else {
    New-Item -ItemType Junction -Path $target -Target $source | Out-Null
    Write-Output "Linked $target -> $source"
}
