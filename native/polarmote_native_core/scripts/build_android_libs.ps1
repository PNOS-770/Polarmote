param(
  [Parameter(Mandatory = $true)]
  [string]$CrateDir,
  [Parameter(Mandatory = $true)]
  [string]$OutputDir,
  [Parameter(Mandatory = $true)]
  [string]$NdkDir,
  [ValidateSet("debug", "release")]
  [string]$Profile = "debug",
  [int]$ApiLevel = 21,
  [string]$Abis = ""
)

$ErrorActionPreference = "Stop"

function Has-NonAscii([string]$value) {
  return $value -match "[^\u0000-\u007F]"
}

function Ensure-AsciiRustToolchain([string]$crateDir, [string]$rustupExecutable) {
  $currentSysroot = ""
  try {
    $currentSysroot = (& rustc --print sysroot 2>$null | Select-Object -First 1)
  } catch {
    $currentSysroot = ""
  }

  if ([string]::IsNullOrWhiteSpace($currentSysroot)) {
    return
  }
  if (-not (Has-NonAscii $currentSysroot)) {
    return
  }

  $localRustupHome = Join-Path $crateDir ".rustup-local"
  $localCargoHome = Join-Path $crateDir ".cargo-local"
  $localCargoBin = Join-Path $localCargoHome "bin"
  New-Item -ItemType Directory -Path $localRustupHome -Force | Out-Null
  New-Item -ItemType Directory -Path $localCargoHome -Force | Out-Null
  New-Item -ItemType Directory -Path $localCargoBin -Force | Out-Null

  Set-Item -Path Env:RUSTUP_HOME -Value $localRustupHome
  Set-Item -Path Env:CARGO_HOME -Value $localCargoHome
  $env:Path = "$localCargoBin;$env:Path"

  if ([string]::IsNullOrWhiteSpace($rustupExecutable)) {
    throw "Rust sysroot path contains non-ASCII characters and rustup is unavailable. Install rustup or ensure an ASCII sysroot."
  }

  $toolchain = "stable-x86_64-pc-windows-msvc"
  & $rustupExecutable toolchain install $toolchain --profile minimal
  & $rustupExecutable default $toolchain

  $newSysroot = (& rustc --print sysroot 2>$null | Select-Object -First 1)
  if ([string]::IsNullOrWhiteSpace($newSysroot) -or (Has-NonAscii $newSysroot)) {
    throw "Failed to switch rust toolchain to ASCII path. Current sysroot: $newSysroot"
  }
  Write-Host "Using local ASCII rustup home: $localRustupHome"
}

function Ensure-PerlAvailable {
  $perlShimDir = Join-Path $PSScriptRoot "perl_lib"

  function Test-PerlForOpenSsl([string]$perlPath) {
    try {
      & $perlPath -MLocale::Maketext::Simple -MExtUtils::MakeMaker -e "exit((`$^O eq 'MSWin32') ? 9 : 0)" *> $null
      return $LASTEXITCODE -eq 0
    } catch {
      return $false
    }
  }

  function Enable-PerlShim([string]$perlPath) {
    if (-not (Test-Path (Join-Path $perlShimDir "Locale/Maketext/Simple.pm"))) {
      return $false
    }
    $existing = [Environment]::GetEnvironmentVariable("PERL5LIB")
    if ([string]::IsNullOrWhiteSpace($existing)) {
      Set-Item -Path Env:PERL5LIB -Value $perlShimDir
    } else {
      Set-Item -Path Env:PERL5LIB -Value "$perlShimDir;$existing"
    }
    if (Test-PerlForOpenSsl $perlPath) {
      Write-Host "Perl Locale::Maketext::Simple shim enabled: $perlShimDir"
      return $true
    }
    return $false
  }

  $resolved = Get-Command perl -ErrorAction SilentlyContinue
  if ($resolved) {
    if (Test-PerlForOpenSsl $resolved.Source) {
      return
    }
    if (Enable-PerlShim $resolved.Source) {
      return
    }
  }

  $candidates = @(
    "$env:ProgramFiles\Git\usr\bin\perl.exe",
    "$env:ProgramFiles\Git\mingw64\bin\perl.exe",
    "$env:ProgramFiles\Git\mingw32\bin\perl.exe",
    "$env:ProgramFiles(x86)\Git\usr\bin\perl.exe",
    "$env:ProgramFiles(x86)\Git\mingw64\bin\perl.exe",
    "$env:ProgramFiles(x86)\Git\mingw32\bin\perl.exe",
    "C:\Strawberry\perl\bin\perl.exe",
    "C:\Perl64\bin\perl.exe"
  )

  foreach ($candidate in $candidates) {
    if (-not (Test-Path $candidate)) {
      continue
    }
    $perlDir = Split-Path $candidate -Parent
    $env:Path = "$perlDir;$env:Path"
    $resolvedCandidate = Get-Command perl -ErrorAction SilentlyContinue
    if (-not $resolvedCandidate) {
      continue
    }
    if ((Test-PerlForOpenSsl $resolvedCandidate.Source) -or
        (Enable-PerlShim $resolvedCandidate.Source)) {
      Write-Host "Using Perl from: $candidate"
      return
    }
  }

  throw "Perl is required to build vendored OpenSSL for Android. Need non-MSWin32 perl (e.g. Git msys perl) with Locale::Maketext::Simple and ExtUtils::MakeMaker (shim in scripts/perl_lib)."
}

