param(
  [Parameter(Mandatory = $true)]
  [string]$CrateDir,
  [Parameter(Mandatory = $true)]
  [string]$OutputDir,
  [ValidateSet("debug", "release")]
  [string]$Profile = "debug",
  [ValidateSet("windows", "linux", "macos")]
  [string]$Platform = "windows"
)

$ErrorActionPreference = "Stop"

function Enable-SccacheIfAvailable {
  $sccache = Get-Command sccache -ErrorAction SilentlyContinue
  if (-not $sccache) {
    return
  }
  Set-Item -Path Env:RUSTC_WRAPPER -Value "sccache"
  try {
    & sccache --start-server *> $null
  } catch {
    # Keep normal build path if cache daemon fails.
  }
  Write-Host "Using sccache for Rust compilation."
}

function Configure-ParallelJobs {
  $logicalCores = [Environment]::ProcessorCount
  if ($logicalCores -lt 2) {
    return
  }
  $jobs = [Math]::Max(1, $logicalCores - 1)
  Set-Item -Path Env:CARGO_BUILD_JOBS -Value "$jobs"
}

function Resolve-CargoExecutable([string]$crateDir) {
  $cargoCommand = Get-Command cargo -ErrorAction SilentlyContinue
  if ($cargoCommand) {
    return $cargoCommand.Source
  }

  $localToolchainDir = Join-Path $crateDir ".rustup-local/toolchains"
  if (Test-Path $localToolchainDir) {
    $localCandidates = @(
      Get-ChildItem -Path $localToolchainDir -Directory |
        ForEach-Object { Join-Path $_.FullName "bin/cargo.exe" } |
        Where-Object { Test-Path $_ }
    )
    if ($localCandidates.Count -gt 0) {
      return $localCandidates[0]
    }
  }

  return $null
}

function Get-LatestRustInputTimestamp([string]$crateDir) {
  $tracked = @()
  $manifest = Join-Path $crateDir "Cargo.toml"
  $lockfile = Join-Path $crateDir "Cargo.lock"
  $sourceDir = Join-Path $crateDir "src"
  $cargoConfigDir = Join-Path $crateDir ".cargo"
  $scriptsDir = Join-Path $crateDir "scripts"

  if (Test-Path $manifest) {
    $tracked += Get-Item $manifest
  }
  if (Test-Path $lockfile) {
    $tracked += Get-Item $lockfile
  }
  if (Test-Path $sourceDir) {
    $tracked += Get-ChildItem -Path $sourceDir -Recurse -File -Filter *.rs
  }
  if (Test-Path $cargoConfigDir) {
    $tracked += Get-ChildItem -Path $cargoConfigDir -Recurse -File
  }
  if (Test-Path $scriptsDir) {
    $tracked += Get-ChildItem -Path $scriptsDir -Recurse -File
  }

  if ($tracked.Count -eq 0) {
    return [DateTime]::UtcNow
  }
  return ($tracked | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
}

function Resolve-ArtifactName([string]$platform) {
  switch ($platform) {
    "windows" { return "Polarmote_native_core.dll" }
    "linux" { return "libPolarmote_native_core.so" }
    "macos" { return "libPolarmote_native_core.dylib" }
    default { throw "Unsupported platform: $platform" }
  }
}

if (-not (Test-Path $CrateDir)) {
  throw "Crate directory not found: $CrateDir"
}

$cargoExecutable = Resolve-CargoExecutable $CrateDir
if (-not $cargoExecutable) {
  throw "Rust toolchain is required but cargo was not found in PATH."
}
Write-Host "Using cargo: $cargoExecutable"
$cargoBinDir = Split-Path -Parent $cargoExecutable
if ($cargoBinDir -and (Test-Path $cargoBinDir)) {
  if (-not $env:PATH.ToLower().Contains($cargoBinDir.ToLower())) {
    $env:PATH = "$cargoBinDir;$env:PATH"
  }
  $rustcPath = Join-Path $cargoBinDir "rustc.exe"
  if (Test-Path $rustcPath) {
    Set-Item -Path Env:RUSTC -Value $rustcPath
  }
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
Set-Item -Path Env:CARGO_INCREMENTAL -Value "1"
Enable-SccacheIfAvailable
Configure-ParallelJobs

$artifactName = Resolve-ArtifactName $Platform
$sourceArtifact = Join-Path $CrateDir "target/$Profile/$artifactName"
$outputArtifact = Join-Path $OutputDir $artifactName
$latestInputTimestamp = Get-LatestRustInputTimestamp $CrateDir
$buildId = ([DateTimeOffset]$latestInputTimestamp).ToUnixTimeSeconds().ToString()
Set-Item -Path Env:Polarmote_BUILD_ID -Value $buildId
Set-Item -Path Env:Polarmote_BUILD_PROFILE -Value $Profile

$needsBuild = $true
if (Test-Path $sourceArtifact) {
  $artifactTime = (Get-Item $sourceArtifact).LastWriteTimeUtc
  $needsBuild = $artifactTime -lt $latestInputTimestamp
}

if ($needsBuild) {
  Write-Host "Building Rust desktop core ($Platform/$Profile)..."
  if ($Profile -eq "release") {
    & $cargoExecutable build --manifest-path (Join-Path $CrateDir "Cargo.toml") --release
  } else {
    & $cargoExecutable build --manifest-path (Join-Path $CrateDir "Cargo.toml")
  }
} else {
  Write-Host "Skipping Rust desktop build ($Platform/$Profile): artifact is up to date."
}

if (-not (Test-Path $sourceArtifact)) {
  throw "Rust desktop artifact not found: $sourceArtifact"
}

$needsCopy = -not (Test-Path $outputArtifact)
if (-not $needsCopy) {
  $sourceTime = (Get-Item $sourceArtifact).LastWriteTimeUtc
  $targetTime = (Get-Item $outputArtifact).LastWriteTimeUtc
  $needsCopy = $sourceTime -gt $targetTime
}

if ($needsCopy) {
  Copy-Item $sourceArtifact $outputArtifact -Force
}

Write-Host "Rust desktop library prepared: $outputArtifact"
