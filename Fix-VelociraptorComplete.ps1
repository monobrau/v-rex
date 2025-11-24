<#
.SYNOPSIS
    Complete fix for Velociraptor service - fixes config path and temp directory
#>

$serverPath = "C:\Program Files\Velociraptor Server"
$configPath = Join-Path $serverPath "server.config.yaml"
$serverExe = Join-Path $serverPath "velociraptor.exe"
$serviceName = "Velociraptor"

Write-Host "=== Complete Velociraptor Fix ===" -ForegroundColor Cyan
Write-Host ""

# Step 1: Stop service and process
Write-Host "Step 1: Stopping service and processes..." -ForegroundColor Yellow
Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
Get-Process -Name "velociraptor" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Step 2: Fix config file - update tempdir_windows
Write-Host ""
Write-Host "Step 2: Fixing config file temp directory..." -ForegroundColor Yellow
$configLines = Get-Content $configPath
$configUpdated = $false
$inClientSection = $false

for ($i = 0; $i -lt $configLines.Count; $i++) {
    $line = $configLines[$i]
    
    if ($line -match '^Client:') {
        $inClientSection = $true
    }
    elseif ($inClientSection -and $line -match '^[A-Z]' -and $line -notmatch '^\s') {
        $inClientSection = $false
    }
    
    # Fix tempdir_windows
    if ($line -match '^\s+tempdir_windows:\s*(.+)$') {
        $currentTempDir = $matches[1].Trim()
        if ($currentTempDir -like "*Velociraptor\Tools*" -and $currentTempDir -notlike "*Velociraptor Server*") {
            Write-Host "   Found tempdir_windows: $currentTempDir" -ForegroundColor Gray
            $indent = if ($line -match '^(\s+)tempdir_windows:') { $matches[1] } else { "    " }
            $newTempDir = '$ProgramFiles\Velociraptor Server\Tools'
            $configLines[$i] = "${indent}tempdir_windows: $newTempDir"
            $configUpdated = $true
            Write-Host "   Updated to: $newTempDir" -ForegroundColor Green
        }
    }
}

if ($configUpdated) {
    $backupPath = "$configPath.backup.$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item $configPath $backupPath -Force
    Write-Host "   Backup created: $backupPath" -ForegroundColor Gray
    $configLines | Set-Content $configPath -Encoding UTF8
    Write-Host "   Config updated successfully" -ForegroundColor Green
}
else {
    Write-Host "   No temp directory changes needed" -ForegroundColor Gray
}

# Step 3: Remove existing service
Write-Host ""
Write-Host "Step 3: Removing existing service..." -ForegroundColor Yellow
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service) {
    sc.exe delete $serviceName | Out-Null
    Start-Sleep -Seconds 2
    Write-Host "   Service removed" -ForegroundColor Green
}

# Step 4: Create Tools directory if it doesn't exist
Write-Host ""
Write-Host "Step 4: Creating Tools directory..." -ForegroundColor Yellow
$toolsDir = Join-Path $serverPath "Tools"
if (-not (Test-Path $toolsDir)) {
    New-Item -Path $toolsDir -ItemType Directory -Force | Out-Null
    Write-Host "   Created: $toolsDir" -ForegroundColor Green
}
else {
    Write-Host "   Directory already exists: $toolsDir" -ForegroundColor Gray
}

# Step 5: Install service with correct config path
Write-Host ""
Write-Host "Step 5: Installing service with correct config path..." -ForegroundColor Yellow

# Use Velociraptor's service install command (it should now use the updated config)
Push-Location $serverPath
try {
    $installArgs = @("--config", "server.config.yaml", "service", "install")
    Write-Host "   Running: .\velociraptor.exe $($installArgs -join ' ')" -ForegroundColor Gray
    $output = & $serverExe $installArgs 2>&1
    $exitCode = $LASTEXITCODE
    
    if ($exitCode -ne 0) {
        Write-Host "   ERROR: Service installation failed" -ForegroundColor Red
        Write-Host "   Output: $output" -ForegroundColor Gray
        Pop-Location
        exit 1
    }
    else {
        Write-Host "   Service installed successfully" -ForegroundColor Green
    }
}
finally {
    Pop-Location
}

