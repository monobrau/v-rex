<#
.SYNOPSIS
    Reinstall Velociraptor service with all fixes applied
#>

$serverPath = "C:\Program Files\Velociraptor Server"
$configPath = Join-Path $serverPath "server.config.yaml"
$serverExe = Join-Path $serverPath "velociraptor.exe"
$serviceName = "Velociraptor"

Write-Host "=== Reinstalling Velociraptor Service ===" -ForegroundColor Cyan
Write-Host ""

# Step 1: Stop everything
Write-Host "Step 1: Stopping all processes..." -ForegroundColor Yellow
Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
Get-Process -Name "velociraptor" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Step 2: Remove existing service
Write-Host ""
Write-Host "Step 2: Removing existing service..." -ForegroundColor Yellow
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service) {
    sc.exe delete $serviceName | Out-Null
    Start-Sleep -Seconds 2
    Write-Host "Service removed" -ForegroundColor Green
}
else {
    Write-Host "No existing service found" -ForegroundColor Gray
}

# Step 3: Verify config file
Write-Host ""
Write-Host "Step 3: Verifying config file..." -ForegroundColor Yellow
if (-not (Test-Path $configPath)) {
    Write-Host "ERROR: Config file not found at $configPath" -ForegroundColor Red
    exit 1
}

Push-Location $serverPath
try {
    $validateOutput = & $serverExe --config server.config.yaml config show 2>&1
    $validateExit = $LASTEXITCODE
    
    if ($validateExit -eq 0) {
        Write-Host "Config file is valid" -ForegroundColor Green
    }
    else {
        Write-Host "ERROR: Config file validation failed:" -ForegroundColor Red
        $validateOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        Pop-Location
        exit 1
    }
}
catch {
    Write-Host "ERROR: Could not validate config: $($_.Exception.Message)" -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location

# Step 4: Install service using Velociraptor command
Write-Host ""
Write-Host "Step 4: Installing service..." -ForegroundColor Yellow
Push-Location $serverPath
try {
    $installArgs = @("--config", "server.config.yaml", "service", "install")
    Write-Host "Running: .\velociraptor.exe $($installArgs -join ' ')" -ForegroundColor Gray
    $output = & $serverExe $installArgs 2>&1
    $exitCode = $LASTEXITCODE
    
    if ($exitCode -ne 0) {
        Write-Host "ERROR: Service installation failed" -ForegroundColor Red
        Write-Host "Output: $output" -ForegroundColor Gray
        Pop-Location
        exit 1
    }
    else {
        Write-Host "Service installed successfully" -ForegroundColor Green
        if ($output) {
            Write-Host "Installation output:" -ForegroundColor Gray
            $output | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        }
    }
}
finally {
    Pop-Location
}

# Step 5: Fix binPath to include --config parameter
Write-Host ""
Write-Host "Step 5: Fixing service binPath..." -ForegroundColor Yellow
Start-Sleep -Seconds 2

$serviceQuery = & sc.exe qc $serviceName 2>&1
if ($LASTEXITCODE -eq 0) {
    $binPath = ($serviceQuery | Select-String "BINARY_PATH_NAME\s*:\s*(.+)").Matches.Groups[1].Value.Trim()
    Write-Host "Current binPath: $binPath" -ForegroundColor Gray
    
        if ($binPath -notmatch '--config') {
        Write-Host "Updating binPath to include --config..." -ForegroundColor Yellow
        
        # Stop service first if it's running
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') {
            Write-Host "Stopping service to apply registry changes..." -ForegroundColor Gray
            Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
            Get-Process -Name "velociraptor" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        
        $correctBinPath = "`"$serverExe`" --config `"$configPath`" service run"
        
        # Use registry method
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
        try {
            Set-ItemProperty -Path $regPath -Name "ImagePath" -Value $correctBinPath -ErrorAction Stop
            Write-Host "binPath updated via registry" -ForegroundColor Green
            
            # Verify
            $newBinPath = (Get-ItemProperty -Path $regPath -Name "ImagePath").ImagePath
            Write-Host "Updated binPath: $newBinPath" -ForegroundColor Gray
            
            if ($newBinPath -match '--config') {
                Write-Host "[OK] Service now includes --config parameter" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "ERROR: Failed to update binPath: $($_.Exception.Message)" -ForegroundColor Red
            exit 1
        }
    }
    else {
        Write-Host "[OK] Service already has --config parameter" -ForegroundColor Green
    }
}
else {
    Write-Host "WARNING: Could not query service" -ForegroundColor Yellow
}

# Step 6: Start service
Write-Host ""
Write-Host "Step 6: Starting service..." -ForegroundColor Yellow
try {
    Start-Service -Name $serviceName -ErrorAction Stop
    Write-Host "Service started" -ForegroundColor Green
    Start-Sleep -Seconds 8
    
    # Check process
    $process = Get-Process -Name "velociraptor" -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "Process running: PID $($process.Id)" -ForegroundColor Green
        
        $cmdLine = (Get-WmiObject Win32_Process -Filter "ProcessId=$($process.Id)").CommandLine
        Write-Host "Command line: $cmdLine" -ForegroundColor Gray
        
        if ($cmdLine -match '--config') {
            Write-Host "[OK] Process has --config parameter" -ForegroundColor Green
        }
        else {
            Write-Host "[X] Process missing --config parameter!" -ForegroundColor Red
        }
    }
    else {
        Write-Host "WARNING: Process not found after start" -ForegroundColor Yellow
        Write-Host "Service may have crashed. Check Windows Event Log." -ForegroundColor Yellow
    }
    
    # Check ports
    Write-Host ""
    Write-Host "Checking ports..." -ForegroundColor Yellow
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
    
    if (-not $port8889 -and -not $port8000) {
        Write-Host ""
        Write-Host "Ports are not listening. Possible issues:" -ForegroundColor Yellow
        Write-Host "  1. Service is crashing on startup" -ForegroundColor White
        Write-Host "  2. Config file has errors preventing port binding" -ForegroundColor White
        Write-Host "  3. Ports are already in use by another process" -ForegroundColor White
        Write-Host ""
        Write-Host "Check Windows Event Log:" -ForegroundColor Yellow
        Write-Host "  Get-EventLog -LogName Application -Source '*Velociraptor*' -Newest 10" -ForegroundColor White
    }
}
catch {
    Write-Host "ERROR: Failed to start service: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Reinstallation Complete ===" -ForegroundColor Cyan