function Ensure-MakeAvailable {
  $resolvedMake = Get-Command make -ErrorAction SilentlyContinue
  if ($resolvedMake) {
    Set-Item -Path Env:MAKE -Value $resolvedMake.Source
    return
  }

  $gmakeCandidates = @(
    "C:\Strawberry\c\bin\gmake.exe",
    "$env:ProgramFiles\Git\usr\bin\make.exe",
    "$env:ProgramFiles(x86)\Git\usr\bin\make.exe"
  )

  foreach ($candidate in $gmakeCandidates) {
    if (-not (Test-Path $candidate)) {
      continue
    }

    $shimDir = Join-Path $env:TEMP "Polarmote-native-tool-shims"
    New-Item -ItemType Directory -Path $shimDir -Force | Out-Null
    $makeBat = Join-Path $shimDir "make.bat"
    $makeCmd = Join-Path $shimDir "make.cmd"
    $makeExe = Join-Path $shimDir "make.exe"
    $escaped = $candidate.Replace('"', '""')
    Set-Content -Path $makeBat -Encoding Ascii -Value "@echo off`r`n`"$escaped`" %*"
    Set-Content -Path $makeCmd -Encoding Ascii -Value "@echo off`r`n`"$escaped`" %*"
    Copy-Item -Path $candidate -Destination $makeExe -Force

    $candidateDir = Split-Path $candidate -Parent
    $env:Path = "$shimDir;$candidateDir;$env:Path"
    $resolvedShim = Get-Command make -ErrorAction SilentlyContinue
    if ($resolvedShim) {
      Set-Item -Path Env:MAKE -Value $resolvedShim.Source
      Write-Host "Using make shim backed by: $candidate"
      return
    }
  }

  throw "make is required to build vendored OpenSSL for Android."
}

function Enable-SccacheIfAvailable {
  $sccache = Get-Command sccache -ErrorAction SilentlyContinue
  if (-not $sccache) {
    return
  }
  Set-Item -Path Env:RUSTC_WRAPPER -Value "sccache"
  try {
    & sccache --start-server *> $null
  } catch {
    # Ignore cache daemon startup failures and keep normal build path.
  }
  Write-Host "Using sccache for Rust compilation."
}

