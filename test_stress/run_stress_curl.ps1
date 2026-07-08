$hostBase = "http://localhost:9876"
$ErrorActionPreference = "Continue"

# 评分系统
$script:totalTests = 0
$script:passedTests = 0
$script:testMetrics = @()

function Call-Api($method, $path, $jsonBody) {
  if ($jsonBody) {
    return Invoke-RestMethod -Uri "$hostBase$path" -Method $method -Body $jsonBody -ContentType "application/json"
  } else {
    return Invoke-RestMethod -Uri "$hostBase$path" -Method $method
  }
}

function Record-Test($name, $passed, $metrics) {
  $script:totalTests++
  if ($passed) { $script:passedTests++ }
  $script:testMetrics += [PSCustomObject]@{
    Name = $name
    Passed = $passed
    Metrics = $metrics
  }
}

Write-Host "=== Asmote Stress Test ===" -ForegroundColor Cyan

try {
  $s = Call-Api GET "/stats" $null
  Write-Host "Server OK: $($s.stages.Count) stages, $($s.sessions) sessions" -ForegroundColor Green
} catch {
  Write-Host "Cannot reach server. Start the app first." -ForegroundColor Red
  exit 1
}

$initialState = Call-Api GET "/stats" $null
Write-Host ""

# Test 1: Storm (创建+切换+背景，综合压力)
Write-Host "--- Test 1: Storm (50 stages, 2000 switches, 10 bgs) ---" -ForegroundColor Yellow
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
  $r = Call-Api POST "/stage/storm" '{"create":50,"switch":2000,"bg":10}'
  $sw.Stop()
  Write-Host "  Created $($r.stagesCreated), switched $($r.switches), total $($r.totalMs)ms (avg $([math]::Round($r.avgMsPerOp,2))ms)" -ForegroundColor Green
  Record-Test "Storm" $true @{AvgMs=$r.avgMsPerOp; TotalMs=$r.totalMs}
} catch {
  $sw.Stop()
  Write-Host "  FAILED: $_" -ForegroundColor Red
  Record-Test "Storm" $false @{Error=$_}
}
Write-Host ""

# Test 2: Switch storm (极限切换速度)
Write-Host "--- Test 2: Switch storm 5000x ---" -ForegroundColor Yellow
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
  $r = Call-Api POST "/stage/switch-storm" '{"count":5000}'
  $sw.Stop()
  Write-Host "  Switched $($r.switches) in $($r.totalMs)ms (avg $([math]::Round($r.avgMs,3))ms)" -ForegroundColor Green
  Record-Test "Switch storm" $true @{AvgMs=$r.avgMs; TotalMs=$r.totalMs}
} catch {
  $sw.Stop()
  Write-Host "  FAILED: $_" -ForegroundColor Red
  Record-Test "Switch storm" $false @{Error=$_}
}
Write-Host ""

# Test 3: Bulk create (批量创建)
Write-Host "--- Test 3: Create 100 stages ---" -ForegroundColor Yellow
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
  $r = Call-Api POST "/stage/create" '{"count":100,"name":"Bulk"}'
  $sw.Stop()
  Write-Host "  Created $($r.created) stages in $($sw.ElapsedMilliseconds)ms" -ForegroundColor Green
  Record-Test "Bulk create" $true @{Count=$r.created; Ms=$sw.ElapsedMilliseconds}
} catch {
  $sw.Stop()
  Write-Host "  FAILED: $_" -ForegroundColor Red
  Record-Test "Bulk create" $false @{Error=$_}
}
Write-Host ""

# Test 4: Background update storm (全量背景更新)
Write-Host "--- Test 4: Set backgrounds on all stages ---" -ForegroundColor Yellow
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
  $s = Call-Api GET "/stats" $null
  $n = $s.stages.Count
  $idx = 0
  while ($idx -lt $n) {
    $bgId = ""
    if ($idx % 3 -eq 0) { $bgId = "bg-1" }
    elseif ($idx % 3 -eq 1) { $bgId = "bg-2" }
    $body = '{"index":' + $idx + ',"bgId":"' + $bgId + '"}'
    $null = Call-Api POST "/stage/set-bg" $body
    $idx += 1
  }
  $sw.Stop()
  Write-Host "  Set backgrounds on $n stages in $($sw.ElapsedMilliseconds)ms" -ForegroundColor Green
  Record-Test "Background update" $true @{Count=$n; Ms=$sw.ElapsedMilliseconds}
} catch {
  $sw.Stop()
  Write-Host "  FAILED: $_" -ForegroundColor Red
  Record-Test "Background update" $false @{Error=$_}
}
Write-Host ""

