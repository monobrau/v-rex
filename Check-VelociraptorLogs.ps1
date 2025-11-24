<#
.SYNOPSIS
    Check Velociraptor service logs and try manual execution
#>

$serverPath = "C:\Program Files\Velociraptor Server"
$configPath = Join-Path $serverPath "server.config.yaml"
$logPath = Join-Path $serverPath "Logs"

Write-Host "=== Checking Velociraptor Logs ===" -ForegroundColor Cyan
Write-Host ""

# Check for log directory
if (Test-Path $logPath) {
    Write-Host "Log directory exists: $logPath" -ForegroundColor Green
    $logFiles = Get-ChildItem -Path $logPath -Filter "*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    if ($logFiles) {
        Write-Host "Found $($logFiles.Count) log file(s):" -ForegroundColor Green
        foreach ($log in $logFiles | Select-Object -First 5) {
            Write-Host "  - $($log.Name) (Last modified: $($log.LastWriteTime))" -ForegroundColor Gray
            Write-Host "    Last 10 lines:" -ForegroundColor Yellow
            Get-Content $log.FullName -Tail 10 -ErrorAction SilentlyContinue | ForEach-Object {
                Write-Host "      $_" -ForegroundColor $(if ($_ -match 'error|Error|ERROR|failed|Failed|FAILED') { 'Red' } else { 'Gray' })
            }
            Write-Host ""
        }
    }
    else {
        Write-Host "No log files found in $logPath" -ForegroundColor Yellow
    }
}
else {
    Write-Host "Log directory not found: $logPath" -ForegroundColor Yellow
}

# Check Windows Event Log
Write-Host "=== Windows Event Log (Last 20 entries) ===" -ForegroundColor Cyan
Write-Host ""
$events = Get-EventLog -LogName Application -Source "*Velociraptor*" -Newest 20 -ErrorAction SilentlyContinue
if ($events) {
    $events | ForEach-Object {
        $color = if ($_.EntryType -eq 'Error') { 'Red' } elseif ($_.EntryType -eq 'Warning') { 'Yellow' } else { 'Green' }
        Write-Host "[$($_.TimeGenerated)] $($_.EntryType): $($_.Message)" -ForegroundColor $color
    }
}
else {
    Write-Host "No Velociraptor events found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Testing Manual Execution ===" -ForegroundColor Cyan
Write-Host ""

# Stop the service first
Write-Host "Stopping service..." -ForegroundColor Yellow
Stop-Service -Name "Velociraptor" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Try running manually to see errors
Write-Host "Attempting to run velociraptor manually (will timeout after 5 seconds)..." -ForegroundColor Yellow
Write-Host "This will show any startup errors:" -ForegroundColor Gray
Write-Host ""

Push-Location $serverPath
try {
    $process = Start-Process -FilePath ".\velociraptor.exe" -ArgumentList "--config", "server.config.yaml", "service", "run" -NoNewWindow -PassThru -RedirectStandardOutput "test_output.txt" -RedirectStandardError "test_error.txt"
    
    # Wait a few seconds
    Start-Sleep -Seconds 5
    
    # Check if it's still running
    if (-not $process.HasExited) {
        Write-Host "Process is still running (good sign)" -ForegroundColor Green
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    else {
        Write-Host "Process exited with code: $($process.ExitCode)" -ForegroundColor $(if ($process.ExitCode -eq 0) { 'Green' } else { 'Red' })
    }
    
    # Show output
    if (Test-Path "test_output.txt") {
        Write-Host ""
        Write-Host "Standard Output:" -ForegroundColor Cyan
        Get-Content "test_output.txt" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        Remove-Item "test_output.txt" -ErrorAction SilentlyContinue
    }
    
    if (Test-Path "test_error.txt") {
        Write-Host ""
        Write-Host "Standard Error:" -ForegroundColor Red
        Get-Content "test_error.txt" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        Remove-Item "test_error.txt" -ErrorAction SilentlyContinue
    }
}
catch {
    Write-Host "Error running manually: $($_.Exception.Message)" -ForegroundColor Red
}
finally {
    Pop-Location
    
    # Restart the service
    Write-Host ""
    Write-Host "Restarting service..." -ForegroundColor Yellow
    Start-Service -Name "Velociraptor" -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "=== Check Complete ===" -ForegroundColor Cyan

