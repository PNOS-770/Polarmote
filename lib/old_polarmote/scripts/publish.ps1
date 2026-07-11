param(
  [Parameter(Mandatory = $false)]
  [string]$Version,
  [switch]$WindowsOnly,
  [switch]$AndroidOnly,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
Set-Location $RepoRoot

# ---- helpers ----
function Log($msg) { Write-Host "[publish] $msg" -ForegroundColor Cyan }

function Die($msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# ---- check gh ----
$ghAvailable = (Get-Command 'gh' -ErrorAction SilentlyContinue) -ne $null
if (-not $ghAvailable -and -not $DryRun) {
  Write-Host "gh CLI not found. Install it:" -ForegroundColor Yellow
  Write-Host "  winget install GitHub.cli" -ForegroundColor White
  Write-Host "  # or: https://cli.github.com/" -ForegroundColor White
  exit 1
}
if ($ghAvailable) {
  $ghUser = gh api user --jq '.login' 2>$null
  if (-not $ghUser) {
    if (-not $DryRun) { Die "Not logged into GitHub. Run: gh auth login" }
    $ghUser = "(unknown)"
  }
  Log "Authenticated as $ghUser"
}

# ---- resolve version ----
if (-not $Version) {
  $yaml = Get-Content pubspec.yaml -Raw
  if ($yaml -match 'version:\s*([\d\.\+]+)') {
    $Version = $Matches[1]
  } else {
    Die "Could not parse version from pubspec.yaml"
  }
}
$Tag = "v$Version"
Log "Version: $Version   Tag: $Tag"

# ---- check tag does not exist yet ----
if ($ghAvailable -and -not $DryRun) {
  $tagExists = gh release view $Tag --json tagName --jq '.tagName' 2>$null
  if ($tagExists) {
    Die "Release $Tag already exists. Bump version in pubspec.yaml or use -Version"
  }
}

# ---- artifacts ----
$Artifacts = @()

# ---- build Android ----
if (-not $WindowsOnly) {
  Log "Building Android APK..."
  $apk = "Asmote-android.apk"
  if ($DryRun) {
    Log "[DRY-RUN] flutter build apk --release --no-tree-shake-icons"
  } else {
    flutter build apk --release --no-tree-shake-icons
    Copy-Item "build/app/outputs/flutter-apk/app-release.apk" $apk
    Log "Android APK: $apk"
  }
  $Artifacts += $apk
}

# ---- build Windows ----
if (-not $AndroidOnly) {
  Log "Building Windows app..."
  $zip = "Asmote-windows.zip"
  if ($DryRun) {
    Log "[DRY-RUN] flutter build windows --release"
    Log "[DRY-RUN] Compress-Archive ..."
  } else {
    flutter build windows --release
    Compress-Archive -Path "build/windows/x64/runner/Release/*" -DestinationPath $zip
    Log "Windows zip: $zip"
  }
  $Artifacts += $zip
}

# ---- release ----
if ($Artifacts.Count -eq 0) {
  Die "No artifacts to upload"
}
if ($DryRun) {
  Log "[DRY-RUN] gh release create $Tag $($Artifacts -join ' ') --generate-notes"
  Log "[DRY-RUN] Done (dry-run)"
  return
}

Log "Creating release $Tag ..."
gh release create $Tag $Artifacts --generate-notes

Log "Done! https://github.com/$ghUser/Asmote/releases/tag/$Tag"

# ---- cleanup local artifacts ----
foreach ($a in $Artifacts) {
  Remove-Item $a -Force
}