function Configure-ParallelJobs {
  $logicalCores = [Environment]::ProcessorCount
  if ($logicalCores -lt 2) {
    return
  }
  # Keep one core free for Gradle/Flutter side tasks.
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

function Resolve-RustupExecutable([string]$cargoExecutable) {
  $rustupCommand = Get-Command rustup -ErrorAction SilentlyContinue
  if ($rustupCommand) {
    return $rustupCommand.Source
  }

  if ([string]::IsNullOrWhiteSpace($cargoExecutable)) {
    return $null
  }

  $cargoBinDir = Split-Path -Parent $cargoExecutable
  $localRustup = Join-Path $cargoBinDir "rustup.exe"
  if (Test-Path $localRustup) {
    return $localRustup
  }

  return $null
}

function Configure-RustToolchainEnvironment([string]$crateDir) {
  $cargoExecutable = Resolve-CargoExecutable $crateDir
  if (-not $cargoExecutable) {
    throw "Rust toolchain is required but cargo was not found in PATH or .rustup-local."
  }

  $cargoBinDir = Split-Path -Parent $cargoExecutable
  if ($cargoBinDir -and (Test-Path $cargoBinDir)) {
    $pathValue = [string]$env:Path
    if (-not $pathValue.ToLowerInvariant().Contains($cargoBinDir.ToLowerInvariant())) {
      $env:Path = "$cargoBinDir;$env:Path"
    }

    $rustcPath = Join-Path $cargoBinDir "rustc.exe"
    if (Test-Path $rustcPath) {
      Set-Item -Path Env:RUSTC -Value $rustcPath
    }
  }

  $rustupExecutable = Resolve-RustupExecutable $cargoExecutable
  return [PSCustomObject]@{
    CargoExecutable = $cargoExecutable
    RustupExecutable = $rustupExecutable
  }
}

function Resolve-RequestedAbis([string]$raw) {
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return @()
  }
  $parts = $raw.Split(',', [System.StringSplitOptions]::RemoveEmptyEntries)
  $normalized = @()
  foreach ($part in $parts) {
    $abi = $part.Trim()
    if ($abi.Length -eq 0) {
      continue
    }
    $normalized += $abi
  }
  return $normalized
}

