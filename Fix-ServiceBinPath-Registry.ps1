<#
.SYNOPSIS
    Fix Velociraptor service binPath using registry (most reliable method)
#>

$serviceName = "Velociraptor"
$serverExe = "C:\Program Files\Velociraptor Server\velociraptor.exe"
$configPath = "C:\Program Files\Velociraptor Server\server.config.yaml"
$binPath = "`"$serverExe`" --config `"$configPath`" service run"

Write-Host "=== Fixing Service BinPath via Registry ===" -ForegroundColor Cyan
Write-Host ""

# Stop service first
Write-Host "Stopping service..." -ForegroundColor Yellow
Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
Get-Process -Name "velociraptor" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Update registry directly
Write-Host "Updating registry..." -ForegroundColor Yellow
$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"

if (-not (Test-Path $regPath)) {
    Write-Host "ERROR: Service registry key not found at $regPath" -ForegroundColor Red
    exit 1
}

Write-Host "Current ImagePath:" -ForegroundColor Gray
$currentPath = (Get-ItemProperty -Path $regPath -Name "ImagePath" -ErrorAction SilentlyContinue).ImagePath
Write-Host "  $currentPath" -ForegroundColor Gray

Write-Host ""
Write-Host "Setting new ImagePath:" -ForegroundColor Yellow
Write-Host "  $binPath" -ForegroundColor Gray

try {
    Set-ItemProperty -Path $regPath -Name "ImagePath" -Value $binPath -ErrorAction Stop
    Write-Host "Registry updated successfully!" -ForegroundColor Green
    
    # Verify
    $newPath = (Get-ItemProperty -Path $regPath -Name "ImagePath").ImagePath
    Write-Host ""
    Write-Host "Verified ImagePath:" -ForegroundColor Gray
    Write-Host "  $newPath" -ForegroundColor Gray
    
    if ($newPath -match '--config') {
        Write-Host "[OK] Service now includes --config parameter" -ForegroundColor Green
    }
    else {
        Write-Host "[X] WARNING: Service still missing --config parameter" -ForegroundColor Red
    }
}
catch {
    Write-Host "ERROR: Failed to update registry: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Verify with sc.exe
Write-Host ""
Write-Host "Verifying with sc.exe..." -ForegroundColor Yellow
$serviceQuery = & sc.exe qc $serviceName 2>&1
if ($LASTEXITCODE -eq 0) {
    $scBinPath = ($serviceQuery | Select-String "BINARY_PATH_NAME\s*:\s*(.+)").Matches.Groups[1].Value.Trim()
    Write-Host "sc.exe reports binPath:" -ForegroundColor Gray
    Write-Host "  $scBinPath" -ForegroundColor Gray
    
    if ($scBinPath -match '--config') {
        Write-Host "[OK] sc.exe confirms --config parameter is present" -ForegroundColor Green
    }
}

# Start service
Write-Host ""
Write-Host "Starting service..." -ForegroundColor Yellow
try {
    Start-Service -Name $serviceName -ErrorAction Stop
    Write-Host "Service started" -ForegroundColor Green
    Start-Sleep -Seconds 5
    
    # Check process
    $process = Get-Process -Name "velociraptor" -ErrorAction SilentlyContinue
    if ($process) {
        $cmdLine = (Get-WmiObject Win32_Process -Filter "ProcessId=$($process.Id)").CommandLine
        Write-Host ""
        Write-Host "Process command line:" -ForegroundColor Gray
        Write-Host "  $cmdLine" -ForegroundColor Gray
        
        if ($cmdLine -match '--config') {
            Write-Host "[OK] Process has --config parameter" -ForegroundColor Green
        }
        else {
            Write-Host "[X] Process missing --config parameter!" -ForegroundColor Red
        }
    }
    else {
        Write-Host "WARNING: Process not found after start" -ForegroundColor Yellow
    }
    
    # Check ports
    Write-Host ""
    Write-Host "Checking ports (waiting 3 more seconds)..." -ForegroundColor Yellow
    Start-Sleep -Seconds 3
    $port8889 = netstat -ano | findstr ":8889" | findstr "LISTENING"
    $port8000 = netstat -ano | findstr ":8000" | findstr "LISTENING"
    
    if ($port8889) {
        Write-Host "Port 8889: LISTENING" -ForegroundColor Green
        $port8889 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    }
    else {
        Write-Host "Port 8889: NOT LISTENING" -ForegroundColor Red
    }
    
    if ($port8000) {
        Write-Host "Port 8000: LISTENING" -ForegroundColor Green
        $port8000 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    }
    else {
        Write-Host "Port 8000: NOT LISTENING" -ForegroundColor Red
    }
}
catch {
    Write-Host "ERROR: Failed to start service: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Complete ===" -ForegroundColor Cyan