# Test 5: Traverse storm (全量遍历 x 5 轮)
Write-Host "--- Test 5: Traverse all stages x 5 rounds ---" -ForegroundColor Yellow
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
  $s = Call-Api GET "/stats" $null
  $n = $s.stages.Count
  $totalSwitches = 0
  $round = 1
  while ($round -le 5) {
    $idx = 0
    while ($idx -lt $n) {
      $body = '{"index":' + $idx + '}'
      $null = Call-Api POST "/stage/switch" $body
      $idx += 1
      $totalSwitches += 1
    }
    Write-Host "  Round $round done ($n switches)"
    $round += 1
  }
  $sw.Stop()
  Write-Host "  Total $totalSwitches switches in $($sw.ElapsedMilliseconds)ms" -ForegroundColor Green
  Record-Test "Traverse storm" $true @{Switches=$totalSwitches; Ms=$sw.ElapsedMilliseconds}
} catch {
  $sw.Stop()
  Write-Host "  FAILED: $_" -ForegroundColor Red
  Record-Test "Traverse storm" $false @{Error=$_}
}
Write-Host ""

# Test 6: Session write storm (大量数据写入)
Write-Host "--- Test 6: Session write storm ---" -ForegroundColor Yellow
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
  $s = Call-Api GET "/stats" $null
  if ($s.sessions -gt 0) {
    $iterations = 100
    $i = 0
    while ($i -lt $iterations) {
      $text = "x" * 200 + "`n"
      $null = Call-Api POST "/session/write-all" ('{"text":"' + $text + '"}')
      $i++
    }
    $sw.Stop()
    Write-Host "  Wrote $iterations * 200 chars to all sessions in $($sw.ElapsedMilliseconds)ms" -ForegroundColor Green
    Record-Test "Session write" $true @{Iterations=$iterations; Ms=$sw.ElapsedMilliseconds}
  } else {
    $sw.Stop()
    Write-Host "  SKIPPED: no sessions" -ForegroundColor Yellow
    Record-Test "Session write" $false @{Skipped=$true}
  }
} catch {
  $sw.Stop()
  Write-Host "  FAILED: $_" -ForegroundColor Red
  Record-Test "Session write" $false @{Error=$_}
}
Write-Host ""

# Test 7: Marathon (真实会话压力 + 长时耐力，20 个 stage，60 秒)
Write-Host "--- Test 7: Marathon (20 stages, 60s) ---" -ForegroundColor Yellow
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
  Write-Host "  Starting marathon in background..." -ForegroundColor Gray
  $r = Call-Api POST "/stress/marathon" '{"stages":20,"duration":60}'
  if ($r.status -eq "started") {
    Write-Host "  Status: $($r.status), stages: $($r.stages), duration: $($r.durationSec)s, hosts: $($r.hosts)" -ForegroundColor Green
    
    $elapsed = 0
    $checkInterval = 3
    while ($elapsed -lt $r.durationSec) {
      Start-Sleep -Seconds $checkInterval
      $elapsed += $checkInterval
      try {
        $status = Call-Api GET "/stress/marathon/status" $null
        if (-not $status.running) {
          Write-Host "  Marathon finished early at ~${elapsed}s" -ForegroundColor Yellow
          break
        }
        $progress = [math]::Round(($elapsed / $r.durationSec) * 100)
        Write-Host "  Marathon running... ${elapsed}s / $($r.durationSec)s ($progress%)" -ForegroundColor Gray
      } catch {
        Write-Host "  Status check failed: $_" -ForegroundColor Red
        break
      }
    }
    $sw.Stop()
    Write-Host "  Marathon done in $($sw.ElapsedMilliseconds)ms" -ForegroundColor Green
    
    # 等待清理完成
    Write-Host "  Waiting for cleanup..." -ForegroundColor Gray
    Start-Sleep -Seconds 3
    
    Record-Test "Marathon" $true @{DurationSec=$r.durationSec; ActualMs=$sw.ElapsedMilliseconds}
  } else {
    $sw.Stop()
    Write-Host "  FAILED: $($r.error)" -ForegroundColor Red
    Record-Test "Marathon" $false @{Error=$r.error}
  }
} catch {
  $sw.Stop()
  Write-Host "  FAILED: $_" -ForegroundColor Red
  Record-Test "Marathon" $false @{Error=$_}
}
Write-Host ""

