<#
.SYNOPSIS
    Fix Velociraptor service binPath using WMI (bypasses sc.exe issues)
#>

$serviceName = "Velociraptor"
$serverExe = "C:\Program Files\Velociraptor Server\velociraptor.exe"
$configPath = "C:\Program Files\Velociraptor Server\server.config.yaml"
$binPath = "`"$serverExe`" --config `"$configPath`" service run"

Write-Host "=== Fixing Service BinPath ===" -ForegroundColor Cyan
Write-Host ""

# Stop service first
Write-Host "Stopping service..." -ForegroundColor Yellow
Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
Get-Process -Name "velociraptor" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Use WMI to modify the service
Write-Host "Updating service binPath using WMI..." -ForegroundColor Yellow
Write-Host "New binPath: $binPath" -ForegroundColor Gray

try {
    $service = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'"
    if ($service) {
        $result = $service.Change($null, $null, $null, $null, $null, $null, $binPath, $null, $null, $null, $null)
        
        if ($result.ReturnValue -eq 0) {
            Write-Host "Service binPath updated successfully!" -ForegroundColor Green
            
            # Verify
            $service.Refresh()
            Write-Host "Updated PathName: $($service.PathName)" -ForegroundColor Gray
            
            if ($service.PathName -match '--config') {
                Write-Host "[OK] Service now includes --config parameter" -ForegroundColor Green
            }
            else {
                Write-Host "[X] WARNING: Service still missing --config parameter" -ForegroundColor Red
            }
        }
        else {
            Write-Host "ERROR: Failed to update service. Return code: $($result.ReturnValue)" -ForegroundColor Red
            exit 1
        }
    }
    else {
        Write-Host "ERROR: Service '$serviceName' not found" -ForegroundColor Red
        exit 1
    }
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
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
        Write-Host "Process command line: $cmdLine" -ForegroundColor Gray
        
        if ($cmdLine -match '--config') {
            Write-Host "[OK] Process has --config parameter" -ForegroundColor Green
        }
        else {
            Write-Host "[X] Process missing --config parameter!" -ForegroundColor Red
        }
    }
    
    # Check ports
    Write-Host ""
    Write-Host "Checking ports..." -ForegroundColor Yellow
    Start-Sleep -Seconds 3
    $port8889 = netstat -ano | findstr ":8889" | findstr "LISTENING"
    $port8000 = netstat -ano | findstr ":8000" | findstr "LISTENING"
    
    if ($port8889) {
        Write-Host "Port 8889: LISTENING" -ForegroundColor Green
    }
    else {
        Write-Host "Port 8889: NOT LISTENING" -ForegroundColor Red
    }
    
    if ($port8000) {
        Write-Host "Port 8000: LISTENING" -ForegroundColor Green
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

