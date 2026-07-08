# 监控自适应限流状态
param(
  [int]$IntervalSec = 2
)

$baseUrl = "http://localhost:9876"

function Call-Api($Method, $Path, $Body = $null) {
  try {
    $params = @{
      Uri = "$baseUrl$Path"
      Method = $Method
      ContentType = "application/json"
      TimeoutSec = 10
    }
    if ($Body) {
      $params.Body = $Body
    }
    return Invoke-RestMethod @params
  } catch {
    Write-Host "  Error: $_" -ForegroundColor Red
    return $null
  }
}

Write-Host "=== Asmote Adaptive Throttle Monitor ===" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop" -ForegroundColor Gray
Write-Host ""

while ($true) {
  $stats = Call-Api GET "/stats"
  
  if ($null -eq $stats) {
    Write-Host "Failed to fetch stats" -ForegroundColor Red
    Start-Sleep -Seconds $IntervalSec
    continue
  }
  
  Clear-Host
  Write-Host "=== Adaptive Throttle Status ===" -ForegroundColor Cyan
  Write-Host "Time: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
  Write-Host ""
  
  Write-Host "Stages: $($stats.stages.Count), Sessions: $($stats.sessions)" -ForegroundColor White
  Write-Host ""
  
  if ($stats.sessionThrottleStats -and $stats.sessionThrottleStats.Count -gt 0) {
    foreach ($sessionStat in $stats.sessionThrottleStats) {
      $throttle = $sessionStat.throttle
      $level = $throttle.currentLevel
      $flushMs = $throttle.flushIntervalMs
      $bufferKB = $throttle.bufferSizeKB
      
      $color = switch ($level) {
        "normal" { "Green" }
        "moderate" { "Yellow" }
        "high" { "DarkYellow" }
        "critical" { "Red" }
        default { "White" }
      }
      
      Write-Host "Session: $($sessionStat.id.Substring(0, 8))..." -NoNewline
      Write-Host " Level: " -NoNewline
      Write-Host $level.ToUpper() -ForegroundColor $color -NoNewline
      Write-Host " | Flush: ${flushMs}ms | Buffer: ${bufferKB}KB"
      
      if ($throttle.recentEvents -and $throttle.recentEvents.Count -gt 0) {
        $lastEvent = $throttle.recentEvents[-1]
        Write-Host "  Last: $($lastEvent.transition) - $($lastEvent.reason)" -ForegroundColor Gray
      }
    }
  } else {
    Write-Host "No active sessions" -ForegroundColor Gray
  }
  
  Write-Host ""
  Write-Host "Refresh in ${IntervalSec}s..." -ForegroundColor DarkGray
  
  Start-Sleep -Seconds $IntervalSec
}