function Get-LatestRustInputTimestamp([string]$crateDir, [string]$scriptPath) {
  $tracked = @()
  $manifest = Join-Path $crateDir "Cargo.toml"
  $lockfile = Join-Path $crateDir "Cargo.lock"
  $sourceDir = Join-Path $crateDir "src"
  $cargoConfigDir = Join-Path $crateDir ".cargo"
  $perlLibDir = Join-Path $PSScriptRoot "perl_lib"

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
  if (Test-Path $perlLibDir) {
    $tracked += Get-ChildItem -Path $perlLibDir -Recurse -File
  }
  if (Test-Path $scriptPath) {
    $tracked += Get-Item $scriptPath
  }

  if ($tracked.Count -eq 0) {
    return [DateTime]::UtcNow
  }
  return ($tracked | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
}

function Is-UpToDate([string]$artifactPath, [DateTime]$latestInputTimestamp) {
  if (-not (Test-Path $artifactPath)) {
    return $false
  }
  $artifactTime = (Get-Item $artifactPath).LastWriteTimeUtc
  return $artifactTime -ge $latestInputTimestamp
}

function Test-LocalRustTargetInstalled([string]$crateDir, [string]$triple) {
  $localToolchainDir = Join-Path $crateDir ".rustup-local/toolchains"
  if (-not (Test-Path $localToolchainDir)) {
    return $false
  }

  $candidateLibDirs = @(
    Get-ChildItem -Path $localToolchainDir -Directory |
      ForEach-Object { Join-Path $_.FullName "lib/rustlib/$triple/lib" } |
      Where-Object { Test-Path $_ }
  )
  foreach ($libDir in $candidateLibDirs) {
    $anyFile = Get-ChildItem -Path $libDir -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($anyFile) {
      return $true
    }
  }

  return $false
}

function Ensure-RustTargetInstalled([string]$triple, [string]$rustupExecutable, [string]$crateDir) {
  if ([string]::IsNullOrWhiteSpace($rustupExecutable)) {
    if (Test-LocalRustTargetInstalled $crateDir $triple) {
      Write-Host "Using preinstalled local Rust target: $triple"
      return
    }
    throw "Rust target '$triple' is required but rustup is unavailable and no local stdlib for that target was found."
  }

  $installedTargets = @()
  try {
    $installedTargets = & $rustupExecutable target list --installed 2>$null
  } catch {
    $installedTargets = @()
  }
  if ($LASTEXITCODE -eq 0 -and $installedTargets -contains $triple) {
    return
  }
  & $rustupExecutable target add $triple | Out-Null
}

if (-not (Test-Path $CrateDir)) {
  throw "Crate directory not found: $CrateDir"
}
if (-not (Test-Path $NdkDir)) {
  throw "Android NDK directory not found: $NdkDir"
}

$toolchainInfo = Configure-RustToolchainEnvironment $CrateDir
Ensure-AsciiRustToolchain $CrateDir $toolchainInfo.RustupExecutable
$toolchainInfo = Configure-RustToolchainEnvironment $CrateDir
$cargoExecutable = $toolchainInfo.CargoExecutable
$rustupExecutable = $toolchainInfo.RustupExecutable
Write-Host "Using cargo: $cargoExecutable"
if ($rustupExecutable) {
  Write-Host "Using rustup: $rustupExecutable"
} else {
  Write-Host "rustup not found; using preinstalled local Rust targets."
}

Ensure-PerlAvailable
Ensure-MakeAvailable
Enable-SccacheIfAvailable
Configure-ParallelJobs

$toolchainBin = Join-Path $NdkDir "toolchains/llvm/prebuilt/windows-x86_64/bin"
if (-not (Test-Path $toolchainBin)) {
  throw "Android NDK llvm toolchain not found: $toolchainBin"
}
$clangExe = Join-Path $toolchainBin "clang.exe"
if (-not (Test-Path $clangExe)) {
  throw "Android NDK clang not found: $clangExe"
}
$llvmArExe = Join-Path $toolchainBin "llvm-ar.exe"
if (-not (Test-Path $llvmArExe)) {
  throw "Android NDK llvm-ar not found: $llvmArExe"
}
$clangExeForCc = $clangExe.Replace("\", "/")
$llvmArExeForCc = $llvmArExe.Replace("\", "/")
$env:Path = "$toolchainBin;$env:Path"
$env:CARGO_INCREMENTAL = "1"

$latestInputTimestamp = Get-LatestRustInputTimestamp $CrateDir $PSCommandPath
$buildId = ([DateTimeOffset]$latestInputTimestamp).ToUnixTimeSeconds().ToString()
Set-Item -Path Env:Polarmote_BUILD_ID -Value $buildId
Set-Item -Path Env:Polarmote_BUILD_PROFILE -Value $Profile

$targets = @(
  @{
    Triple = "aarch64-linux-android"
    Abi = "arm64-v8a"
    ClangPrefix = "aarch64-linux-android"
    CargoLinkerEnv = "CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER"
  },
  @{
    Triple = "armv7-linux-androideabi"
    Abi = "armeabi-v7a"
    ClangPrefix = "armv7a-linux-androideabi"
    CargoLinkerEnv = "CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER"
  },
  @{
    Triple = "x86_64-linux-android"
    Abi = "x86_64"
    ClangPrefix = "x86_64-linux-android"
    CargoLinkerEnv = "CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER"
  }
)

$requestedAbis = Resolve-RequestedAbis $Abis
if ($requestedAbis.Count -gt 0) {
  $targets = @($targets | Where-Object { $requestedAbis -contains $_.Abi })
  if ($targets.Count -eq 0) {
    throw "No matching ABI selected from -Abis '$Abis'. Supported: arm64-v8a, armeabi-v7a, x86_64."
  }
  Write-Host "Building selected Android ABIs: $($targets.Abi -join ', ')"
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

foreach ($target in $targets) {
  $triple = $target.Triple
  $abi = $target.Abi
  $clangCommand = "$($target.ClangPrefix)$ApiLevel-clang"
  $clangWrapperName = "$clangCommand.cmd"
  $linker = Join-Path $toolchainBin $clangWrapperName
  if (-not (Test-Path $linker)) {
    throw "Android NDK linker not found: $linker"
  }

  $tripleLowerUnderscore = $triple.Replace("-", "_")
  $ccEnv = "CC_$tripleLowerUnderscore"
  $arEnv = "AR_$tripleLowerUnderscore"
  $cflagsEnv = "CFLAGS_$tripleLowerUnderscore"
  $linkerForEnv = $linker
  $targetFlag = "--target=$($target.ClangPrefix)$ApiLevel"

  Ensure-RustTargetInstalled $triple $rustupExecutable $CrateDir

  $libPath = Join-Path $CrateDir "target/$triple/$Profile/libPolarmote_native_core.so"
  $needsBuild = -not (Is-UpToDate $libPath $latestInputTimestamp)
  if ($needsBuild) {
    Write-Host "Building Rust target $triple ($Profile)..."
  } else {
    Write-Host "Skipping Rust target $triple ($Profile): artifact is up to date."
  }

  if ($needsBuild) {
    # Android cross build must not inherit host OpenSSL settings (e.g. OPENSSL_DIR
    # pointing to Win64 OpenSSL). Let crates build/find target OpenSSL themselves.
    $targetOpenSslPrefix = $triple.Replace("-", "_").ToUpperInvariant()
    $opensslEnvNames = @(
      "OPENSSL_DIR",
      "OPENSSL_LIB_DIR",
      "OPENSSL_INCLUDE_DIR",
      "OPENSSL_LIBS",
      "OPENSSL_STATIC",
      "${targetOpenSslPrefix}_OPENSSL_DIR",
      "${targetOpenSslPrefix}_OPENSSL_LIB_DIR",
      "${targetOpenSslPrefix}_OPENSSL_INCLUDE_DIR",
      "${targetOpenSslPrefix}_OPENSSL_LIBS",
      "${targetOpenSslPrefix}_OPENSSL_STATIC"
    )
    foreach ($opensslEnvName in $opensslEnvNames) {
      Remove-Item "Env:$opensslEnvName" -ErrorAction SilentlyContinue
    }

    Set-Item -Path "Env:$($target.CargoLinkerEnv)" -Value $linkerForEnv
    # Use clang.exe for C build scripts (openssl/libz). Pair with --target to keep
    # cross-compile behavior without relying on .cmd wrappers inside sh.
    Set-Item -Path "Env:$ccEnv" -Value $clangExeForCc
      Set-Item -Path "Env:$arEnv" -Value $llvmArExeForCc
      Set-Item -Path "Env:$cflagsEnv" -Value $targetFlag
      try {
        if ($Profile -eq "release") {
          & $cargoExecutable build --manifest-path (Join-Path $CrateDir "Cargo.toml") --target $triple --release
        } else {
          & $cargoExecutable build --manifest-path (Join-Path $CrateDir "Cargo.toml") --target $triple
        }
      } finally {
        Remove-Item "Env:$($target.CargoLinkerEnv)" -ErrorAction SilentlyContinue
      Remove-Item "Env:$ccEnv" -ErrorAction SilentlyContinue
      Remove-Item "Env:$arEnv" -ErrorAction SilentlyContinue
      Remove-Item "Env:$cflagsEnv" -ErrorAction SilentlyContinue
    }
  }

  if (-not (Test-Path $libPath)) {
    throw "Rust Android artifact not found: $libPath"
  }

  $abiDir = Join-Path $OutputDir $abi
  New-Item -ItemType Directory -Path $abiDir -Force | Out-Null
  $outputLibPath = Join-Path $abiDir "libPolarmote_native_core.so"
  $needsCopy = -not (Test-Path $outputLibPath)
  if (-not $needsCopy) {
    $sourceTime = (Get-Item $libPath).LastWriteTimeUtc
    $targetTime = (Get-Item $outputLibPath).LastWriteTimeUtc
    $needsCopy = $sourceTime -gt $targetTime
  }
  if ($needsCopy) {
    Copy-Item $libPath $outputLibPath -Force
  }
}

Write-Host "Rust Android libraries prepared in: $OutputDir"
