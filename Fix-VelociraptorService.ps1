<#
.SYNOPSIS
    Fixes Velociraptor service to use the correct server executable

.DESCRIPTION
    Stops and removes the incorrectly configured Velociraptor service,
    then reinstalls it pointing to the server executable and configuration.

.PARAMETER ServerPath
    Path to the Velociraptor Server installation directory
    Default: "C:\Program Files\Velociraptor Server"

.PARAMETER ConfigFile
    Name of the server configuration file
    Default: "server.config.yaml"

.EXAMPLE
    .\Fix-VelociraptorService.ps1
    
.EXAMPLE
    .\Fix-VelociraptorService.ps1 -ServerPath "D:\Velociraptor Server" -ConfigFile "server.config.yaml"
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

Write-Host "=== Fixing Velociraptor Service Configuration ===" -ForegroundColor Cyan
Write-Host ""

# Verify server path exists
$serverExe = Join-Path $ServerPath "velociraptor.exe"
$configPath = Join-Path $ServerPath $ConfigFile

if (-not (Test-Path $serverExe)) {
    Write-Host "ERROR: Server executable not found at: $serverExe" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $configPath)) {
    Write-Host "ERROR: Configuration file not found at: $configPath" -ForegroundColor Red
    exit 1
}

Write-Host "Server executable: $serverExe" -ForegroundColor Green
Write-Host "Configuration file: $configPath" -ForegroundColor Green
Write-Host ""

