<#
.SYNOPSIS
    Fixes the Velociraptor service to include the --config parameter
#>

$serverPath = "C:\Program Files\Velociraptor Server"
$serverExe = Join-Path $serverPath "velociraptor.exe"
$configPath = Join-Path $serverPath "server.config.yaml"
$serviceName = "Velociraptor"

Write-Host "=== Fixing Velociraptor Service Configuration ===" -ForegroundColor Cyan
Write-Host ""

# Stop any running process
Write-Host "Step 1: Stopping any running Velociraptor processes..." -ForegroundColor Yellow
$processes = Get-Process -Name "velociraptor" -ErrorAction SilentlyContinue
if ($processes) {
    $processes | Stop-Process -Force
    Write-Host "   Stopped $($processes.Count) process(es)" -ForegroundColor Green
    Start-Sleep -Seconds 2
}
else {
    Write-Host "   No processes found" -ForegroundColor Gray
}

# Remove existing service if it exists
Write-Host ""
Write-Host "Step 2: Removing existing service (if any)..." -ForegroundColor Yellow
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service) {
    if ($service.Status -eq 'Running') {
        Stop-Service -Name $serviceName -Force
        Start-Sleep -Seconds 2
    }
    sc.exe delete $serviceName | Out-Null
    Write-Host "   Service removed" -ForegroundColor Green
    Start-Sleep -Seconds 2
}
else {
    Write-Host "   No existing service found" -ForegroundColor Gray
}

# Install service with correct config path using sc.exe
Write-Host ""
Write-Host "Step 3: Installing service with correct configuration..." -ForegroundColor Yellow

# The binPath must include the --config parameter
$binPath = "`"$serverExe`" --config `"$configPath`" service run"
Write-Host "   binPath: $binPath" -ForegroundColor Gray

# Use sc.exe to create the service
$createResult = & sc.exe create $serviceName binPath= $binPath start= auto DisplayName= "Velociraptor" 2>&1
$createExitCode = $LASTEXITCODE

if ($createExitCode -eq 0) {
    Write-Host "   Service created successfully" -ForegroundColor Green
    
    # Set description
    & sc.exe description $serviceName "Velociraptor Server" | Out-Null
    
    # Configure failure actions
    & sc.exe failure $serviceName reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
    
    Write-Host "   Service configured" -ForegroundColor Green
}
else {
    Write-Host "   ERROR: Failed to create service" -ForegroundColor Red
    Write-Host "   Output: $createResult" -ForegroundColor Gray
    
    # Try alternative method - use Velociraptor's service install
    Write-Host ""
    Write-Host "   Trying Velociraptor's service install..." -ForegroundColor Yellow
    Push-Location $serverPath
    try {
        $installArgs = @("--config", "server.config.yaml", "service", "install")
        $output = & $serverExe $installArgs 2>&1
        $exitCode = $LASTEXITCODE
        
        if ($exitCode -ne 0) {
            Write-Host "   ERROR: Velociraptor service install also failed" -ForegroundColor Red
            Write-Host "   Output: $output" -ForegroundColor Gray
            Pop-Location
            exit 1
        }
        else {
            Write-Host "   Service installed via Velociraptor command" -ForegroundColor Green
            
            # But we still need to fix the binPath if it's missing --config
            $serviceQuery = & sc.exe qc $serviceName 2>&1
            if ($LASTEXITCODE -eq 0) {
                $currentBinPath = ($serviceQuery | Select-String "BINARY_PATH_NAME\s*:\s*(.+)").Matches.Groups[1].Value.Trim()
                Write-Host "   Current binPath: $currentBinPath" -ForegroundColor Gray
                
                if ($currentBinPath -notmatch '--config') {
                    Write-Host "   WARNING: binPath is missing --config parameter!" -ForegroundColor Yellow
                    Write-Host "   Updating service binPath..." -ForegroundColor Yellow
                    
                    # Stop service
                    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                    
                    # Update binPath
                    $updateResult = & sc.exe config $serviceName binPath= $binPath 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "   binPath updated successfully" -ForegroundColor Green
                    }
                    else {
                        Write-Host "   ERROR: Failed to update binPath" -ForegroundColor Red
                        Write-Host "   Output: $updateResult" -ForegroundColor Gray
                    }
                }
            }
        }
    }
    finally {
        Pop-Location
    }
}

# Verify service configuration
Write-Host ""
Write-Host "Step 4: Verifying service configuration..." -ForegroundColor Yellow
$serviceQuery = & sc.exe qc $serviceName 2>&1
if ($LASTEXITCODE -eq 0) {
    $finalBinPath = ($serviceQuery | Select-String "BINARY_PATH_NAME\s*:\s*(.+)").Matches.Groups[1].Value.Trim()
    Write-Host "   Final binPath: $finalBinPath" -ForegroundColor Gray
    
    if ($finalBinPath -match '--config') {
        Write-Host "   [OK] Service includes --config parameter" -ForegroundColor Green
    }
    else {
        Write-Host "   [X] WARNING: Service is missing --config parameter!" -ForegroundColor Red
    }
}
else {
    Write-Host "   WARNING: Could not query service" -ForegroundColor Yellow
}

# Start the service
Write-Host ""
Write-Host "Step 5: Starting service..." -ForegroundColor Yellow
try {
    Start-Service -Name $serviceName -ErrorAction Stop
    Write-Host "   Service started" -ForegroundColor Green
    Start-Sleep -Seconds 3
    
    # Verify process
    $process = Get-Process -Name "velociraptor" -ErrorAction SilentlyContinue
    if ($process) {
        $cmdLine = (Get-WmiObject Win32_Process -Filter "ProcessId=$($process.Id)").CommandLine
        Write-Host "   Process command line: $cmdLine" -ForegroundColor Gray
        
        if ($cmdLine -match '--config') {
            Write-Host "   [OK] Process has --config parameter" -ForegroundColor Green
        }
        else {
            Write-Host "   [X] Process is missing --config parameter!" -ForegroundColor Red
        }
    }
}
catch {
    Write-Host "   ERROR: Failed to start service: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Fix Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Check if ports are listening:" -ForegroundColor Yellow
Write-Host "  netstat -ano | findstr ':8889'" -ForegroundColor White
Write-Host "  netstat -ano | findstr ':8000'" -ForegroundColor White
Write-Host ""

