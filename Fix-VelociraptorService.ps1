<#
.SYNOPSIS
    Fixes Velociraptor Windows service to work properly

.DESCRIPTION
    Since frontend mode works but service mode doesn't, this script fixes the service
    configuration to ensure it runs correctly as a Windows service.

.PARAMETER ServerPath
    Path to the Velociraptor Server installation directory
    Default: "C:\Program Files\Velociraptor Server"

.PARAMETER ConfigFile
    Name of the server configuration file
    Default: "server.config.yaml"

.EXAMPLE
    .\Fix-VelociraptorService.ps1
#>

param(
    [string]$ServerPath = "C:\Program Files\Velociraptor Server",
    [string]$ConfigFile = "server.config.yaml"
)

# Require admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERROR: This script requires Administrator privileges!" -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
    exit 1
}

Write-Host "=== Fixing Velociraptor Service ===" -ForegroundColor Cyan
Write-Host ""

$serverExe = Join-Path $ServerPath "velociraptor.exe"
$configPath = Join-Path $ServerPath $ConfigFile
$serviceName = "Velociraptor"

# Verify paths
if (-not (Test-Path $serverExe)) {
    Write-Host "ERROR: Server executable not found at: $serverExe" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $configPath)) {
    Write-Host "ERROR: Configuration file not found at: $configPath" -ForegroundColor Red
    exit 1
}

# Step 1: Stop service and processes
Write-Host "Step 1: Stopping service and processes..." -ForegroundColor Yellow
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

# Step 3: Install service using Velociraptor's command
Write-Host ""
Write-Host "Step 3: Installing service..." -ForegroundColor Yellow
Push-Location $ServerPath
try {
    $installArgs = @("--config", $ConfigFile, "service", "install")
    Write-Host "Running: .\velociraptor.exe $($installArgs -join ' ')" -ForegroundColor Gray
    $output = & $serverExe $installArgs 2>&1
    $exitCode = $LASTEXITCODE
    
    if ($exitCode -ne 0) {
        Write-Host "ERROR: Service installation failed" -ForegroundColor Red
        Write-Host "Output: $output" -ForegroundColor Gray
        Pop-Location
        exit 1
    }
    Write-Host "Service installed successfully" -ForegroundColor Green
}
finally {
    Pop-Location
}

# Step 4: Fix binPath via registry to ensure --config parameter is included
Write-Host ""
Write-Host "Step 4: Verifying and fixing service binPath..." -ForegroundColor Yellow
Start-Sleep -Seconds 2

$regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
$correctBinPath = "`"$serverExe`" --config `"$configPath`" service run"

try {
    $currentBinPath = (Get-ItemProperty -Path $regPath -Name "ImagePath" -ErrorAction SilentlyContinue).ImagePath
    
    if ($currentBinPath -notmatch '--config') {
        Write-Host "Updating binPath to include --config parameter..." -ForegroundColor Yellow
        Set-ItemProperty -Path $regPath -Name "ImagePath" -Value $correctBinPath -ErrorAction Stop
        Write-Host "binPath updated via registry" -ForegroundColor Green
    }
    else {
        Write-Host "[OK] Service already has --config parameter" -ForegroundColor Green
    }
    
    # Verify
    $finalBinPath = (Get-ItemProperty -Path $regPath -Name "ImagePath").ImagePath
    Write-Host "Final binPath: $finalBinPath" -ForegroundColor Gray
}
catch {
    Write-Host "ERROR: Failed to update binPath: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Step 5: Configure service
Write-Host ""
Write-Host "Step 5: Configuring service..." -ForegroundColor Yellow
sc.exe config $serviceName start= auto | Out-Null
sc.exe description $serviceName "Velociraptor Server" | Out-Null
sc.exe failure $serviceName reset= 86400 actions= restart/60000/restart/60000/restart/60000 | Out-Null
Write-Host "Service configured" -ForegroundColor Green

# Step 6: Start service
Write-Host ""
Write-Host "Step 6: Starting service..." -ForegroundColor Yellow
try {
    Start-Service -Name $serviceName -ErrorAction Stop
    Write-Host "Service started" -ForegroundColor Green
    Start-Sleep -Seconds 5
    
    # Check if process is running
    $process = Get-Process -Name "velociraptor" -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "Process running: PID $($process.Id)" -ForegroundColor Green
        
        $cmdLine = (Get-WmiObject Win32_Process -Filter "ProcessId=$($process.Id)").CommandLine
        Write-Host "Command line: $cmdLine" -ForegroundColor Gray
        
        if ($cmdLine -match '--config') {
            Write-Host "[OK] Process has --config parameter" -ForegroundColor Green
        }
    }
    
    # Check ports
    Write-Host ""
    Write-Host "Checking ports..." -ForegroundColor Yellow
    Start-Sleep -Seconds 3
    $port8889 = Get-NetTCPConnection -LocalPort 8889 -State Listen -ErrorAction SilentlyContinue
    $port8000 = Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue
    
    if ($port8889) {
        Write-Host "Port 8889: LISTENING" -ForegroundColor Green
    }
    else {
        Write-Host "Port 8889: NOT LISTENING" -ForegroundColor Red
        Write-Host "Service may need more time to start, or check Windows Event Log for errors" -ForegroundColor Yellow
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
    Write-Host "Check Windows Event Log: Get-EventLog -LogName Application -Source '*Velociraptor*' -Newest 10" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Fix Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "If ports are not listening, check:" -ForegroundColor Yellow
Write-Host "  1. Windows Event Log for errors" -ForegroundColor White
Write-Host "  2. Service logs in: $ServerPath\Logs" -ForegroundColor White
Write-Host "  3. Try running manually: .\velociraptor.exe --config server.config.yaml frontend" -ForegroundColor White
Write-Host ""