# Step 1: Check current service status
Write-Host "Step 1: Checking current service status..." -ForegroundColor Yellow
$service = Get-Service -Name "Velociraptor" -ErrorAction SilentlyContinue
if ($service) {
    Write-Host "   Service found: $($service.Name) - Status: $($service.Status)" -ForegroundColor Gray
    
    # Check current binary path
    $serviceQuery = sc.exe qc Velociraptor 2>&1
    if ($LASTEXITCODE -eq 0) {
        $binaryPath = ($serviceQuery | Select-String "BINARY_PATH_NAME\s*:\s*(.+)").Matches.Groups[1].Value.Trim()
        Write-Host "   Current binary path: $binaryPath" -ForegroundColor Gray
        
        if ($binaryPath -like "*Velociraptor Server*") {
            Write-Host "   [OK] Service is already configured correctly!" -ForegroundColor Green
            Write-Host "   No changes needed." -ForegroundColor Green
            exit 0
        }
    }
    
    # Step 2: Stop the service
    Write-Host ""
    Write-Host "Step 2: Stopping Velociraptor service..." -ForegroundColor Yellow
    if ($service.Status -eq 'Running') {
        try {
            Stop-Service -Name "Velociraptor" -Force -ErrorAction Stop
            Write-Host "   Service stopped successfully" -ForegroundColor Green
            
            # Wait a moment for the service to fully stop
            Start-Sleep -Seconds 2
        }
        catch {
            Write-Host "   ERROR: Failed to stop service: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "   Attempting to continue anyway..." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "   Service is already stopped" -ForegroundColor Gray
    }
    
    # Step 3: Delete the service
    Write-Host ""
    Write-Host "Step 3: Removing incorrectly configured service..." -ForegroundColor Yellow
    try {
        $deleteResult = sc.exe delete Velociraptor 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   Service removed successfully" -ForegroundColor Green
            Start-Sleep -Seconds 2
        }
        else {
            Write-Host "   WARNING: Service deletion returned exit code $LASTEXITCODE" -ForegroundColor Yellow
            Write-Host "   Output: $deleteResult" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "   ERROR: Failed to delete service: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "   No existing Velociraptor service found" -ForegroundColor Gray
}

# Step 4: Verify config file bind address
Write-Host ""
Write-Host "Step 4: Verifying configuration file..." -ForegroundColor Yellow
$configContent = Get-Content $configPath -Raw
$needsConfigFix = $false

if ($configContent -match 'GUI:[\s\S]*?bind_address:\s*([^\s\r\n]+)') {
    $guiBindAddress = $matches[1].Trim()
    Write-Host "   GUI bind address: $guiBindAddress" -ForegroundColor Gray
    
    if ($guiBindAddress -eq '127.0.0.1' -or $guiBindAddress -eq 'localhost') {
        Write-Host "   WARNING: GUI is bound to localhost only!" -ForegroundColor Yellow
        Write-Host "   Would you like to change it to 0.0.0.0 for remote access? (Y/N)" -ForegroundColor Yellow
        $response = Read-Host
        if ($response -eq 'Y' -or $response -eq 'y') {
            Write-Host "   Updating GUI bind address to 0.0.0.0..." -ForegroundColor Yellow
            $configContent = $configContent -replace '(GUI:[\s\S]*?bind_address:\s*)(127\.0\.0\.1|localhost)', '$10.0.0.0'
            $configContent | Set-Content $configPath -NoNewline
            Write-Host "   Configuration updated" -ForegroundColor Green
        }
    }
    elseif ($guiBindAddress -eq '0.0.0.0') {
        Write-Host "   [OK] GUI bind address is correct (0.0.0.0)" -ForegroundColor Green
    }
}

# Step 5: Install service with correct path
Write-Host ""
Write-Host "Step 5: Installing service with correct server executable..." -ForegroundColor Yellow
Push-Location $ServerPath
try {
    $installArgs = @("--config", $ConfigFile, "service", "install")
    Write-Host "   Running: .\velociraptor.exe $($installArgs -join ' ')" -ForegroundColor Gray
    
    $output = & $serverExe $installArgs 2>&1
    $exitCode = $LASTEXITCODE
    
    if ($exitCode -eq 0) {
        Write-Host "   Service installed successfully" -ForegroundColor Green
    }
    else {
        Write-Host "   ERROR: Service installation failed with exit code $exitCode" -ForegroundColor Red
        Write-Host "   Output:" -ForegroundColor Yellow
        $output | ForEach-Object { Write-Host "     $_" -ForegroundColor Gray }
        Pop-Location
        exit 1
    }
    
    if ($output) {
        Write-Host "   Installation output:" -ForegroundColor Gray
        $output | ForEach-Object { Write-Host "     $_" -ForegroundColor Gray }
    }
}
catch {
    Write-Host "   ERROR: Failed to install service: $($_.Exception.Message)" -ForegroundColor Red
    Pop-Location
    exit 1
}
finally {
    Pop-Location
}

# Step 6: Verify service configuration
Write-Host ""
Write-Host "Step 6: Verifying service configuration..." -ForegroundColor Yellow
Start-Sleep -Seconds 2
$serviceQuery = sc.exe qc Velociraptor 2>&1
if ($LASTEXITCODE -eq 0) {
    $binaryPath = ($serviceQuery | Select-String "BINARY_PATH_NAME\s*:\s*(.+)").Matches.Groups[1].Value.Trim()
    Write-Host "   Service binary path: $binaryPath" -ForegroundColor Gray
    
    if ($binaryPath -like "*Velociraptor Server*") {
        Write-Host "   [OK] Service is now configured correctly!" -ForegroundColor Green
    }
    else {
        Write-Host "   WARNING: Service path still doesn't look correct" -ForegroundColor Yellow
        Write-Host "   Please verify manually: sc.exe qc Velociraptor" -ForegroundColor Yellow
    }
}
else {
    Write-Host "   WARNING: Could not verify service configuration" -ForegroundColor Yellow
}

# Step 7: Start the service
Write-Host ""
Write-Host "Step 7: Starting Velociraptor service..." -ForegroundColor Yellow
try {
    Start-Service -Name "Velociraptor" -ErrorAction Stop
    Write-Host "   Service started successfully" -ForegroundColor Green
    
    # Wait a moment for the service to start
    Start-Sleep -Seconds 3
    
    # Verify it's running
    $service.Refresh()
    if ($service.Status -eq 'Running') {
        Write-Host "   [OK] Service is running" -ForegroundColor Green
    }
    else {
        Write-Host "   WARNING: Service status is $($service.Status)" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "   ERROR: Failed to start service: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   You may need to start it manually: Start-Service -Name 'Velociraptor'" -ForegroundColor Yellow
}

# Step 8: Final verification
Write-Host ""
Write-Host "Step 8: Final verification..." -ForegroundColor Yellow
$process = Get-Process -Name "velociraptor" -ErrorAction SilentlyContinue
if ($process) {
    Write-Host "   Process found: PID $($process.Id)" -ForegroundColor Green
    Write-Host "   Process path: $($process.Path)" -ForegroundColor Gray
    
    if ($process.Path -like "*Velociraptor Server*") {
        Write-Host "   [OK] Correct SERVER executable is running!" -ForegroundColor Green
    }
    else {
        Write-Host "   [X] Process is still running from wrong path!" -ForegroundColor Red
        Write-Host "   Please restart the service: Restart-Service -Name 'Velociraptor'" -ForegroundColor Yellow
    }
}
else {
    Write-Host "   WARNING: No velociraptor process found" -ForegroundColor Yellow
    Write-Host "   Service may still be starting, or there may be an issue" -ForegroundColor Yellow
}

# Check ports
Write-Host ""
Write-Host "Checking if ports are listening..." -ForegroundColor Yellow
$ports = @(8000, 8889)
foreach ($port in $ports) {
    $listening = netstat -ano | findstr ":$port" | findstr "LISTENING"
    if ($listening) {
        Write-Host "   Port ${port}: LISTENING" -ForegroundColor Green
    }
    else {
        Write-Host "   Port ${port}: NOT LISTENING (may take a few seconds to start)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=== Service Fix Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Wait a few seconds for the service to fully start" -ForegroundColor White
Write-Host "  2. Run diagnostic script: .\Test-VelociraptorServer.ps1" -ForegroundColor White
Write-Host "  3. Try accessing the web GUI: https://<server-ip>:8889" -ForegroundColor White
Write-Host ""

