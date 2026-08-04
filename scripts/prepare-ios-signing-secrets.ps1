# Encode iOS code-signing materials and print `gh secret set` commands.
# NOT the VoIP push .p12 — use Apple Development / Distribution (Ad Hoc) certificate.
#
# Usage:
#   .\scripts\prepare-ios-signing-secrets.ps1 `
#     -P12Path "C:\path\AppleDistribution.p12" `
#     -P12Password "your-p12-password" `
#     -AppProfilePath "C:\path\HangXun_AdHoc.mobileprovision" `
#     -NseProfilePath "C:\path\HangXun_NSE_AdHoc.mobileprovision" `
#     -TeamId "U7QZA36QT4" `
#     -Apply   # optional: actually upload secrets via gh

param(
    [Parameter(Mandatory = $true)][string]$P12Path,
    [Parameter(Mandatory = $true)][string]$P12Password,
    [Parameter(Mandatory = $true)][string]$AppProfilePath,
    [Parameter(Mandatory = $true)][string]$NseProfilePath,
    [string]$TeamId = "U7QZA36QT4",
    [string]$KeychainPassword = "",
    [string]$Repo = "219889kkk/imapp",
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

function Assert-File([string]$path, [string]$label) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing $label file: $path"
    }
}

Assert-File $P12Path "P12"
Assert-File $AppProfilePath "App provisioning profile"
Assert-File $NseProfilePath "NotificationService provisioning profile"

if ([string]::IsNullOrWhiteSpace($KeychainPassword)) {
    $KeychainPassword = -join ((48..57 + 65..90 + 97..122) | Get-Random -Count 24 | ForEach-Object { [char]$_ })
}

function To-B64([string]$path) {
    [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $path)))
}

$p12B64 = To-B64 $P12Path
$appB64 = To-B64 $AppProfilePath
$nseB64 = To-B64 $NseProfilePath

Write-Host ""
Write-Host "=== Required GitHub Secrets (repo: $Repo) ===" -ForegroundColor Cyan
Write-Host "IOS_P12_BASE64          (from $P12Path)"
Write-Host "IOS_P12_PASSWORD        (your p12 password)"
Write-Host "IOS_PROFILE_APP_BASE64  (top.hangxun.app profile)"
Write-Host "IOS_PROFILE_NSE_BASE64  (top.hangxun.app.NotificationService profile)"
Write-Host "IOS_TEAM_ID             ($TeamId)"
Write-Host "IOS_KEYCHAIN_PASSWORD   (optional CI keychain pass)"
Write-Host ""
Write-Host "Bundle IDs must match profiles:" -ForegroundColor Yellow
Write-Host "  top.hangxun.app"
Write-Host "  top.hangxun.app.NotificationService"
Write-Host "Ad Hoc: add test iPhone UDIDs to both profiles."
Write-Host "Do NOT use VoIP push certificate here."
Write-Host ""

$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    $ghPath = "C:\Program Files\GitHub CLI\gh.exe"
    if (Test-Path $ghPath) { $gh = @{ Source = $ghPath } }
}

if ($Apply) {
    if (-not $gh) { throw "gh CLI not found; install GitHub CLI or run without -Apply and paste secrets manually." }
    $env:GH_PROMPT_DISABLED = "1"
    Write-Host "Uploading secrets with gh..." -ForegroundColor Green
    $p12B64 | & $gh.Source secret set IOS_P12_BASE64 -R $Repo
    $P12Password | & $gh.Source secret set IOS_P12_PASSWORD -R $Repo
    $appB64 | & $gh.Source secret set IOS_PROFILE_APP_BASE64 -R $Repo
    $nseB64 | & $gh.Source secret set IOS_PROFILE_NSE_BASE64 -R $Repo
    $TeamId | & $gh.Source secret set IOS_TEAM_ID -R $Repo
    $KeychainPassword | & $gh.Source secret set IOS_KEYCHAIN_PASSWORD -R $Repo
    Write-Host "Done. Run Actions → iOS Signed (method: ad-hoc or development)." -ForegroundColor Green
} else {
    Write-Host "Dry-run only. Re-run with -Apply to upload, or set secrets in GitHub UI." -ForegroundColor Yellow
    Write-Host "Lengths: P12=$($p12B64.Length) APP=$($appB64.Length) NSE=$($nseB64.Length)"
}
