<#
.SYNOPSIS
    Run Velociraptor manually to see startup errors
#>

$serverPath = "C:\Program Files\Velociraptor Server"
$configPath = Join-Path $serverPath "server.config.yaml"
$serverExe = Join-Path $serverPath "velociraptor.exe"

Write-Host "=== Testing Velociraptor Manual Execution ===" -ForegroundColor Cyan
Write-Host ""

# Stop service if running
Write-Host "Stopping service..." -ForegroundColor Yellow
Stop-Service -Name "Velociraptor" -Force -ErrorAction SilentlyContinue
Get-Process -Name "velociraptor" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Check config file
Write-Host "Validating config file..." -ForegroundColor Yellow
Push-Location $serverPath
try {
    $validateOutput = & $serverExe --config server.config.yaml config show 2>&1
    $validateExit = $LASTEXITCODE
    
    if ($validateExit -eq 0) {
        Write-Host "[OK] Config file is valid" -ForegroundColor Green
    }
    else {
        Write-Host "[X] Config file has errors:" -ForegroundColor Red
        $validateOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        Pop-Location
        exit 1
    }
}
catch {
    Write-Host "[X] Error validating config: $($_.Exception.Message)" -ForegroundColor Red
    Pop-Location
    exit 1
}

# Run manually and capture output
Write-Host ""
Write-Host "Running Velociraptor manually (will run for 10 seconds)..." -ForegroundColor Yellow
Write-Host "Watch for any errors:" -ForegroundColor Gray
Write-Host ""

$stdoutFile = Join-Path $serverPath "test_stdout.txt"
$stderrFile = Join-Path $serverPath "test_stderr.txt"

# Remove old test files
Remove-Item $stdoutFile -ErrorAction SilentlyContinue
Remove-Item $stderrFile -ErrorAction SilentlyContinue

try {
    $process = Start-Process -FilePath $serverExe -ArgumentList "--config", "server.config.yaml", "service", "run" -NoNewWindow -PassThru -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
    
    Write-Host "Process started: PID $($process.Id)" -ForegroundColor Green
    Write-Host "Waiting 10 seconds to see startup output..." -ForegroundColor Gray
    Write-Host ""
    
    # Wait and show output in real-time
    for ($i = 1; $i -le 10; $i++) {
        Start-Sleep -Seconds 1
        
        # Check if process is still running
        if ($process.HasExited) {
            Write-Host "Process exited with code: $($process.ExitCode)" -ForegroundColor $(if ($process.ExitCode -eq 0) { 'Green' } else { 'Red' })
            break
        }
        
        # Show any new output
        if (Test-Path $stdoutFile) {
            $allLines = Get-Content $stdoutFile -ErrorAction SilentlyContinue
            if ($allLines) {
                $skipCount = if ($script:lastStdoutLines) { $script:lastStdoutLines } else { 0 }
                if ($allLines.Count -gt $skipCount) {
                    $newLines = $allLines | Select-Object -Skip $skipCount
                    $newLines | ForEach-Object { Write-Host "  [STDOUT] $_" -ForegroundColor Gray }
                    $script:lastStdoutLines = $allLines.Count
                }
            }
        }
        
        if (Test-Path $stderrFile) {
            $allLines = Get-Content $stderrFile -ErrorAction SilentlyContinue
            if ($allLines) {
                $skipCount = if ($script:lastStderrLines) { $script:lastStderrLines } else { 0 }
                if ($allLines.Count -gt $skipCount) {
                    $newLines = $allLines | Select-Object -Skip $skipCount
                    $newLines | ForEach-Object { Write-Host "  [STDERR] $_" -ForegroundColor Red }
                    $script:lastStderrLines = $allLines.Count
                }
            }
        }
        
        # Check ports
        $port8889 = netstat -ano | findstr ":8889" | findstr "LISTENING"
        $port8000 = netstat -ano | findstr ":8000" | findstr "LISTENING"
        
        if ($port8889 -or $port8000) {
            Write-Host ""
            Write-Host "[SUCCESS] Ports are now listening!" -ForegroundColor Green
            if ($port8889) { Write-Host "  Port 8889: LISTENING" -ForegroundColor Green }
            if ($port8000) { Write-Host "  Port 8000: LISTENING" -ForegroundColor Green }
            break
        }
    }
    
    # Stop the process
    if (-not $process.HasExited) {
        Write-Host ""
        Write-Host "Stopping test process..." -ForegroundColor Yellow
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    
    # Show final output
    Write-Host ""
    Write-Host "=== Final Output ===" -ForegroundColor Cyan
    
    if (Test-Path $stdoutFile) {
        $stdout = Get-Content $stdoutFile -ErrorAction SilentlyContinue
        if ($stdout) {
            Write-Host "STDOUT:" -ForegroundColor Yellow
            $stdout | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        }
    }
    
    if (Test-Path $stderrFile) {
        $stderr = Get-Content $stderrFile -ErrorAction SilentlyContinue
        if ($stderr) {
            Write-Host "STDERR:" -ForegroundColor Red
            $stderr | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        }
    }
    
    # Cleanup
    Remove-Item $stdoutFile -ErrorAction SilentlyContinue
    Remove-Item $stderrFile -ErrorAction SilentlyContinue
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "=== Test Complete ===" -ForegroundColor Cyan