# Final state
Write-Host "--- Final state ---" -ForegroundColor Cyan
$finalState = Call-Api GET "/stats" $null
Write-Host "  Stages: $($finalState.stages.Count), Sessions: $($finalState.sessions), Backgrounds: $($finalState.backgroundImages)"
Write-Host ""

# 评分系统
Write-Host "=== Test Results & Score ===" -ForegroundColor Cyan
Write-Host ""

$score = 0
$maxScore = 100

# 1. 通过率 (40 分)
$passRate = $script:passedTests / $script:totalTests
$passScore = [math]::Round($passRate * 40)
$score += $passScore
Write-Host "Pass Rate: $script:passedTests / $script:totalTests ($([math]::Round($passRate*100))%) -> $passScore / 40" -ForegroundColor $(if ($passRate -ge 0.8) {"Green"} elseif ($passRate -ge 0.5) {"Yellow"} else {"Red"})

# 2. 性能评分 (30 分)
$perfScore = 0
foreach ($test in $script:testMetrics) {
  if ($test.Passed -and $test.Metrics.AvgMs) {
    $avgMs = $test.Metrics.AvgMs
    if ($avgMs -lt 0.05) { $perfScore += 6 }
    elseif ($avgMs -lt 0.1) { $perfScore += 5 }
    elseif ($avgMs -lt 0.5) { $perfScore += 4 }
    elseif ($avgMs -lt 1) { $perfScore += 3 }
    else { $perfScore += 1 }
  }
}
$perfScore = [math]::Min($perfScore, 30)
$score += $perfScore
Write-Host "Performance: $perfScore / 30" -ForegroundColor $(if ($perfScore -ge 24) {"Green"} elseif ($perfScore -ge 15) {"Yellow"} else {"Red"})

# 3. 稳定性评分 (20 分)
$stabilityScore = 20
foreach ($test in $script:testMetrics) {
  if (-not $test.Passed -and -not $test.Metrics.Skipped) {
    $stabilityScore -= 5
  }
}
$stabilityScore = [math]::Max($stabilityScore, 0)
$score += $stabilityScore
Write-Host "Stability: $stabilityScore / 20" -ForegroundColor $(if ($stabilityScore -ge 16) {"Green"} elseif ($stabilityScore -ge 10) {"Yellow"} else {"Red"})

# 4. 清理完成度 (10 分)
$cleanupScore = 0
if ($finalState.stages.Count -le ($initialState.stages.Count + 5)) {
  $cleanupScore = 10
} elseif ($finalState.stages.Count -le ($initialState.stages.Count + 20)) {
  $cleanupScore = 5
}
$score += $cleanupScore
Write-Host "Cleanup: $cleanupScore / 10 (stages: $($initialState.stages.Count) -> $($finalState.stages.Count))" -ForegroundColor $(if ($cleanupScore -ge 8) {"Green"} elseif ($cleanupScore -ge 5) {"Yellow"} else {"Red"})

Write-Host ""
Write-Host "=== Final Score: $score / $maxScore ===" -ForegroundColor $(if ($score -ge 80) {"Green"} elseif ($score -ge 60) {"Yellow"} else {"Red"})

if ($score -ge 90) {
  Write-Host "Rating: S (Excellent)" -ForegroundColor Green
} elseif ($score -ge 80) {
  Write-Host "Rating: A (Good)" -ForegroundColor Green
} elseif ($score -ge 70) {
  Write-Host "Rating: B (Fair)" -ForegroundColor Yellow
} elseif ($score -ge 60) {
  Write-Host "Rating: C (Pass)" -ForegroundColor Yellow
} else {
  Write-Host "Rating: D (Fail)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Check the app for visual issues (stutter, flicker, errors)." -ForegroundColor Gray