# Step 6: Verify and fix binPath if needed
Write-Host ""
Write-Host "Step 6: Verifying service configuration..." -ForegroundColor Yellow
Start-Sleep -Seconds 2
$serviceQuery = & sc.exe qc $serviceName 2>&1
if ($LASTEXITCODE -eq 0) {
    $binPath = ($serviceQuery | Select-String "BINARY_PATH_NAME\s*:\s*(.+)").Matches.Groups[1].Value.Trim()
    Write-Host "   Current binPath: $binPath" -ForegroundColor Gray
    
    if ($binPath -notmatch '--config') {
        Write-Host "   WARNING: binPath missing --config parameter!" -ForegroundColor Yellow
        Write-Host "   Updating binPath..." -ForegroundColor Yellow
        
        # Construct correct binPath
        $correctBinPath = "`"$serverExe`" --config `"$configPath`" service run"
        
        # Use sc.exe config with proper syntax
        # sc.exe requires: sc config ServiceName binPath= "path"
        $updateCmd = "sc.exe config $serviceName binPath= $correctBinPath"
        Write-Host "   Running: $updateCmd" -ForegroundColor Gray
        
        $updateResult = Invoke-Expression $updateCmd 2>&1
        $updateExitCode = $LASTEXITCODE
        
        if ($updateExitCode -eq 0) {
            Write-Host "   binPath updated successfully" -ForegroundColor Green
            
            # Verify
            $serviceQuery2 = & sc.exe qc $serviceName 2>&1
            $newBinPath = ($serviceQuery2 | Select-String "BINARY_PATH_NAME\s*:\s*(.+)").Matches.Groups[1].Value.Trim()
            Write-Host "   New binPath: $newBinPath" -ForegroundColor Gray
        }
        else {
            Write-Host "   ERROR: Failed to update binPath" -ForegroundColor Red
            Write-Host "   Output: $updateResult" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "   [OK] binPath includes --config parameter" -ForegroundColor Green
    }
}
else {
    Write-Host "   WARNING: Could not query service" -ForegroundColor Yellow
}

# Step 7: Start service
Write-Host ""
Write-Host "Step 7: Starting service..." -ForegroundColor Yellow
try {
    Start-Service -Name $serviceName -ErrorAction Stop
    Write-Host "   Service started" -ForegroundColor Green
    Start-Sleep -Seconds 5
    
    # Check if process is running
    $process = Get-Process -Name "velociraptor" -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "   Process running: PID $($process.Id)" -ForegroundColor Green
        
        # Check command line
        $cmdLine = (Get-WmiObject Win32_Process -Filter "ProcessId=$($process.Id)").CommandLine
        Write-Host "   Command line: $cmdLine" -ForegroundColor Gray
        
        if ($cmdLine -match '--config') {
            Write-Host "   [OK] Process has --config parameter" -ForegroundColor Green
        }
        else {
            Write-Host "   [X] Process missing --config parameter!" -ForegroundColor Red
        }
    }
    else {
        Write-Host "   WARNING: Process not found after start" -ForegroundColor Yellow
    }
    
    # Check ports
    Write-Host ""
    Write-Host "Checking ports..." -ForegroundColor Yellow
    Start-Sleep -Seconds 3
    $port8889 = netstat -ano | findstr ":8889" | findstr "LISTENING"
    $port8000 = netstat -ano | findstr ":8000" | findstr "LISTENING"
    
    if ($port8889) {
        Write-Host "   Port 8889: LISTENING" -ForegroundColor Green
    }
    else {
        Write-Host "   Port 8889: NOT LISTENING" -ForegroundColor Red
    }
    
    if ($port8000) {
        Write-Host "   Port 8000: LISTENING" -ForegroundColor Green
    }
    else {
        Write-Host "   Port 8000: NOT LISTENING" -ForegroundColor Red
    }
}
catch {
    Write-Host "   ERROR: Failed to start service: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Fix Complete ===" -ForegroundColor Cyan
Write-Host ""

